defmodule Cauldron3D.Vec do
  @moduledoc """
  Three-component vectors as `{x, y, z}` float tuples.

      Cauldron3D.Vec.add({1.0, 0.0, 0.0}, {0.0, 2.0, 0.0})
      #=> {1.0, 2.0, 0.0}
  """

  @type t :: {float(), float(), float()}

  @doc "The zero vector."
  @spec zero() :: t()
  def zero, do: {0.0, 0.0, 0.0}

  @doc "`a + b`."
  @spec add(t(), t()) :: t()
  def add({ax, ay, az}, {bx, by, bz}), do: {ax + bx, ay + by, az + bz}

  @doc "`a - b`."
  @spec sub(t(), t()) :: t()
  def sub({ax, ay, az}, {bx, by, bz}), do: {ax - bx, ay - by, az - bz}

  @doc "`v * s`."
  @spec scale(t(), number()) :: t()
  def scale({x, y, z}, s), do: {x * s, y * s, z * s}

  @doc "`a + b * s`."
  @spec madd(t(), t(), number()) :: t()
  def madd({ax, ay, az}, {bx, by, bz}, s), do: {ax + bx * s, ay + by * s, az + bz * s}

  @doc "The dot product."
  @spec dot(t(), t()) :: float()
  def dot({ax, ay, az}, {bx, by, bz}), do: ax * bx + ay * by + az * bz

  @doc "The cross product."
  @spec cross(t(), t()) :: t()
  def cross({ax, ay, az}, {bx, by, bz}),
    do: {ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx}

  @doc "The length."
  @spec length(t()) :: float()
  def length(v), do: :math.sqrt(dot(v, v))

  @doc "The vector scaled to length one; the zero vector stays zero."
  @spec normalize(t()) :: t()
  def normalize(v) do
    case __MODULE__.length(v) do
      length when length == 0 -> {0.0, 0.0, 0.0}
      length -> scale(v, 1 / length)
    end
  end

  @doc "The point `t` of the way from `a` to `b`."
  @spec lerp(t(), t(), number()) :: t()
  def lerp(a, b, t), do: madd(a, sub(b, a), t)

  @doc "Each component the smaller of the two."
  @spec min(t(), t()) :: t()
  def min({ax, ay, az}, {bx, by, bz}),
    do: {Kernel.min(ax, bx), Kernel.min(ay, by), Kernel.min(az, bz)}

  @doc "Each component the larger of the two."
  @spec max(t(), t()) :: t()
  def max({ax, ay, az}, {bx, by, bz}),
    do: {Kernel.max(ax, bx), Kernel.max(ay, by), Kernel.max(az, bz)}

  @doc "The vector as floats."
  @spec float({number(), number(), number()}) :: t()
  def float({x, y, z}), do: {x / 1, y / 1, z / 1}
end
