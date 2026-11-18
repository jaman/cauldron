defmodule Cauldron3D.Quat do
  @moduledoc """
  Rotations as unit quaternions `{x, y, z, w}`.

      q = Cauldron3D.Quat.from_euler({0.0, 0.0, :math.pi() / 2})
      Cauldron3D.Quat.rotate(q, {1.0, 0.0, 0.0})
      #=> {0.0, 1.0, 0.0}
  """

  alias Cauldron3D.Vec

  @type t :: {float(), float(), float(), float()}

  @doc "No rotation."
  @spec identity() :: t()
  def identity, do: {0.0, 0.0, 0.0, 1.0}

  @doc """
  The rotation turning `x` radians about the x axis, then `y` about the y axis, then `z`
  about the z axis.
  """
  @spec from_euler(Vec.t()) :: t()
  def from_euler({x, y, z}) do
    {sr, cr} = {:math.sin(x / 2), :math.cos(x / 2)}
    {sp, cp} = {:math.sin(y / 2), :math.cos(y / 2)}
    {sy, cy} = {:math.sin(z / 2), :math.cos(z / 2)}

    {sr * cp * cy - cr * sp * sy, cr * sp * cy + sr * cp * sy, cr * cp * sy - sr * sp * cy,
     cr * cp * cy + sr * sp * sy}
  end

  @doc "`q` scaled to unit length."
  @spec normalize(t()) :: t()
  def normalize({x, y, z, w}) do
    length = :math.sqrt(x * x + y * y + z * z + w * w)
    if length == 0, do: identity(), else: {x / length, y / length, z / length, w / length}
  end

  @doc "The rotation `t` of the way from `a` to `b`, along the shorter arc."
  @spec slerp(t(), t(), float()) :: t()
  def slerp({ax, ay, az, aw} = a, {bx, by, bz, bw}, t) do
    dot = ax * bx + ay * by + az * bz + aw * bw
    {b, dot} = if dot < 0, do: {{-bx, -by, -bz, -bw}, -dot}, else: {{bx, by, bz, bw}, dot}

    {wa, wb} =
      if dot > 0.9995 do
        {1 - t, t}
      else
        angle = :math.acos(dot)
        sine = :math.sin(angle)
        {:math.sin((1 - t) * angle) / sine, :math.sin(t * angle) / sine}
      end

    {cx, cy, cz, cw} = b
    {x, y, z, w} = a
    normalize({x * wa + cx * wb, y * wa + cy * wb, z * wa + cz * wb, w * wa + cw * wb})
  end

  @doc "The rotation turning `angle` radians about the unit vector `axis`."
  @spec axis_angle(Vec.t(), number()) :: t()
  def axis_angle({x, y, z}, angle) do
    s = :math.sin(angle / 2)
    {x * s, y * s, z * s, :math.cos(angle / 2)}
  end

  @doc "The rotation doing `inner` and then `outer`."
  @spec multiply(t(), t()) :: t()
  def multiply({ax, ay, az, aw}, {bx, by, bz, bw}) do
    {aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
     aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz}
  end

  @doc "The rotation undoing `q`."
  @spec conjugate(t()) :: t()
  def conjugate({x, y, z, w}), do: {-x, -y, -z, w}

  @doc """
  The shortest rotation turning direction `from` onto direction `to`; neither needs unit
  length. Opposite directions turn half a turn about an axis across `from`.
  """
  @spec from_to(Vec.t(), Vec.t()) :: t()
  def from_to(from, to) do
    a = Vec.normalize(from)
    b = Vec.normalize(to)
    dot = Vec.dot(a, b)

    if dot < -0.999_999 do
      across = Vec.cross({1.0, 0.0, 0.0}, a)
      across = if Vec.length(across) < 1.0e-6, do: Vec.cross({0.0, 1.0, 0.0}, a), else: across
      axis_angle(Vec.normalize(across), :math.pi())
    else
      {x, y, z} = Vec.cross(a, b)
      normalize({x, y, z, 1.0 + dot})
    end
  end

  @doc "The rotation as the rows of a 3 by 3 matrix."
  @spec to_rows(t()) :: {Vec.t(), Vec.t(), Vec.t()}
  def to_rows({x, y, z, w}) do
    {{1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y)},
     {2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)},
     {2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)}}
  end

  @doc "`vector` turned by `q`."
  @spec rotate(t(), Vec.t()) :: Vec.t()
  def rotate(q, vector) do
    {r0, r1, r2} = to_rows(q)
    {Vec.dot(r0, vector), Vec.dot(r1, vector), Vec.dot(r2, vector)}
  end
end
