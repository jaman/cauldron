defmodule Cauldron3D.Net.Replay do
  @moduledoc """
  Draws a scene a server sends (`Cauldron3D.Net.Drawer`) with a local renderer, a
  `Cauldron3D.Scene.Target`. The server's meshes, textures, canvases and materials are
  uploaded to the target as they arrive, and every handle in later changes is swapped
  for the target's own; the rest of the changes are what the caller submits to the
  target, ticks left out.

      {submit, handles} = Cauldron3D.Net.Replay.apply(target, handles, received)
      Cauldron3D.Scene.Target.submit(target, submit)

  `handles` starts as `%{}` and is kept between calls. `release/2` drops every upload,
  as when the target is rebuilt from the start.
  """

  alias Cauldron3D.Scene.{Handle, Stream, Target}

  @type handles :: %{{Handle.kind(), Stream.id()} => Handle.t()}

  @uploads [:mesh, :texture, :material]
  @drops %{drop_mesh: :mesh, drop_texture: :texture, drop_material: :material}

  @doc "Upload what `changes` define and answer the changes to submit, with the handles after them."
  @spec apply(Target.t(), handles(), [Stream.change()]) :: {[Stream.change()], handles()}
  def apply(target, handles, changes) do
    {submitted, handles} =
      Enum.reduce(changes, {[], handles}, fn change, {submitted, handles} ->
        step(target, handles, change, submitted)
      end)

    {Enum.reverse(submitted), handles}
  end

  @doc "Release every upload in `handles` from `target`."
  @spec release(Target.t(), handles()) :: :ok
  def release(target, handles),
    do: Enum.each(handles, fn {_key, handle} -> Target.release(target, handle) end)

  defp step(_target, handles, :tick, submitted), do: {submitted, handles}

  defp step(target, handles, {kind, id, value}, submitted) when kind in @uploads,
    do: {submitted, Map.put(handles, {kind, id}, upload(target, kind, swapped(value, handles)))}

  defp step(target, handles, {:canvas, id, canvas}, submitted),
    do: {submitted, Map.put(handles, {:texture, id}, Target.canvas(target, canvas))}

  defp step(target, handles, {drop, id}, submitted) when is_map_key(@drops, drop) do
    case Map.pop(handles, {Map.fetch!(@drops, drop), id}) do
      {nil, handles} ->
        {submitted, handles}

      {handle, handles} ->
        Target.release(target, handle)
        {submitted, handles}
    end
  end

  defp step(_target, handles, change, submitted),
    do: {[swapped(change, handles) | submitted], handles}

  defp upload(target, :mesh, mesh), do: Target.mesh(target, mesh)
  defp upload(target, :texture, texture), do: Target.texture(target, texture)
  defp upload(target, :material, material), do: Target.material(target, material)

  defp swapped(%Handle{kind: kind, id: id} = handle, handles),
    do: Map.get(handles, {kind, id}, handle)

  defp swapped(%{__struct__: module} = struct, handles),
    do: struct(module, struct |> Map.from_struct() |> swapped(handles))

  defp swapped(map, handles) when is_map(map),
    do: Map.new(map, fn {key, value} -> {key, swapped(value, handles)} end)

  defp swapped(list, handles) when is_list(list), do: Enum.map(list, &swapped(&1, handles))

  defp swapped(tuple, handles) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> swapped(handles) |> List.to_tuple()

  defp swapped(value, _handles), do: value
end
