defmodule Cauldron3D.Net.SceneState do
  @moduledoc """
  The scene a client is shown, as a value: everything sent so far
  (`Cauldron3D.Scene.Host.Record`) and the next handle id. `submit/2`, `put/3` and
  `release/2` return the `Cauldron3D.Scene.Stream` bytes to send to the browsers already
  watching; `submit_changes/2`, `put_changes/3` and `release_changes/2` return the same as
  change terms. `snapshot/1` is the bytes a browser joining late gets.

      state = Cauldron3D.Net.SceneState.new()
      {cube, bytes, state} = Cauldron3D.Net.SceneState.put(state, :mesh, Cauldron3D.Scene.Mesh.cube(1.0))
      {bytes, state} = Cauldron3D.Net.SceneState.submit(state, [{:instance, 1, %Cauldron3D.Scene.Instance{mesh: cube}}])

  `Cauldron3D.Net.Scene` and `Cauldron3D.Kino` hold one each.
  """

  alias Cauldron3D.Scene.{Canvas, Handle, Material, Mesh, Scatter, Stream, Texture}
  alias Cauldron3D.Scene.Host.Record

  @type kind :: :mesh | :texture | :canvas | :material | :scatter
  @type t :: %__MODULE__{record: Record.t(), next: pos_integer()}

  @enforce_keys [:record, :next]
  defstruct [:record, :next]

  @doc "An empty scene."
  @spec new() :: t()
  def new, do: %__MODULE__{record: Record.new(), next: 1}

  @doc "One tick of changes: the bytes for watching browsers, the tick marker first."
  @spec submit(t(), [Stream.change()]) :: {binary(), t()}
  def submit(%__MODULE__{} = state, changes),
    do: state |> submit_changes(changes) |> encoded()

  @doc "`submit/2` as change terms."
  @spec submit_changes(t(), [Stream.change()]) :: {[Stream.change()], t()}
  def submit_changes(%__MODULE__{} = state, changes), do: recorded(state, [:tick | changes])

  @doc "Adds a mesh, texture, canvas, material or scatter, answering its handle and the bytes."
  @spec put(t(), kind(), Mesh.t() | Texture.t() | Canvas.t() | Material.t() | Scatter.t()) ::
          {Handle.t(), binary(), t()}
  def put(%__MODULE__{} = state, kind, value) do
    {handle, changes, state} = put_changes(state, kind, value)
    {bytes, state} = encoded({changes, state})
    {handle, bytes, state}
  end

  @doc "`put/3` as change terms."
  @spec put_changes(t(), kind(), Mesh.t() | Texture.t() | Canvas.t() | Material.t() | Scatter.t()) ::
          {Handle.t(), [Stream.change()], t()}
  def put_changes(%__MODULE__{next: id} = state, :canvas, %Canvas{} = canvas) do
    handle = %Handle{kind: :texture, id: id, ref: make_ref()}
    {changes, state} = recorded(%{state | next: id + 1}, [{:canvas, id, canvas}])
    {handle, changes, state}
  end

  def put_changes(%__MODULE__{next: id} = state, kind, value)
      when kind in [:mesh, :texture, :material, :scatter] do
    handle = %Handle{kind: kind, id: id, ref: make_ref(), keeps: keeps(value)}
    {changes, state} = recorded(%{state | next: id + 1}, [{kind, id, value}])
    {handle, changes, state}
  end

  @doc "Drops a mesh, texture or material once no scene entry uses it."
  @spec release(t(), Handle.t()) :: {binary(), t()}
  def release(%__MODULE__{} = state, handle),
    do: state |> release_changes(handle) |> encoded()

  @doc "`release/2` as change terms."
  @spec release_changes(t(), Handle.t()) :: {[Stream.change()], t()}
  def release_changes(%__MODULE__{} = state, %Handle{kind: kind, id: id}),
    do: recorded(state, [{drop(kind), id}])

  @doc "The bytes that give a browser the whole scene as it stands."
  @spec snapshot(t()) :: binary()
  def snapshot(%__MODULE__{record: record}),
    do: record |> Record.replay() |> Stream.encode() |> IO.iodata_to_binary()

  defp recorded(state, changes),
    do: {changes, %{state | record: Record.apply_changes(state.record, changes)}}

  defp encoded({changes, state}),
    do: {changes |> Stream.encode() |> IO.iodata_to_binary(), state}

  defp keeps(%Material{} = material), do: Material.textures(material)
  defp keeps(_value), do: []

  defp drop(:mesh), do: :drop_mesh
  defp drop(:texture), do: :drop_texture
  defp drop(:material), do: :drop_material
  defp drop(:scatter), do: :drop_scatter
end
