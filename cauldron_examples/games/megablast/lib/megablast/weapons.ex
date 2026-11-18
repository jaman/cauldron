defmodule Megablast.Weapons do
  @moduledoc """
  What a ship carries and what it fires. A kit is a level for each weapon:

    * `:main` (1–4) — one shot ahead, then two, then a fan of three, then of five
    * `:laser` (0–3) — a beam ahead that passes through everything, harder each level
    * `:rear` (0–2) — a shot behind, then two angled behind
    * `:side` (0–2) — a shot to each side, then two to each side
    * `:homing` (0–2) — missiles that turn after the nearest foe, more often each level
    * `:drones` (0–2) — drones flying beside the ship and firing with it
    * `:engine` (0–3) — a faster ship
    * `:bombs` (0–5) — bombs held; a bomb clears every bullet and strikes everything in view

  A shot is a `Cauldron2D.Projectiles` shot, `%{x, y, vx, vy, damage, kind, pierce?}`,
  `kind` `:pellet`, `:laser` or `:missile`; a missile homes on the nearest foe
  (`motion: {:homing, 16.0, 4.0}`). Losing a ship costs one level of every weapon above
  its first.
  """

  @type kit :: %{atom() => non_neg_integer()}
  @type shot :: %{
          required(:x) => float(),
          required(:y) => float(),
          required(:vx) => float(),
          required(:vy) => float(),
          required(:damage) => pos_integer(),
          required(:kind) => atom(),
          required(:pierce?) => boolean(),
          optional(:motion) => Cauldron2D.Projectiles.motion()
        }

  @firsts %{main: 1, laser: 0, rear: 0, side: 0, homing: 0, drones: 0, engine: 0, bombs: 1}
  @drone_reach 1.7

  @doc "The kit a new pilot starts with."
  @spec start() :: kit()
  def start, do: @firsts

  @doc "The kit after a ship is lost: every weapon one level down, none below its first."
  @spec lost(kit()) :: kit()
  def lost(kit),
    do:
      Map.new(kit, fn {weapon, level} -> {weapon, max(Map.fetch!(@firsts, weapon), level - 1)} end)

  @doc "Where a ship's drones fly, beside `{x, y}`."
  @spec drones(kit(), {number(), number()}) :: [{float(), float()}]
  def drones(%{drones: 0}, _at), do: []
  def drones(%{drones: 1}, {x, y}), do: [{x - @drone_reach, y + 0.4}, {x + @drone_reach, y + 0.4}]

  def drones(%{drones: _two}, {x, y}),
    do: [
      {x - @drone_reach, y + 0.4},
      {x + @drone_reach, y + 0.4},
      {x - 2 * @drone_reach, y + 0.9},
      {x + 2 * @drone_reach, y + 0.9}
    ]

  @doc "The shots one pull of the trigger fires from a ship at `{x, y}`, at `speed` tiles a second."
  @spec volley(kit(), {number(), number()}, number()) :: [shot()]
  def volley(kit, at, speed) do
    main(kit.main, at, speed) ++
      laser(kit.laser, at, speed) ++
      rear(kit.rear, at, speed) ++
      side(kit.side, at, speed) ++
      Enum.map(drones(kit, at), &pellet(&1, 0.0, -speed))
  end

  @doc "The missiles a ship at `{x, y}` lets go."
  @spec missiles(kit(), {number(), number()}) :: [shot()]
  def missiles(%{homing: 0}, _at), do: []

  def missiles(_kit, {x, y}),
    do: [
      missile(x - 0.6, y, -3.0),
      missile(x + 0.6, y, 3.0)
    ]

  @doc "Seconds between missiles at a homing level."
  @spec missile_every(non_neg_integer()) :: number() | nil
  def missile_every(0), do: nil
  def missile_every(1), do: 0.9
  def missile_every(_two), do: 0.5

  defp main(1, at, speed), do: [pellet(at, 0.0, -speed)]

  defp main(2, {x, y}, speed),
    do: [pellet({x - 0.35, y}, 0.0, -speed), pellet({x + 0.35, y}, 0.0, -speed)]

  defp main(3, at, speed), do: Enum.map([-4.0, 0.0, 4.0], &pellet(at, &1, -speed))
  defp main(_four, at, speed), do: Enum.map([-7.0, -3.5, 0.0, 3.5, 7.0], &pellet(at, &1, -speed))

  defp laser(0, _at, _speed), do: []

  defp laser(level, {x, y}, speed),
    do: [
      %{x: x, y: y - 0.6, vx: 0.0, vy: -speed * 1.6, damage: level, kind: :laser, pierce?: true}
    ]

  defp rear(0, _at, _speed), do: []
  defp rear(1, at, speed), do: [pellet(at, 0.0, speed * 0.7)]
  defp rear(_two, at, speed), do: [pellet(at, -4.0, speed * 0.7), pellet(at, 4.0, speed * 0.7)]

  defp side(0, _at, _speed), do: []
  defp side(1, at, speed), do: [pellet(at, -speed * 0.6, 0.0), pellet(at, speed * 0.6, 0.0)]

  defp side(_two, at, speed),
    do: [
      pellet(at, -speed * 0.6, 0.0),
      pellet(at, speed * 0.6, 0.0),
      pellet(at, -speed * 0.45, -speed * 0.45),
      pellet(at, speed * 0.45, -speed * 0.45)
    ]

  defp missile(x, y, vx),
    do: %{
      x: x,
      y: y,
      vx: vx,
      vy: -6.0,
      damage: 2,
      kind: :missile,
      pierce?: false,
      motion: {:homing, 16.0, 4.0}
    }

  defp pellet({x, y}, vx, vy),
    do: %{x: x / 1, y: y - 0.5, vx: vx, vy: vy, damage: 1, kind: :pellet, pierce?: false}
end
