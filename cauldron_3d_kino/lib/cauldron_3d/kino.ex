defmodule Cauldron3D.Kino do
  @moduledoc """
  A 3D scene as a Livebook cell. The cell's process keeps the scene; the browser draws
  it with three.js on the viewer's graphics card (`cauldron_3d_net`'s client), and
  nothing is drawn on the machine running the notebook.

      view = Cauldron3D.Kino.new(height: 420)
      cube = Cauldron3D.Kino.mesh(view, Cauldron3D.Scene.Mesh.cube(1.0))
      Cauldron3D.Kino.submit(view, [
        {:instance, 1, %Cauldron3D.Scene.Instance{mesh: cube}},
        %Cauldron3D.Scene.Camera{position: {0.0, 1.0, 4.0}}
      ])
      view

  A view is a `Cauldron3D.Scene.Target`, so the `cauldron_gpu` converters
  (`Cauldron3D.Scene.Bsp.upload/4` and the rest) upload to it as to a renderer. Changes are
  `Cauldron3D.Scene.Stream` changes. A browser opening the notebook later gets the whole
  scene, then every tick.

  Input on the cell arrives as the events `CauldronGPU`'s windows send
  (`Cauldron3D.Net.Events`). `events/1` is a stream of them for `Kino.listen/3`;
  `subscribe/1` sends them to a process instead.

  ## Options

    * `:height` — the cell's height in pixels. Default `480`
  """

  use Kino.JS
  use Kino.JS.Live

  alias Cauldron3D.Kino.Client
  alias Cauldron3D.Net.{Events, SceneState}
  alias Cauldron3D.Scene.{Canvas, Handle, Material, Mesh, Scatter, Stream, Texture}
  alias Kino.JS.Live

  @external_resource Client.path()

  @enforce_keys [:live]
  defstruct [:live]

  @type t :: %__MODULE__{live: Live.t()}
  @type client :: term()

  @doc "A view with an empty scene; see the module documentation for the options."
  @spec new(keyword()) :: t()
  def new(opts \\ []),
    do: %__MODULE__{live: Live.new(__MODULE__, Keyword.get(opts, :height, 480))}

  @doc "Sends one tick of changes to every browser showing the view and keeps them."
  @spec submit(t(), [Stream.change()]) :: :ok
  def submit(view, changes), do: Live.call(view.live, {:submit, changes})

  @doc "Uploads a mesh and returns its handle."
  @spec mesh(t(), Mesh.t()) :: Handle.t()
  def mesh(view, %Mesh{} = mesh), do: Live.call(view.live, {:put, :mesh, mesh})

  @doc "Uploads a texture and returns its handle."
  @spec texture(t(), Texture.t()) :: Handle.t()
  def texture(view, %Texture{} = texture), do: Live.call(view.live, {:put, :texture, texture})

  @doc "Makes a canvas and returns its handle, a texture's."
  @spec canvas(t(), Canvas.t()) :: Handle.t()
  def canvas(view, %Canvas{} = canvas), do: Live.call(view.live, {:put, :canvas, canvas})

  @doc "Defines a material and returns its handle."
  @spec material(t(), Material.t()) :: Handle.t()
  def material(view, %Material{} = material),
    do: Live.call(view.live, {:put, :material, material})

  @doc "Uploads a scatter and returns its handle."
  @spec scatter(t(), Scatter.t()) :: Handle.t()
  def scatter(view, %Scatter{} = scatter), do: Live.call(view.live, {:put, :scatter, scatter})

  @doc "Lets the view drop a mesh, texture or material once no scene entry uses it."
  @spec release(t(), Handle.t()) :: :ok
  def release(view, %Handle{} = handle), do: Live.call(view.live, {:release, handle})

  @doc """
  Sends the calling process the view's input as `{:cauldron_3d_kino, ref, client, event}`
  until `unsubscribe/2` or the process exits, answering `ref`. `client` names the
  browser the event came from.
  """
  @spec subscribe(t()) :: reference()
  def subscribe(view), do: Live.call(view.live, {:subscribe, self()})

  @doc "Stops the messages `subscribe/1` started."
  @spec unsubscribe(t(), reference()) :: :ok
  def unsubscribe(view, ref), do: Live.call(view.live, {:unsubscribe, ref})

  @doc """
  The view's input as a stream of `{client, event}`, read by the process that runs it.

      view
      |> Cauldron3D.Kino.events()
      |> Kino.listen(orbit, fn {_client, event}, orbit -> {:cont, Orbit.handle(orbit, event)} end)
  """
  @spec events(t()) :: Enumerable.t({client(), term()})
  def events(view) do
    Elixir.Stream.resource(
      fn -> subscribe(view) end,
      fn ref ->
        receive do
          {:cauldron_3d_kino, ^ref, client, event} -> {[{client, event}], ref}
        end
      end,
      &unsubscribe(view, &1)
    )
  end

  @impl true
  def init(height, ctx),
    do: {:ok, assign(ctx, height: height, scene: SceneState.new(), subscribers: %{})}

  @impl true
  def handle_connect(ctx) do
    snapshot = SceneState.snapshot(ctx.assigns.scene)
    {:ok, {:binary, %{height: ctx.assigns.height}, snapshot}, ctx}
  end

  @impl true
  def handle_call({:submit, changes}, _from, ctx) do
    {bytes, scene} = SceneState.submit(ctx.assigns.scene, changes)
    {:reply, :ok, ctx |> assign(scene: scene) |> broadcast(bytes)}
  end

  def handle_call({:put, kind, value}, _from, ctx) do
    {handle, bytes, scene} = SceneState.put(ctx.assigns.scene, kind, value)
    {:reply, handle, ctx |> assign(scene: scene) |> broadcast(bytes)}
  end

  def handle_call({:release, handle}, _from, ctx) do
    {bytes, scene} = SceneState.release(ctx.assigns.scene, handle)
    {:reply, :ok, ctx |> assign(scene: scene) |> broadcast(bytes)}
  end

  def handle_call({:subscribe, pid}, _from, ctx) do
    ref = Process.monitor(pid)
    {:reply, ref, assign(ctx, subscribers: Map.put(ctx.assigns.subscribers, ref, pid))}
  end

  def handle_call({:unsubscribe, ref}, _from, ctx) do
    Process.demonitor(ref, [:flush])
    {:reply, :ok, assign(ctx, subscribers: Map.delete(ctx.assigns.subscribers, ref))}
  end

  @impl true
  def handle_event("event", message, ctx) do
    with {:ok, event} <- Events.decode(message) do
      for {ref, pid} <- ctx.assigns.subscribers,
          do: send(pid, {:cauldron_3d_kino, ref, ctx.origin, event})
    end

    {:noreply, ctx}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, ctx),
    do: {:noreply, assign(ctx, subscribers: Map.delete(ctx.assigns.subscribers, ref))}

  defp broadcast(ctx, bytes) do
    broadcast_event(ctx, "changes", {:binary, %{}, bytes})
    ctx
  end

  asset "cauldron3d.js" do
    Client.source()
  end

  asset "main.js" do
    """
    import { mount } from "./cauldron3d.js";

    export function init(ctx, [info, snapshot]) {
      ctx.root.innerHTML = `<canvas tabindex="0" style="display: block; width: 100%; height: ${info.height}px; outline: none; background: #000;"></canvas>`;
      const canvas = ctx.root.querySelector("canvas");
      const scene = mount(canvas, (message) => ctx.pushEvent("event", message));
      scene.resize();
      scene.apply(snapshot);
      ctx.handleEvent("changes", ([_info, bytes]) => scene.apply(bytes));
    }
    """
  end

  defimpl Kino.Render do
    def to_livebook(view), do: Kino.Render.to_livebook(view.live)
  end

  defimpl Cauldron3D.Scene.Target do
    def submit(view, changes), do: @for.submit(view, changes)
    def mesh(view, mesh), do: @for.mesh(view, mesh)
    def texture(view, texture), do: @for.texture(view, texture)
    def canvas(view, canvas), do: @for.canvas(view, canvas)
    def material(view, material), do: @for.material(view, material)
    def scatter(view, scatter), do: @for.scatter(view, scatter)
    def release(view, handle), do: @for.release(view, handle)
    def capabilities(_view), do: %Cauldron3D.Scene.Capabilities{}
  end
end
