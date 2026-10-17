if Code.ensure_loaded?(Cauldron2D.Sectors.Map) do
  defmodule CauldronGPU.Sectors.Surfaces do
    @moduledoc """
    Convex polygons gathered into one `CauldronGPU.Mesh`, one part per material key.

    A surface is `{key, corners}`: `key` names its material (any term), `corners` are at
    least three `{position, normal, uv, light}` in counter-clockwise order seen from the
    side they face, positions and normals in map coordinates (+Z up) and `light` a sector
    light level `0..255`, read through `CauldronGPU.Sectors.Light.uv/1`.

        {mesh, keys} = CauldronGPU.Sectors.Surfaces.mesh(surfaces)

    `keys` lists the material key of each part, in part order.
    """

    alias CauldronGPU.Mesh
    alias CauldronGPU.Sectors.Light

    @type vec3 :: {number(), number(), number()}
    @type corner :: {vec3(), vec3(), {number(), number()}, integer()}
    @type surface :: {term(), [corner()]}

    @doc "The mesh holding `surfaces` and the material key of each of its parts."
    @spec mesh([surface()]) :: {Mesh.t(), [term()]}
    def mesh(surfaces) do
      groups =
        surfaces
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
        |> Enum.sort_by(&elem(&1, 0))

      {vertices, indices, parts, _count, _index_count} =
        Enum.reduce(groups, {[], [], [], 0, 0}, &add_group/2)

      mesh = %Mesh{
        vertices: vertices |> Enum.reverse() |> IO.iodata_to_binary(),
        indices: indices |> Enum.reverse() |> IO.iodata_to_binary(),
        parts: Enum.reverse(parts)
      }

      {mesh, Enum.map(groups, &elem(&1, 0))}
    end

    defp add_group({_key, polygons}, {vertices, indices, parts, count, index_count}) do
      {group_vertices, group_indices, next} =
        Enum.reduce(polygons, {[], [], count}, &add_polygon/2)

      added = div(IO.iodata_length(group_indices), 4)

      {[group_vertices | vertices], [group_indices | indices], [{index_count, added} | parts],
       next, index_count + added}
    end

    defp add_polygon(corners, {vertices, indices, base}) do
      count = length(corners)

      fan =
        for corner <- 1..(count - 2)//1,
            index <- [base, base + corner, base + corner + 1],
            into: <<>>,
            do: <<index::little-32>>

      {[vertices | Enum.map(corners, &encode/1)], [indices | fan], base + count}
    end

    defp encode({{x, y, z}, {nx, ny, nz}, {u, v}, light}) do
      {lu, lv} = Light.uv(light)

      <<x::little-float-32, y::little-float-32, z::little-float-32, u::little-float-32,
        nx::little-float-32, ny::little-float-32, nz::little-float-32, v::little-float-32,
        lu::little-float-32, lv::little-float-32, 0::little-float-32, 0::little-float-32>>
    end
  end
end
