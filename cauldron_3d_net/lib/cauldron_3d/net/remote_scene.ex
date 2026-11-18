defmodule Cauldron3D.Net.RemoteScene do
  @moduledoc """
  The scene of a remote world's view (`Cauldron.Net.Link.World` with
  `Cauldron3D.Net.Drawer`) for a 3D game's client: a `:gpu` closure that draws, with the
  client's own renderer, the scene the server sends.

      def scene(%{remote: _} = view, _look), do: Cauldron3D.Net.RemoteScene.scene(view)

  What arrives is kept in a store of its own (`Cauldron3D.Net.RemoteScene.Store`),
  started by the first batch and linked to the process that keeps the view's `remote`
  map; the view holds only the store and the number of the latest batch. A renderer that
  has drawn the earlier batches is given the new ones, and a new renderer, or one too far
  behind, the whole scene (`Cauldron3D.Net.Replay`). Before anything has arrived the
  scene is empty.
  """

  alias Cauldron3D.Net.RemoteScene.Store
  alias Cauldron3D.Net.Replay

  @typedoc "What a view's `remote` map keeps under `:scene_3d`."
  @type received :: %{store: pid(), seq: pos_integer()}

  @doc "The remote map with one more batch of changes, kept in its store."
  @spec received(map(), [Cauldron3D.Scene.Stream.change()]) :: map()
  def received(remote, changes) do
    %{store: store, seq: seq} = Map.get(remote, :scene_3d) || started()
    Store.add(store, changes)
    Map.put(remote, :scene_3d, %{store: store, seq: seq + 1})
  end

  @doc "The scene of a remote view."
  @spec scene(map()) :: map()
  def scene(%{remote: remote}) do
    status = Map.get(remote, :status) || %{}
    received = Map.get(remote, :scene_3d)

    %{
      focus: Map.get(status, :focus) || {0.0, 0.0},
      bounds: :unbounded,
      cell: fn _cell -> nil end,
      movers: [],
      gpu: fn target, cache, _size, _aspect -> drawn(target, cache, received) end
    }
  end

  defp started do
    {:ok, store} = Store.start_link()
    %{store: store, seq: 0}
  end

  defp drawn(_target, cache, nil), do: {[], cache}

  defp drawn(target, cache, %{store: store}) do
    case Store.since(store, seen(cache, store)) do
      {:newer, changes, seq} ->
        {submit, handles} = Replay.apply(target, cache.handles, changes)
        {submit, %{store: store, seq: seq, handles: handles}}

      {:whole, changes, seq} ->
        if cache, do: Replay.release(target, cache.handles)
        {submit, handles} = Replay.apply(target, %{}, changes)
        {submit, %{store: store, seq: seq, handles: handles}}
    end
  end

  defp seen(%{store: store, seq: seq}, store), do: seq
  defp seen(_cache, _store), do: nil
end
