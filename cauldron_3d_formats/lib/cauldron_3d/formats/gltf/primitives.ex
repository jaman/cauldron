defmodule Cauldron3D.Formats.Gltf.Primitives do
  @moduledoc """
  A glTF mesh's primitives as packed triangle lists, every attribute a binary of
  little-endian 32-bit floats:

    * `positions`, `normals` — three floats a vertex
    * `uvs` — two floats a vertex (zeros when the primitive has none); `uvs1` the second
      set or `nil`
    * `colors` — four floats a vertex from `0.0` to `1.0`, or `nil`
    * `joints` — four little-endian unsigned 32-bit integers a vertex, indices into the
      skin's joints, or `nil`; `weights` — their four weights as floats, or `nil`
    * `indices` — little-endian unsigned 32-bit integers, three per counter-clockwise
      triangle
    * `targets` — one `%{positions, normals}` for each morph target: each vertex's offset
      from the base, three floats a vertex (`normals` is `nil` when the target gives none),
      in the same vertex order as the primitive
    * `material` — an index or `nil`

  Triangle strips and fans become triangle lists. A primitive without normals gets flat
  ones, its vertices split so each triangle has its own. A primitive keeps only the
  vertices its triangles use, renumbered in the order they are first used, so primitives
  sharing one large vertex buffer do not each copy all of it. Points and lines are left out.
  """

  alias Cauldron3D.Formats.Gltf.Accessor

  @doc "The triangle primitives of mesh `index` in `json`, reading from `buffers`."
  @spec read(map(), [binary()], non_neg_integer()) :: [map()]
  def read(json, buffers, index) do
    json["meshes"]
    |> Enum.at(index)
    |> Map.get("primitives", [])
    |> Enum.filter(&(Map.get(&1, "mode", 4) in [4, 5, 6]))
    |> Enum.map(&primitive(json, buffers, &1))
  end

  @doc "The number of vertices in `primitive`."
  @spec vertex_count(map()) :: non_neg_integer()
  def vertex_count(%{positions: positions}), do: div(byte_size(positions), 12)

  defp primitive(json, buffers, source) do
    attributes = source["attributes"]
    {3, positions} = Accessor.floats(json, buffers, attributes["POSITION"])
    count = div(byte_size(positions), 12)

    indices =
      case source["indices"] do
        nil -> for index <- 0..(count - 1)//1, into: <<>>, do: <<index::little-32>>
        accessor -> Accessor.integers(json, buffers, accessor)
      end

    primitive = %{
      positions: positions,
      normals: attribute(json, buffers, attributes["NORMAL"]),
      uvs:
        attribute(json, buffers, attributes["TEXCOORD_0"]) ||
          :binary.copy(<<0.0::little-float-32>>, count * 2),
      uvs1: attribute(json, buffers, attributes["TEXCOORD_1"]),
      colors: colors(json, buffers, attributes["COLOR_0"]),
      joints: joints(json, buffers, attributes["JOINTS_0"]),
      weights: attribute(json, buffers, attributes["WEIGHTS_0"]),
      targets: targets(json, buffers, Map.get(source, "targets", []), count),
      indices: triangulated(indices, Map.get(source, "mode", 4)),
      material: source["material"]
    }

    if primitive.normals, do: compact(primitive, count), else: flat(primitive)
  end

  defp targets(json, buffers, targets, count) do
    for target <- targets do
      %{
        positions:
          attribute(json, buffers, target["POSITION"]) ||
            :binary.copy(<<0.0::little-float-32>>, count * 3),
        normals: attribute(json, buffers, target["NORMAL"])
      }
    end
  end

  defp joints(_json, _buffers, nil), do: nil
  defp joints(json, buffers, accessor), do: Accessor.integers(json, buffers, accessor)

  defp compact(primitive, count) do
    order = listed(primitive.indices)
    {used, renumbered} = first_uses(order)

    if map_size(used) == count do
      primitive
    else
      kept = used |> Enum.sort_by(&elem(&1, 1)) |> Enum.map(&elem(&1, 0))

      primitive
      |> picked_attributes(kept)
      |> Map.put(:indices, packed(renumbered))
    end
  end

  defp first_uses(order) do
    {used, renumbered} =
      Enum.reduce(order, {%{}, []}, fn index, {used, renumbered} ->
        case used do
          %{^index => new} -> {used, [new | renumbered]}
          _ -> {Map.put(used, index, map_size(used)), [map_size(used) | renumbered]}
        end
      end)

    {used, Enum.reverse(renumbered)}
  end

  defp picked_attributes(primitive, order) do
    %{
      primitive
      | positions: picked(primitive.positions, order, 12),
        normals: picked(primitive.normals, order, 12),
        uvs: picked(primitive.uvs, order, 8),
        uvs1: picked(primitive.uvs1, order, 8),
        colors: picked(primitive.colors, order, 16),
        joints: picked(primitive.joints, order, 16),
        weights: picked(primitive.weights, order, 16),
        targets: Enum.map(primitive.targets, &picked_target(&1, order))
    }
  end

  defp picked_target(target, order),
    do: %{
      positions: picked(target.positions, order, 12),
      normals: picked(target.normals, order, 12)
    }

  defp attribute(_json, _buffers, nil), do: nil

  defp attribute(json, buffers, accessor) do
    {_width, floats} = Accessor.floats(json, buffers, accessor)
    floats
  end

  defp colors(_json, _buffers, nil), do: nil

  defp colors(json, buffers, accessor) do
    case Accessor.floats(json, buffers, accessor) do
      {4, rgba} ->
        rgba

      {3, rgb} ->
        for <<colour::binary-size(12) <- rgb>>,
          into: <<>>,
          do: <<colour::binary, 1.0::little-float-32>>
    end
  end

  defp triangulated(indices, 4), do: indices

  defp triangulated(indices, 5) do
    indices
    |> listed()
    |> Enum.chunk_every(3, 1, :discard)
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {[a, b, c], index} when rem(index, 2) == 0 -> [a, b, c]
      {[a, b, c], _index} -> [b, a, c]
    end)
    |> packed()
  end

  defp triangulated(indices, 6) do
    [first | rest] = listed(indices)

    rest
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [b, c] -> [first, b, c] end)
    |> packed()
  end

  defp listed(indices), do: for(<<index::little-32 <- indices>>, do: index)
  defp packed(indices), do: for(index <- indices, into: <<>>, do: <<index::little-32>>)

  defp flat(primitive) do
    order = listed(primitive.indices)

    normals =
      order
      |> Enum.chunk_every(3)
      |> Enum.map(fn [a, b, c] ->
        normal =
          face_normal(
            vector(primitive.positions, a),
            vector(primitive.positions, b),
            vector(primitive.positions, c)
          )

        :binary.copy(normal, 3)
      end)
      |> IO.iodata_to_binary()

    %{
      picked_attributes(primitive, order)
      | normals: normals,
        indices: packed(Enum.to_list(0..(length(order) - 1)//1))
    }
  end

  defp picked(nil, _order, _size), do: nil

  defp picked(values, order, size),
    do: for(index <- order, into: <<>>, do: binary_part(values, index * size, size))

  defp vector(positions, index) do
    <<x::little-float-32, y::little-float-32, z::little-float-32>> =
      binary_part(positions, index * 12, 12)

    {x, y, z}
  end

  defp face_normal({ax, ay, az}, {bx, by, bz}, {cx, cy, cz}) do
    {ux, uy, uz} = {bx - ax, by - ay, bz - az}
    {vx, vy, vz} = {cx - ax, cy - ay, cz - az}
    {nx, ny, nz} = {uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx}
    length = :math.sqrt(nx * nx + ny * ny + nz * nz)
    {x, y, z} = if length > 0, do: {nx / length, ny / length, nz / length}, else: {0.0, 1.0, 0.0}
    <<x::little-float-32, y::little-float-32, z::little-float-32>>
  end
end
