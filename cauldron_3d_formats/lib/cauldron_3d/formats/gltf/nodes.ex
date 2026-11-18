defmodule Cauldron3D.Formats.Gltf.Nodes do
  @moduledoc """
  A glTF document's nodes.

    * `placed/1` — the nodes of the scene that carry a mesh, each with its world matrix:
      the node's own `matrix`, or its `translation`, `rotation` and `scale`, after every
      parent's, with its index (`node`) and its skin (an index or `nil`)
    * `tree/1` — every node with its parent, children, mesh, skin and its place relative
      to its parent as `translation`, `rotation` (`{x, y, z, w}`) and `scale`; a node
      given as a `matrix` has it taken apart, which assumes no shear

  Matrices are 16 numbers, column after column, as glTF writes them.

      Cauldron3D.Formats.Gltf.Nodes.placed(json)
      #=> [%{mesh: 0, node: 0, skin: nil, name: "sponza", matrix: {1.0, 0.0, ...}}]
  """

  @identity {1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0}

  @type matrix :: tuple()
  @type tree_node :: %{
          name: String.t() | nil,
          parent: non_neg_integer() | nil,
          children: [non_neg_integer()],
          mesh: non_neg_integer() | nil,
          skin: non_neg_integer() | nil,
          translation: {float(), float(), float()},
          rotation: {float(), float(), float(), float()},
          scale: {float(), float(), float()}
        }

  @doc "The 4×4 identity matrix."
  @spec identity() :: matrix()
  def identity, do: @identity

  @doc "Every node under the document's scene (its `scene`, else the first) that has a mesh."
  @spec placed(map()) :: [
          %{
            mesh: non_neg_integer(),
            node: non_neg_integer(),
            skin: non_neg_integer() | nil,
            name: String.t() | nil,
            matrix: matrix()
          }
        ]
  def placed(json) do
    nodes = Map.get(json, "nodes", [])
    roots = roots(json, nodes)
    Enum.flat_map(roots, &walk(nodes, &1, @identity))
  end

  @doc "Every node of the document, in the document's order."
  @spec tree(map()) :: [tree_node()]
  def tree(json) do
    nodes = Map.get(json, "nodes", [])

    parents =
      for {node, index} <- Enum.with_index(nodes),
          child <- Map.get(node, "children", []),
          into: %{},
          do: {child, index}

    nodes
    |> Enum.with_index()
    |> Enum.map(fn {node, index} ->
      {translation, rotation, scale} = parts(node)

      %{
        name: node["name"],
        parent: Map.get(parents, index),
        children: Map.get(node, "children", []),
        mesh: node["mesh"],
        skin: node["skin"],
        translation: translation,
        rotation: rotation,
        scale: scale
      }
    end)
  end

  @doc "`a` times `b`, both column-major."
  @spec multiply(matrix(), matrix()) :: matrix()
  def multiply(a, b) do
    for column <- 0..3, row <- 0..3 do
      Enum.reduce(0..3, 0.0, fn k, sum -> sum + elem(a, k * 4 + row) * elem(b, column * 4 + k) end)
    end
    |> List.to_tuple()
  end

  defp roots(json, nodes) do
    case Map.get(json, "scenes") do
      [_ | _] = scenes -> Enum.at(scenes, Map.get(json, "scene", 0))["nodes"] || []
      _none -> Enum.to_list(0..(length(nodes) - 1)//1)
    end
  end

  defp walk(nodes, index, parent) do
    node = Enum.at(nodes, index)
    world = multiply(parent, local(node))

    own =
      if node["mesh"],
        do: [
          %{
            mesh: node["mesh"],
            node: index,
            skin: node["skin"],
            name: node["name"],
            matrix: world
          }
        ],
        else: []

    own ++ Enum.flat_map(Map.get(node, "children", []), &walk(nodes, &1, world))
  end

  defp parts(%{"matrix" => matrix}) do
    [a, b, c, _, d, e, f, _, g, h, i, _, tx, ty, tz, _] = Enum.map(matrix, &(&1 / 1))
    {sx, sy, sz} = {norm(a, b, c), norm(d, e, f), norm(g, h, i)}

    {{tx, ty, tz},
     rotation({a / sx, b / sx, c / sx}, {d / sy, e / sy, f / sy}, {g / sz, h / sz, i / sz}),
     {sx, sy, sz}}
  end

  defp parts(node) do
    [tx, ty, tz] = Map.get(node, "translation", [0, 0, 0])
    [qx, qy, qz, qw] = Map.get(node, "rotation", [0, 0, 0, 1])
    [sx, sy, sz] = Map.get(node, "scale", [1, 1, 1])
    {{tx / 1, ty / 1, tz / 1}, {qx / 1, qy / 1, qz / 1, qw / 1}, {sx / 1, sy / 1, sz / 1}}
  end

  defp norm(x, y, z) do
    length = :math.sqrt(x * x + y * y + z * z)
    if length == 0, do: 1.0, else: length
  end

  defp rotation({m00, m10, m20}, {m01, m11, m21}, {m02, m12, m22}) do
    trace = m00 + m11 + m22

    cond do
      trace > 0 ->
        s = :math.sqrt(trace + 1.0) * 2
        {(m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s, 0.25 * s}

      m00 > m11 and m00 > m22 ->
        s = :math.sqrt(1.0 + m00 - m11 - m22) * 2
        {0.25 * s, (m01 + m10) / s, (m02 + m20) / s, (m21 - m12) / s}

      m11 > m22 ->
        s = :math.sqrt(1.0 + m11 - m00 - m22) * 2
        {(m01 + m10) / s, 0.25 * s, (m12 + m21) / s, (m02 - m20) / s}

      true ->
        s = :math.sqrt(1.0 + m22 - m00 - m11) * 2
        {(m02 + m20) / s, (m12 + m21) / s, 0.25 * s, (m10 - m01) / s}
    end
  end

  defp local(%{"matrix" => matrix}), do: matrix |> Enum.map(&(&1 / 1)) |> List.to_tuple()

  defp local(node) do
    [tx, ty, tz] = Map.get(node, "translation", [0, 0, 0])
    [qx, qy, qz, qw] = Map.get(node, "rotation", [0, 0, 0, 1])
    [sx, sy, sz] = Map.get(node, "scale", [1, 1, 1])

    {
      (1 - 2 * (qy * qy + qz * qz)) * sx,
      2 * (qx * qy + qz * qw) * sx,
      2 * (qx * qz - qy * qw) * sx,
      0.0,
      2 * (qx * qy - qz * qw) * sy,
      (1 - 2 * (qx * qx + qz * qz)) * sy,
      2 * (qy * qz + qx * qw) * sy,
      0.0,
      2 * (qx * qz + qy * qw) * sz,
      2 * (qy * qz - qx * qw) * sz,
      (1 - 2 * (qx * qx + qy * qy)) * sz,
      0.0,
      tx / 1,
      ty / 1,
      tz / 1,
      1.0
    }
  end
end
