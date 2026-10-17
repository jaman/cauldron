defmodule Cauldron2D.Drafter.Client.Stage do
  @moduledoc """
  A graphics card drawing a client's scenes: a `CauldronGPU.Host` renderer, offscreen for
  pictures shown in the pane or in a window of its own, and the cache a scene's `:gpu`
  function keeps between ticks.

      {:ok, stage} = Stage.start(:pane, title: "Quake")
      # once {Stage, ^stage, :ready} has arrived:
      {:ok, raster} = Stage.picture(stage, scene.gpu, {960, 600}, 1.0)

  The process that starts a stage is its owner and receives `{Stage, stage, message}`:

    * `:ready` — the renderer has opened; `picture/4` and `draw/2` may be used
    * `{:failed, reason}` — it did not open, or stopped and could not be started again;
      the stage has stopped
    * `{:input, event}` — a key pressed or released in the window, as a terminal's drafter
      event (`Cauldron2D.Drafter.Client.WindowKeys`)
    * `:closed` — the window was closed; the stage has stopped

  A renderer process that exits is started again with the scene it had, so the cache
  stays good. The stage stops when its owner exits.
  """

  use GenServer

  require Logger

  @compile {:no_warn_undefined, [CauldronGPU.Host]}

  alias Cauldron2D.Drafter.Client.WindowKeys
  alias FrenchCurve.Raster

  @type t :: pid()
  @type mode :: :pane | :window
  @type gpu :: (term(), term(), {pos_integer(), pos_integer()}, number() -> {list(), term()})

  @pane_size {640, 360}
  @window_size {1280, 720}
  @picture_timeout 5_000

  @doc "Whether this build has `CauldronGPU` and a renderer to open."
  @spec available?() :: boolean()
  def available?,
    do: Code.ensure_loaded?(CauldronGPU.Host) and CauldronGPU.Host.backends() != []

  @doc """
  Starts a stage owned by the caller, opening its renderer in the background. Options:
  `:title` (the window's title).
  """
  @spec start(mode(), keyword()) :: {:ok, t()} | {:error, term()}
  def start(mode, opts \\ []) when mode in [:pane, :window] do
    if available?(),
      do: GenServer.start(__MODULE__, {mode, self(), opts}),
      else: {:error, "no graphics card renderer in this build"}
  end

  @doc """
  The scene `gpu` describes drawn at `size` pixels, as a raster. `{:error, reason}` when
  the renderer is not ready, the function raises, or no frame comes back in time.
  """
  @spec picture(t(), gpu(), {pos_integer(), pos_integer()}, number()) ::
          {:ok, Raster.t()} | {:error, term()}
  def picture(stage, gpu, size, aspect) do
    GenServer.call(stage, {:picture, gpu, size, aspect}, @picture_timeout + 1_000)
  catch
    :exit, reason -> {:error, reason}
  end

  @doc "Sends the scene `gpu` describes to the window. Ticks sent faster than they are drawn are dropped for the newest."
  @spec draw(t(), gpu()) :: :ok
  def draw(stage, gpu), do: GenServer.cast(stage, {:draw, gpu})

  @doc "Stops the stage, closing its renderer."
  @spec stop(t()) :: :ok
  def stop(stage) do
    GenServer.stop(stage)
  catch
    :exit, _reason -> :ok
  end

  @impl true
  def init({mode, owner, opts}) do
    Process.monitor(owner)

    {:ok,
     %{
       mode: mode,
       owner: owner,
       title: Keyword.get(opts, :title, "cauldron"),
       host: nil,
       size: if(mode == :window, do: @window_size, else: @pane_size),
       cache: nil,
       modifiers: []
     }, {:continue, :open}}
  end

  @impl true
  def handle_continue(:open, state) do
    {width, height} = state.size

    case CauldronGPU.Host.open(
           window: state.mode == :window,
           title: state.title,
           width: width,
           height: height,
           events: self()
         ) do
      {:ok, host} ->
        tell(state, :ready)
        {:noreply, %{state | host: host}}

      {:error, reason} ->
        tell(state, {:failed, reason})
        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_call({:picture, _gpu, _size, _aspect}, _from, %{host: nil} = state),
    do: {:reply, {:error, :not_ready}, state}

  def handle_call({:picture, gpu, size, aspect}, _from, state) do
    state = sized(state, size)

    with {:ok, state} <- described(state, gpu, aspect),
         {:ok, frame} <- CauldronGPU.Host.capture(state.host, @picture_timeout) do
      {:reply, {:ok, Raster.from_rgba(frame.width, frame.height, frame.pixels)}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:draw, _gpu}, %{host: nil} = state), do: {:noreply, state}

  def handle_cast({:draw, gpu}, state) do
    case described(state, newest(gpu), 1.0) do
      {:ok, state} -> {:noreply, state}
      {:error, _reason} -> {:noreply, state}
    end
  end

  @impl true
  def handle_info({:cauldron_gpu, _id, {:key, _direction, _name, _repeat?} = event}, state) do
    Enum.each(WindowKeys.events(event, state.modifiers), &tell(state, {:input, &1}))
    {:noreply, %{state | modifiers: WindowKeys.modifiers(event, state.modifiers)}}
  end

  def handle_info({:cauldron_gpu, _id, {:resized, width, height}}, state)
      when width > 0 and height > 0,
      do: {:noreply, %{state | size: {width, height}}}

  def handle_info({:cauldron_gpu, _id, {:focus, false}}, state) do
    Enum.each(state.modifiers, &release_modifier(state, &1))
    {:noreply, %{state | modifiers: []}}
  end

  def handle_info({:cauldron_gpu, _id, :close_requested}, state) do
    tell(state, :closed)
    {:stop, :normal, state}
  end

  def handle_info({:cauldron_gpu, _id, :renderer_exited}, state) do
    case CauldronGPU.Host.restart(state.host) do
      :ok ->
        {:noreply, state}

      {:error, reason} ->
        tell(state, {:failed, reason})
        {:stop, :normal, state}
    end
  end

  def handle_info({:cauldron_gpu, _id, {:error, message}}, state) do
    Logger.error("#{inspect(__MODULE__)} renderer rejected a change: #{message}")
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, owner, _reason}, %{owner: owner} = state),
    do: {:stop, :normal, state}

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{host: nil}), do: :ok
  def terminate(_reason, %{host: host}), do: CauldronGPU.Host.close(host)

  defp sized(%{size: size} = state, size), do: state

  defp sized(state, {width, height} = size) do
    case CauldronGPU.Host.resize(state.host, width, height) do
      :ok -> %{state | size: size}
      {:error, _reason} -> state
    end
  end

  defp described(state, gpu, aspect) do
    {changes, cache} = gpu.(state.host, state.cache, state.size, aspect)

    case CauldronGPU.Host.submit(state.host, changes) do
      :ok -> {:ok, %{state | cache: cache}}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error ->
      report(error, __STACKTRACE__)
      {:error, error}
  end

  defp newest(gpu) do
    receive do
      {:"$gen_cast", {:draw, newer}} -> newest(newer)
    after
      0 -> gpu
    end
  end

  defp release_modifier(state, modifier),
    do: tell(state, {:input, {:key_up, modifier_key(modifier), []}})

  defp modifier_key(:shift), do: :left_shift
  defp modifier_key(:ctrl), do: :left_control
  defp modifier_key(:alt), do: :left_alt

  defp tell(state, message), do: send(state.owner, {__MODULE__, self(), message})

  defp report(error, stacktrace) do
    message = Exception.message(error)
    seen = Process.get(__MODULE__, MapSet.new())

    unless MapSet.member?(seen, message) do
      Process.put(__MODULE__, MapSet.put(seen, message))

      Logger.error("""
      #{inspect(__MODULE__)} could not describe the scene for the graphics card, so the \
      game's own picture is drawn instead: #{message}
      #{Exception.format_stacktrace(stacktrace)}\
      """)
    end
  end
end
