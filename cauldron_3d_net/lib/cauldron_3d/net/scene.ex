defmodule Cauldron3D.Net.Scene do
  @moduledoc """
  A scene browsers watch: it keeps everything sent to it (`Cauldron3D.Net.SceneState`) so a
  browser that joins later gets the whole scene, and broadcasts each batch to the
  browsers already watching as `Cauldron3D.Scene.Stream` bytes.

      {:ok, scene} = Cauldron3D.Net.Scene.open(id: "courtyard", events: self())
      cube = Cauldron3D.Net.Scene.mesh(scene, Cauldron3D.Scene.Mesh.cube(1.0))
      Cauldron3D.Net.Scene.submit(scene, [{:instance, 1, %Cauldron3D.Scene.Instance{mesh: cube}}])

  A scene is a `Cauldron3D.Scene.Target`, so the converters (`Cauldron3D.Scene.Bsp.upload/4` and the
  rest) upload to it as they do to a renderer. Changes are `Cauldron3D.Scene.Stream` changes.
  Meshes, textures and materials are kept until `release/2`. Input from a browser
  arrives at the `:events` pid as `{:cauldron_3d_net, scene_id, session, event}`,
  `session` a reference for the browser and `event` shaped as `CauldronGPU`'s window
  events, plus `:joined` and `:left`.

  `open/1` starts the scene linked to the caller; `start_link/1` is the same for a
  supervisor, and `lookup/1` finds a started scene by id.
  """

  use GenServer

  alias Cauldron3D.Net.SceneState
  alias Cauldron3D.Scene.{Canvas, Handle, Material, Mesh, Scatter, Stream, Texture}

  @type t :: %__MODULE__{server: pid(), id: String.t()}

  @enforce_keys [:server, :id]
  defstruct [:server, :id]

  @doc "Starts a scene. Options: `:id` (a string, required), `:events` (a pid, default none)."
  @spec open(keyword()) :: {:ok, t()} | {:error, term()}
  def open(opts) do
    with {:ok, pid} <- start_link(opts),
         do: {:ok, %__MODULE__{server: pid, id: Keyword.fetch!(opts, :id)}}
  end

  @doc "Starts a scene as `open/1` does, answering its pid, for a supervisor."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: {:via, Registry, {Cauldron3D.Net.Scenes, id}})
  end

  @doc "The scene started as `id`, or `nil`."
  @spec lookup(String.t()) :: t() | nil
  def lookup(id) do
    case Registry.lookup(Cauldron3D.Net.Scenes, id) do
      [{pid, _}] -> %__MODULE__{server: pid, id: id}
      [] -> nil
    end
  end

  @doc "The PubSub topic a scene's batches are broadcast on."
  @spec topic(String.t()) :: String.t()
  def topic(id), do: "cauldron_3d_net:" <> id

  @doc "Sends one tick of changes to every watching browser and keeps them for later ones."
  @spec submit(t(), [Stream.change()]) :: :ok
  def submit(%__MODULE__{server: server}, changes),
    do: GenServer.call(server, {:submit, changes})

  @doc "Uploads a mesh and returns its handle."
  @spec mesh(t(), Mesh.t()) :: Handle.t()
  def mesh(%__MODULE__{server: server}, %Mesh{} = mesh),
    do: GenServer.call(server, {:put, :mesh, mesh})

  @doc "Uploads a texture and returns its handle."
  @spec texture(t(), Texture.t()) :: Handle.t()
  def texture(%__MODULE__{server: server}, %Texture{} = texture),
    do: GenServer.call(server, {:put, :texture, texture})

  @doc "Makes a canvas and returns its handle, a texture's."
  @spec canvas(t(), Canvas.t()) :: Handle.t()
  def canvas(%__MODULE__{server: server}, %Canvas{} = canvas),
    do: GenServer.call(server, {:put, :canvas, canvas})

  @doc "Defines a material and returns its handle."
  @spec material(t(), Material.t()) :: Handle.t()
  def material(%__MODULE__{server: server}, %Material{} = material),
    do: GenServer.call(server, {:put, :material, material})

  @doc "Uploads a scatter and returns its handle."
  @spec scatter(t(), Scatter.t()) :: Handle.t()
  def scatter(%__MODULE__{server: server}, %Scatter{} = scatter),
    do: GenServer.call(server, {:put, :scatter, scatter})

  @doc "Lets the scene drop a mesh, texture or material once no scene entry uses it."
  @spec release(t(), Handle.t()) :: :ok
  def release(%__MODULE__{server: server}, %Handle{} = handle),
    do: GenServer.call(server, {:release, handle})

  @doc "The bytes that give a browser the whole scene as it stands."
  @spec snapshot(t()) :: binary()
  def snapshot(%__MODULE__{server: server}), do: GenServer.call(server, :snapshot)

  @doc "Passes a browser's event to the scene's `:events` pid."
  @spec event(t(), reference(), term()) :: :ok
  def event(%__MODULE__{server: server}, session, event),
    do: GenServer.cast(server, {:event, session, event})

  @impl true
  def init(opts) do
    {:ok,
     %{
       id: Keyword.fetch!(opts, :id),
       events: Keyword.get(opts, :events),
       scene: SceneState.new()
     }}
  end

  @impl true
  def handle_call({:submit, changes}, _from, state) do
    {bytes, scene} = SceneState.submit(state.scene, changes)
    {:reply, :ok, broadcast(%{state | scene: scene}, bytes)}
  end

  def handle_call({:put, kind, value}, _from, state) do
    {handle, bytes, scene} = SceneState.put(state.scene, kind, value)
    {:reply, handle, broadcast(%{state | scene: scene}, bytes)}
  end

  def handle_call({:release, handle}, _from, state) do
    {bytes, scene} = SceneState.release(state.scene, handle)
    {:reply, :ok, broadcast(%{state | scene: scene}, bytes)}
  end

  def handle_call(:snapshot, _from, state),
    do: {:reply, SceneState.snapshot(state.scene), state}

  @impl true
  def handle_cast({:event, session, event}, state) do
    if state.events, do: send(state.events, {:cauldron_3d_net, state.id, session, event})
    {:noreply, state}
  end

  defp broadcast(state, bytes) do
    Phoenix.PubSub.broadcast(
      Cauldron3D.Net.PubSub,
      topic(state.id),
      {:cauldron_3d_net_changes, bytes}
    )

    state
  end

  defimpl Cauldron3D.Scene.Target do
    def submit(scene, changes), do: @for.submit(scene, changes)
    def mesh(scene, mesh), do: @for.mesh(scene, mesh)
    def texture(scene, texture), do: @for.texture(scene, texture)
    def canvas(scene, canvas), do: @for.canvas(scene, canvas)
    def material(scene, material), do: @for.material(scene, material)
    def scatter(scene, scatter), do: @for.scatter(scene, scatter)
    def release(scene, handle), do: @for.release(scene, handle)
    def capabilities(_scene), do: %Cauldron3D.Scene.Capabilities{}
  end
end
