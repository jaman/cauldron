defmodule CauldronGPU.Quat do
  @moduledoc """
  Rotations as unit quaternions `{x, y, z, w}`, in the renderer's frame: right-handed,
  +Y up, the camera looking down -Z.

      CauldronGPU.Quat.yaw_pitch(:math.pi() / 2, -0.2)
  """

  @type t :: {float(), float(), float(), float()}
  @type vec3 :: {number(), number(), number()}

  @doc "No rotation."
  @spec identity() :: t()
  def identity, do: {0.0, 0.0, 0.0, 1.0}

  @doc "A rotation of `angle` radians about `axis` (any length but zero)."
  @spec axis_angle(vec3(), number()) :: t()
  def axis_angle({x, y, z}, angle) do
    size = :math.sqrt(x * x + y * y + z * z)
    half = angle / 2
    scale = :math.sin(half) / size
    {x * scale, y * scale, z * scale, :math.cos(half)}
  end

  @doc "Turn `yaw` radians about +Y, then tilt `pitch` radians about the turned +X."
  @spec yaw_pitch(number(), number()) :: t()
  def yaw_pitch(yaw, pitch),
    do: multiply(axis_angle({0, 1, 0}, yaw), axis_angle({1, 0, 0}, pitch))

  @doc "The rotation `a` applied after `b`."
  @spec multiply(t(), t()) :: t()
  def multiply({ax, ay, az, aw}, {bx, by, bz, bw}) do
    {aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
     aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz}
  end

  @doc "`vector` turned by `rotation`."
  @spec rotate(t(), vec3()) :: {float(), float(), float()}
  def rotate({qx, qy, qz, qw}, {vx, vy, vz}) do
    {tx, ty, tz} = scale(cross({qx, qy, qz}, {vx, vy, vz}), 2)
    {cx, cy, cz} = cross({qx, qy, qz}, {tx, ty, tz})
    {vx + tx * qw + cx, vy + ty * qw + cy, vz + tz * qw + cz}
  end

  defp cross({ax, ay, az}, {bx, by, bz}),
    do: {ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx}

  defp scale({x, y, z}, factor), do: {x * factor, y * factor, z * factor}
end
