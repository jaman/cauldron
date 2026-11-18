defmodule Courtyard.Gait do
  @moduledoc """
  A walk, a run and standing still, made from sines: the rotations of a VRM avatar's
  humanoid bones and how far its hips dip, for a speed and a point in the stride.

      %{turns: turns, dip: dip} = Courtyard.Gait.pose(bones, 1.4, phase, time)

  `bones` maps standard bone names (`"leftUpperLeg"`, …) to the bones of the avatar's rig;
  names it lacks are left out. `speed` is in metres a second, `phase` the stride in
  radians (a whole stride, both steps, is `2π`), `time` the seconds the avatar has stood
  for breathing. The rotations are in the avatar's own axes, which assumes its bones'
  rest rotations are all none, as a VRM 0.x avatar's are, and that it faces −Z.
  `stride/1` is how far a whole stride carries the avatar at a speed.
  """

  alias Cauldron3D.Quat

  @x {1.0, 0.0, 0.0}
  @y {0.0, 1.0, 0.0}
  @z {0.0, 0.0, 1.0}
  @arms_down 1.25
  @run 3.5

  @doc "The length of a whole stride at `speed`, in metres."
  @spec stride(number()) :: float()
  def stride(speed), do: speed |> Kernel.*(0.38) |> Kernel.+(0.9) |> min(2.2)

  @doc "The bone rotations and hip dip at `speed`, `phase` and `time`."
  @spec pose(%{String.t() => non_neg_integer()}, number(), number(), number()) ::
          %{turns: %{non_neg_integer() => Quat.t()}, dip: float()}
  def pose(bones, speed, phase, time) do
    effort = min(speed / @run, 1.0)
    swing = :math.sin(phase)
    breath = :math.sin(time * 1.7)

    turns =
      [
        {"leftUpperLeg", Quat.axis_angle(@x, swing * leg(effort))},
        {"rightUpperLeg", Quat.axis_angle(@x, -swing * leg(effort))},
        {"leftLowerLeg", Quat.axis_angle(@x, -knee(effort, phase))},
        {"rightLowerLeg", Quat.axis_angle(@x, -knee(effort, phase + :math.pi()))},
        {"leftFoot", Quat.axis_angle(@x, -swing * leg(effort) * 0.4)},
        {"rightFoot", Quat.axis_angle(@x, swing * leg(effort) * 0.4)},
        {"leftUpperArm", arm(@arms_down - 0.04 * breath, -swing * effort * 0.7)},
        {"rightUpperArm", arm(-@arms_down + 0.04 * breath, swing * effort * 0.7)},
        {"leftLowerArm", Quat.axis_angle(@y, -0.25 - effort * 0.9)},
        {"rightLowerArm", Quat.axis_angle(@y, 0.25 + effort * 0.9)},
        {"spine",
         Quat.multiply(
           Quat.axis_angle(@y, swing * effort * 0.12),
           Quat.axis_angle(@x, 0.015 * breath - effort * 0.12)
         )},
        {"neck", Quat.axis_angle(@x, effort * 0.08)}
      ]
      |> Enum.flat_map(fn {name, turn} ->
        case Map.fetch(bones, name) do
          {:ok, bone} -> [{bone, turn}]
          :error -> []
        end
      end)
      |> Map.new()

    %{turns: turns, dip: effort * 0.035 * abs(:math.cos(phase))}
  end

  defp leg(effort), do: 0.12 * min(effort * 4, 1.0) + effort * 0.5

  defp knee(effort, phase), do: 0.08 + effort * (0.25 + 1.1 * max(0.0, :math.cos(phase)))

  defp arm(down, swing),
    do: Quat.multiply(Quat.axis_angle(@x, swing), Quat.axis_angle(@z, down))
end
