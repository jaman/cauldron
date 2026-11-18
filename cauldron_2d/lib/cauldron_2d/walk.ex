defmodule Cauldron2D.Walk do
  @moduledoc """
  Walking in a top-down world, or through an eye: which way the held actions point, how
  hard a stick pushes, and a step that slides along walls.

      {dx, dy} = Cauldron2D.Walk.direction(input.held)
      push = Cauldron2D.Walk.strength(input)
      Cauldron2D.Walk.slide({x, y}, {dx, dy}, 4.0 * push * dt, &walkable?/1)

  The directions are a map from action to a unit step, by default
  `%{left: {-1, 0}, right: {1, 0}, up: {0, -1}, down: {0, 1}}`, `y` growing downward.
  """

  @directions %{left: {-1, 0}, right: {1, 0}, up: {0, -1}, down: {0, 1}}

  @type point :: {number(), number()}
  @type directions :: %{atom() => {number(), number()}}

  @doc "The sum of the steps of the held directions; `{0, 0}` when none is held or they cancel."
  @spec direction(MapSet.t(atom()), directions()) :: {number(), number()}
  def direction(held, directions \\ @directions) do
    Enum.reduce(directions, {0, 0}, fn {action, {dx, dy}}, {x, y} ->
      if MapSet.member?(held, action), do: {x + dx, y + dy}, else: {x, y}
    end)
  end

  @doc """
  How hard the held directions are pushed, `0.0..1.0`: the strongest of their
  `:strength`s (a stick's), `1.0` for a held key or when none is held.
  """
  @spec strength(map(), directions()) :: float()
  def strength(%{held: held} = input, directions \\ @directions) do
    strengths = Map.get(input, :strength, %{})

    case for(
           action <- Map.keys(directions),
           MapSet.member?(held, action),
           do: Map.get(strengths, action, 1.0)
         ) do
      [] -> 1.0
      pushes -> Enum.max(pushes)
    end
  end

  @doc """
  `direction` turned to the eye's heading `eye` (radians, `0` along `+x`): up walks where
  the eye looks, down away, left and right across.
  """
  @spec relative({number(), number()}, number()) :: {float(), float()}
  def relative({dx, dy}, eye) do
    {fx, fy} = {:math.cos(eye), :math.sin(eye)}
    {-dy * fx - dx * fy, -dy * fy + dx * fx}
  end

  @doc """
  A step of `step` tiles from `from` along `direction`: `{:moved, to}` where `walkable?`
  allows it, sliding along a wall — only across, or only along — when the full step is
  blocked; `:blocked` when no part of it is open.
  """
  @spec slide(point(), {number(), number()}, number(), (point() -> boolean())) ::
          {:moved, point()} | :blocked
  def slide({x, y}, {dx, dy}, step, walkable?) do
    length = :math.sqrt(dx * dx + dy * dy)
    {tx, ty} = {x + dx / length * step, y + dy / length * step}

    cond do
      walkable?.({tx, ty}) -> {:moved, {tx, ty}}
      tx != x and walkable?.({tx, y}) -> {:moved, {tx, y}}
      ty != y and walkable?.({x, ty}) -> {:moved, {x, ty}}
      true -> :blocked
    end
  end
end
