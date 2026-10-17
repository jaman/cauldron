if Code.ensure_loaded?(Cauldron2D.Sectors.Map) do
  defmodule CauldronGPU.Sectors.Live.Mesh do
    @moduledoc """
    `CauldronGPU.Sectors.Live.Geometry` surfaces gathered into one `CauldronGPU.Mesh`,
    one part per picture, each corner's lightmap coordinates reading its sector's row of a
    `CauldronGPU.Sectors.Live.Lightmap` of `count` sectors.

        {mesh, keys} = CauldronGPU.Sectors.Live.Mesh.build(surfaces, count)

    `keys` lists each part's key, `{:picture, id}` or `:sky`, in part order.
    """

    alias CauldronGPU.Mesh
    alias CauldronGPU.Sectors.Live.{Geometry, Lightmap}

    @doc "The mesh holding `surfaces` and the key of each of its parts."
    @spec build([Geometry.surface()], pos_integer()) :: {Mesh.t(), [term()]}
    def build(surfaces, count) do
      groups =
        surfaces
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
        |> Enum.sort_by(&elem(&1, 0))

      {vertices, indices, parts, _vertex_count, _index_count} =
        Enum.reduce(groups, {[], [], [], 0, 0}, &add_group(&1, &2, count))

      mesh = %Mesh{
        vertices: vertices |> Enum.reverse() |> IO.iodata_to_binary(),
        indices: indices |> Enum.reverse() |> IO.iodata_to_binary(),
        parts: Enum.reverse(parts)
      }

      {mesh, Enum.map(groups, &elem(&1, 0))}
    end

    defp add_group({_key, polygons}, {vertices, indices, parts, base, first}, count) do
      {group_vertices, group_indices, next} =
        Enum.reduce(polygons, {[], [], base}, &add_polygon(&1, &2, count))

      added = div(IO.iodata_length(group_indices), 4)

      {[group_vertices | vertices], [group_indices | indices], [{first, added} | parts], next,
       first + added}
    end

    defp add_polygon(corners, {vertices, indices, base}, count) do
      fan =
        for corner <- 1..(length(corners) - 2)//1,
            index <- [base, base + corner, base + corner + 1],
            into: <<>>,
            do: <<index::little-32>>

      {[vertices | Enum.map(corners, &encode(&1, count))], [indices | fan],
       base + length(corners)}
    end

    defp encode({{x, y, z}, {nx, ny, nz}, {u, v}, light}, count) do
      {lu, lv} = Lightmap.uv(light, count)

      <<x::little-float-32, y::little-float-32, z::little-float-32, u::little-float-32,
        nx::little-float-32, ny::little-float-32, nz::little-float-32, v::little-float-32,
        lu::little-float-32, lv::little-float-32, 0::little-float-32, 0::little-float-32>>
    end
  end
end
