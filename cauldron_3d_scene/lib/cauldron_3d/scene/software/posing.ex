if Code.ensure_loaded?(Cauldron3D.Render) do
  defmodule Cauldron3D.Scene.Software.Posing do
    @moduledoc """
    An instance's mesh in the world, as `Cauldron3D.Scene.Software` draws it: blended
    toward its pose's `blend_to` mesh, moved by its pose's morph target `weights`, skinned by its pose's bones, then scaled, turned and
    moved by its transform. Answers a tuple of `{position, normal, uv}`, one a vertex, in
    the order of the mesh's vertices.
    """

    alias Cauldron3D.Scene.{Pose, Quat, Transform}
    alias Cauldron3D.Scene.Software.Resources

    @doc "The world vertices of `mesh` posed by `pose` (or `nil`) and placed by `transform`; `meshes` holds a pose's `blend_to`."
    @spec world(Resources.mesh(), Pose.t() | nil, Transform.t(), map()) :: tuple()
    def world(mesh, pose, %Transform{} = transform, meshes) do
      mesh.vertices
      |> blended(pose, meshes)
      |> morphed(pose, mesh.morphs)
      |> skinned(pose, mesh.skin)
      |> placed(transform)
    end

    defp blended(vertices, %Pose{blend_to: %{id: id}, blend: amount}, meshes) when amount > 0 do
      case Map.fetch(meshes, id) do
        {:ok, %{vertices: target}} when tuple_size(target) == tuple_size(vertices) ->
          for index <- 0..(tuple_size(vertices) - 1)//1 do
            {position, normal, uv} = elem(vertices, index)
            {to_position, to_normal, _uv} = elem(target, index)
            {lerp(position, to_position, amount), lerp(normal, to_normal, amount), uv}
          end
          |> List.to_tuple()

        _no_target ->
          vertices
      end
    end

    defp blended(vertices, _pose, _meshes), do: vertices

    defp morphed(vertices, %Pose{weights: [_ | _] = weights}, [_ | _] = morphs) do
      active =
        morphs
        |> Enum.zip(weights)
        |> Enum.reject(fn {_morph, weight} -> weight == 0 end)

      if active == [], do: vertices, else: offset(vertices, active)
    end

    defp morphed(vertices, _pose, _morphs), do: vertices

    defp offset(vertices, active) do
      for index <- 0..(tuple_size(vertices) - 1)//1 do
        {position, normal, uv} = elem(vertices, index)

        {position, normal} =
          Enum.reduce(active, {position, normal}, fn {morph, weight}, {position, normal} ->
            {add(position, elem(morph.positions, index), weight),
             if(morph.normals, do: add(normal, elem(morph.normals, index), weight), else: normal)}
          end)

        {position, unit(normal), uv}
      end
      |> List.to_tuple()
    end

    defp add({x, y, z}, {dx, dy, dz}, weight),
      do: {x + dx * weight, y + dy * weight, z + dz * weight}

    defp skinned(vertices, %Pose{bones: [_ | _] = bones}, skin) when skin != nil do
      matrices = bones |> Enum.map(&List.to_tuple/1) |> List.to_tuple()

      for index <- 0..(tuple_size(vertices) - 1)//1 do
        {position, normal, uv} = elem(vertices, index)
        matrix = weighted(elem(skin, index), matrices)
        {affine(matrix, position), unit(linear(matrix, normal)), uv}
      end
      |> List.to_tuple()
    end

    defp skinned(vertices, _pose, _skin), do: vertices

    defp weighted({{b0, b1, b2, b3}, {w0, w1, w2, w3}}, matrices) do
      [{b0, w0}, {b1, w1}, {b2, w2}, {b3, w3}]
      |> Enum.reject(fn {bone, weight} -> weight == 0 or bone >= tuple_size(matrices) end)
      |> Enum.reduce(List.duplicate(0.0, 12), fn {bone, weight}, sum ->
        bone_matrix = elem(matrices, bone) |> Tuple.to_list()
        Enum.zip_with(sum, bone_matrix, &(&1 + &2 * weight / 255))
      end)
      |> List.to_tuple()
    end

    defp affine(m, {x, y, z}) do
      {elem(m, 0) * x + elem(m, 1) * y + elem(m, 2) * z + elem(m, 3),
       elem(m, 4) * x + elem(m, 5) * y + elem(m, 6) * z + elem(m, 7),
       elem(m, 8) * x + elem(m, 9) * y + elem(m, 10) * z + elem(m, 11)}
    end

    defp linear(m, {x, y, z}) do
      {elem(m, 0) * x + elem(m, 1) * y + elem(m, 2) * z,
       elem(m, 4) * x + elem(m, 5) * y + elem(m, 6) * z,
       elem(m, 8) * x + elem(m, 9) * y + elem(m, 10) * z}
    end

    defp placed(vertices, %Transform{
           position: {px, py, pz},
           rotation: rotation,
           scale: {sx, sy, sz}
         }) do
      for {{x, y, z}, {nx, ny, nz}, uv} <- Tuple.to_list(vertices) do
        {rx, ry, rz} = Quat.rotate(rotation, {x * sx, y * sy, z * sz})

        {{rx + px, ry + py, rz + pz}, unit(Quat.rotate(rotation, {nx / sx, ny / sy, nz / sz})),
         uv}
      end
      |> List.to_tuple()
    end

    defp lerp({ax, ay, az}, {bx, by, bz}, t),
      do: {ax + (bx - ax) * t, ay + (by - ay) * t, az + (bz - az) * t}

    defp unit({x, y, z}) do
      length = :math.sqrt(x * x + y * y + z * z)
      if length > 0.0, do: {x / length, y / length, z / length}, else: {0.0, 1.0, 0.0}
    end
  end
end
