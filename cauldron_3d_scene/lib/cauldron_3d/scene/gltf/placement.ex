defmodule Cauldron3D.Scene.Gltf.Placement do
  @moduledoc """
  4×4 matrices as glTF writes them (16 numbers, column after column) and the
  `Cauldron3D.Scene.Transform` each stands for.

      matrix = Cauldron3D.Scene.Gltf.Placement.matrix(Cauldron3D.Scene.Transform.new(position: {0.0, 1.0, 0.0}))
      Cauldron3D.Scene.Gltf.Placement.transform(matrix)
  """

  alias Cauldron3D.Scene.Transform

  @type matrix :: tuple()

  @doc "The matrix of a transform: scale, then rotation, then position."
  @spec matrix(Transform.t()) :: matrix()
  def matrix(%Transform{position: {tx, ty, tz}, rotation: {qx, qy, qz, qw}, scale: {sx, sy, sz}}) do
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

  @doc "`a` times `b`."
  @spec multiply(matrix(), matrix()) :: matrix()
  def multiply(a, b) do
    for column <- 0..3, row <- 0..3 do
      Enum.reduce(0..3, 0.0, fn k, sum -> sum + elem(a, k * 4 + row) * elem(b, column * 4 + k) end)
    end
    |> List.to_tuple()
  end

  @doc "Where `matrix` puts the point `{x, y, z}`."
  @spec point(matrix(), {number(), number(), number()}) :: {float(), float(), float()}
  def point(m, {x, y, z}) do
    {
      elem(m, 0) * x + elem(m, 4) * y + elem(m, 8) * z + elem(m, 12),
      elem(m, 1) * x + elem(m, 5) * y + elem(m, 9) * z + elem(m, 13),
      elem(m, 2) * x + elem(m, 6) * y + elem(m, 10) * z + elem(m, 14)
    }
  end

  @doc """
  The transform a matrix without shear stands for: its translation, the length of each
  axis as the scale (the first negated when the matrix mirrors), and the rotation left.
  """
  @spec transform(matrix()) :: Transform.t()
  def transform(m) do
    x_axis = {elem(m, 0), elem(m, 1), elem(m, 2)}
    y_axis = {elem(m, 4), elem(m, 5), elem(m, 6)}
    z_axis = {elem(m, 8), elem(m, 9), elem(m, 10)}
    mirror = if determinant(x_axis, y_axis, z_axis) < 0, do: -1.0, else: 1.0
    {sx, sy, sz} = {magnitude(x_axis) * mirror, magnitude(y_axis), magnitude(z_axis)}

    %Transform{
      position: {elem(m, 12), elem(m, 13), elem(m, 14)},
      rotation: rotation(divide(x_axis, sx), divide(y_axis, sy), divide(z_axis, sz)),
      scale: {sx, sy, sz}
    }
  end

  defp determinant({ax, ay, az}, {bx, by, bz}, {cx, cy, cz}),
    do: ax * (by * cz - bz * cy) - bx * (ay * cz - az * cy) + cx * (ay * bz - az * by)

  defp magnitude({x, y, z}), do: :math.sqrt(x * x + y * y + z * z)

  defp divide({x, y, z}, scale) when scale == 0, do: {x, y, z}
  defp divide({x, y, z}, scale), do: {x / scale, y / scale, z / scale}

  defp rotation({m00, m10, m20}, {m01, m11, m21}, {m02, m12, m22}) do
    trace = m00 + m11 + m22

    cond do
      trace > 0 ->
        s = :math.sqrt(trace + 1.0) * 2
        normalized({(m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s, 0.25 * s})

      m00 > m11 and m00 > m22 ->
        s = :math.sqrt(1.0 + m00 - m11 - m22) * 2
        normalized({0.25 * s, (m01 + m10) / s, (m02 + m20) / s, (m21 - m12) / s})

      m11 > m22 ->
        s = :math.sqrt(1.0 + m11 - m00 - m22) * 2
        normalized({(m01 + m10) / s, 0.25 * s, (m12 + m21) / s, (m02 - m20) / s})

      true ->
        s = :math.sqrt(1.0 + m22 - m00 - m11) * 2
        normalized({(m02 + m20) / s, (m12 + m21) / s, 0.25 * s, (m10 - m01) / s})
    end
  end

  defp normalized({x, y, z, w}) do
    length = :math.sqrt(x * x + y * y + z * z + w * w)
    {x / length, y / length, z / length, w / length}
  end
end
