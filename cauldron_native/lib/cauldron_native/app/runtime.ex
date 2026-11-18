defmodule CauldronNative.App.Runtime do
  @moduledoc """
  The process that runs a `CauldronNative.App`: it holds the app's state, renders it,
  sends the native side what changed, and turns the native side's events into the app's
  `c:CauldronNative.App.handle_event/3`.

  Answers to `CauldronNative.Device` requests arrive as `{:cauldron_native, :result, json}`
  and reach the app's `handle_info/2` as `{:device, tag, answer}`.

  The native side sends an event as `{:cauldron_native, :ui, json}`, the JSON
  `{"id": node id, "kind": "tap" | "change" | "submit" | "back" | …, "value": …}`. An
  event for a node or kind with no handler, or for a disabled node, is passed over. The
  window's size arrives as `{"window": {"width", "height", "compact"}}` and reaches the
  app's `handle_info/2` as `{:cauldron_native, :window, %{width, height, compact}}`.

  Options: `:app`, the module (required); `:params`, given to its `mount/1` (default
  `%{}`); `:send`, the function a patch's JSON is given to (default
  `CauldronNative.Native.ui/1`, after subscribing to the native side's events);
  `:name`. Without `:send`, outside a native app (`CauldronNative.available?/0`), it
  starts nothing and returns `:ignore`.
  """

  use GenServer

  alias CauldronNative.Device.Answer
  alias CauldronNative.Native
  alias CauldronNative.UI.{Tree, Value}

  @doc "Start running `:app`."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    if Keyword.has_key?(opts, :send) or CauldronNative.available?(),
      do: GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: [])),
      else: :ignore
  end

  @doc "The app's state, for tests and tools."
  @spec state(GenServer.server()) :: term()
  def state(runtime), do: GenServer.call(runtime, :state)

  @impl GenServer
  def init(opts) do
    app = Keyword.fetch!(opts, :app)
    send = Keyword.get_lazy(opts, :send, &native_send/0)
    state = app.mount(Keyword.get(opts, :params, %{}))
    {:ok, rendered(%{app: app, send: send, state: state, tree: Tree.empty()})}
  end

  @impl GenServer
  def handle_call(:state, _from, runtime), do: {:reply, runtime.state, runtime}

  @impl GenServer
  def handle_info({:cauldron_native, :ui, json}, runtime) do
    case event(runtime, json) do
      {:window, window} ->
        handle_info({:cauldron_native, :window, window}, runtime)

      nil ->
        {:noreply, runtime}

      {event, value} ->
        {:noreply, changed(runtime, runtime.app.handle_event(event, value, runtime.state))}
    end
  end

  def handle_info({:cauldron_native, :result, json}, runtime) do
    case Answer.decode(json) do
      :invalid -> {:noreply, runtime}
      answer -> handle_info(answer, runtime)
    end
  end

  def handle_info(message, runtime) do
    if function_exported?(runtime.app, :handle_info, 2),
      do: {:noreply, changed(runtime, runtime.app.handle_info(message, runtime.state))},
      else: {:noreply, runtime}
  end

  defp native_send do
    :ok = Native.subscribe(self())
    &Native.ui/1
  end

  defp event(runtime, json) do
    case JSON.decode(json) do
      {:ok, %{"window" => %{"width" => width, "height" => height} = window}} ->
        {:window, %{width: width, height: height, compact: Map.get(window, "compact", false)}}

      _other ->
        node_event(runtime, json)
    end
  end

  defp node_event(runtime, json) do
    with {:ok, %{"id" => id, "kind" => kind} = message} <- JSON.decode(json),
         false <- disabled?(runtime.tree, id),
         {event, decode} <- Tree.handler(runtime.tree, id, kind) do
      {event, Value.decode(decode, Map.get(message, "value"))}
    else
      _ignored -> nil
    end
  end

  defp disabled?(tree, id), do: get_in(tree.records, [id, "props", "disabled"]) == true

  defp changed(runtime, state), do: rendered(%{runtime | state: state})

  defp rendered(runtime) do
    tree = Tree.build(runtime.app.render(runtime.state))
    patch = Tree.diff(runtime.tree, tree)
    unless Tree.unchanged?(patch), do: runtime.send.(Tree.encode(patch))
    %{runtime | tree: tree}
  end
end
