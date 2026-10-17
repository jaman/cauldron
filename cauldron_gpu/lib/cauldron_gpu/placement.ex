defmodule CauldronGPU.Placement do
  @moduledoc """
  Transforms standing a model made in map axes (x forward, y left, z up) at a point of a
  map, in the renderer's frame, matching `CauldronGPU.Bsp.transform/1` and
  `CauldronGPU.Bsp.point/2`: map units times `scale` metres, +Z up turned to +Y up.

      CauldronGPU.Placement.transform(1 / 32, {480.0, -352.0, 88.0}, 90)
  """

  alias CauldronGPU.{Quat, Transform}

  @type vec3 :: {number(), number(), number()}

  @doc """
  The transform for a model at map point `origin` turned by `angles`: a yaw in degrees
  (0 along +X, counter-clockwise from above), or `{pitch, yaw, roll}` in degrees, applied
  roll about x, then pitch about y, then yaw about z.
  """
  @spec transform(number(), vec3(), number() | vec3()) :: Transform.t()
  def transform(scale, origin, yaw) when is_number(yaw), do: transform(scale, origin, {0, yaw, 0})

  def transform(scale, {x, y, z}, {pitch, yaw, roll}) do
    turn =
      Quat.axis_angle({0, 0, 1}, radians(yaw))
      |> Quat.multiply(Quat.axis_angle({0, 1, 0}, radians(pitch)))
      |> Quat.multiply(Quat.axis_angle({1, 0, 0}, radians(roll)))

    Transform.new(
      position: {x * scale, z * scale, -y * scale},
      rotation: Quat.multiply(Quat.axis_angle({1, 0, 0}, -:math.pi() / 2), turn),
      scale: scale
    )
  end

  defp radians(degrees), do: degrees * :math.pi() / 180
end
