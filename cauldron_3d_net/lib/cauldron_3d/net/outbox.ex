defmodule Cauldron3D.Net.Outbox do
  @moduledoc """
  The scene one network client is shown, as a `Cauldron3D.Scene.Target`: a scene's
  `:gpu` closure uploads to it and submits to it as to a renderer, and the changes
  collect until `take/1` hands them over, in order, as `Cauldron3D.Scene.Stream` change
  terms.

  An outbox belongs to the process that started it, its owner (`Cauldron3D.Net.Drawer`
  in a session). Changes the owner makes it collects quietly; when another process
  uploads (a loader filling the scene in the background), the owner is sent
  `{Cauldron3D.Net.Outbox, ref, :changed}` once until it next takes, `ref` as
  `ref/1` gives it.
  """

  use GenServer

  alias Cauldron3D.Net.SceneState
  alias Cauldron3D.Scene.{Canvas, Handle, Material, Mesh, Scatter, Stream, Texture}

  @type t :: %__MODULE__{server: pid(), ref: reference()}

  @enforce_keys [:server, :ref]
  defstruct [:server, :ref]

  @doc "Start an outbox owned by the calling process and linked to it."
  @spec start_link() :: {:ok, t()}
  def start_link do
    ref = make_ref()
    {:ok, pid} = GenServer.start_link(__MODULE__, {self(), ref})
    {:ok, %__MODULE__{server: pid, ref: ref}}
  end

  @doc "The reference in the outbox's `:changed` messages."
  @spec ref(t()) :: reference()
  def ref(%__MODULE__{ref: ref}), do: ref

  @doc "The changes collected since the last take, oldest first."
  @spec take(t()) :: [Stream.change()]
  def take(%__MODULE__{server: server}), do: GenServer.call(server, :take)

  @doc "Stop the outbox."
  @spec stop(t()) :: :ok
  def stop(%__MODULE__{server: server}), do: GenServer.stop(server)

  @doc "Adds one tick of changes."
  @spec submit(t(), [Stream.change()]) :: :ok
  def submit(%__MODULE__{server: server}, changes), do: GenServer.call(server, {:submit, changes})

  @doc "Adds a mesh, texture, canvas, material or scatter, answering its handle."
  @spec put(t(), SceneState.kind(), Mesh.t() | Texture.t() | Canvas.t() | Material.t() | Scatter.t()) ::
          Handle.t()
  def put(%__MODULE__{server: server}, kind, value),
    do: GenServer.call(server, {:put, kind, value})

  @doc "Lets the client drop a mesh, texture or material once no scene entry uses it."
  @spec release(t(), Handle.t()) :: :ok
  def release(%__MODULE__{server: server}, %Handle{} = handle),
    do: GenServer.call(server, {:release, handle})

  @impl GenServer
  def init({owner, ref}),
    do: {:ok, %{owner: owner, ref: ref, scene: SceneState.new(), waiting: [], told?: false}}

  @impl GenServer
  def handle_call(:take, _from, state),
    do:
      {:reply, state.waiting |> Enum.reverse() |> Enum.concat(),
       %{state | waiting: [], told?: false}}

  def handle_call({:submit, changes}, from, state) do
    {changes, scene} = SceneState.submit_changes(state.scene, changes)
    {:reply, :ok, collected(state, scene, changes, from)}
  end

  def handle_call({:put, kind, value}, from, state) do
    {handle, changes, scene} = SceneState.put_changes(state.scene, kind, value)
    {:reply, handle, collected(state, scene, changes, from)}
  end

  def handle_call({:release, handle}, from, state) do
    {changes, scene} = SceneState.release_changes(state.scene, handle)
    {:reply, :ok, collected(state, scene, changes, from)}
  end

  defp collected(state, scene, changes, {caller, _tag}) do
    state = %{state | scene: scene, waiting: [changes | state.waiting]}
    if caller == state.owner or state.told?, do: state, else: told(state)
  end

  defp told(state) do
    send(state.owner, {__MODULE__, state.ref, :changed})
    %{state | told?: true}
  end

  defimpl Cauldron3D.Scene.Target do
    def submit(outbox, changes), do: @for.submit(outbox, changes)
    def mesh(outbox, mesh), do: @for.put(outbox, :mesh, mesh)
    def texture(outbox, texture), do: @for.put(outbox, :texture, texture)
    def canvas(outbox, canvas), do: @for.put(outbox, :canvas, canvas)
    def material(outbox, material), do: @for.put(outbox, :material, material)
    def scatter(outbox, scatter), do: @for.put(outbox, :scatter, scatter)
    def release(outbox, handle), do: @for.release(outbox, handle)
    def capabilities(_outbox), do: %Cauldron3D.Scene.Capabilities{}
  end
end
