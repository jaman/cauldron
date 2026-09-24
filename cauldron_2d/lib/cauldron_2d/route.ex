defmodule Cauldron2D.Route do
  @moduledoc """
  A way from where something stands to where it was sent, and walking it a step at a time.

      {:ok, route} = Cauldron2D.Route.to(&MyGame.open?/1, {x, y}, aim, size: {width, height})
      {{x, y}, route} = Cauldron2D.Route.advance(route, {x, y}, speed * dt)

  This is what a game needs behind a click on the ground: the terminal client already
  reports where the pointer is in the world as an input's `:aim`, `to/4` turns that into a
  way across the grid with `Cauldron2D.Grid.Path`, and `advance/3` walks it.

  A route is the tile centres still to walk through, in order, so it is a plain list of
  points: it saves, replays and pattern matches like any other list, and `[]` means there
  is nowhere left to go. Dropping a route is how a game cancels one — a key press, a
  shove, a door closing.

  `advance/3` passes through as many points as the distance covers, so a small tile and a
  fast mover do not lose steps. `heading/2` is the way to the next point, for posing a
  mover or aiming what it carries.
  """

  alias Cauldron2D.Grid.Path

  @type point :: {number(), number()}
  @type t :: [point()]

  @doc """
  The way from `from` to `to`: the tile centres to walk through, and `to` itself at the end.

  Both points are in tiles and may be fractional; the tiles they fall in are what the way
  is found between, but the last step is the point asked for rather than the middle of the
  tile it falls in, so a mover arrives where it was sent. `passable?` and `opts` are
  `Cauldron2D.Grid.Path.find/4`'s, so `:size` is required. `:none` when there is no way.

  Standing already where it was sent gives `{:ok, []}`; standing elsewhere in the same tile
  gives the one step across it.
  """
  @spec to(Path.passable(), point(), point(), keyword()) :: {:ok, t()} | :none
  def to(passable?, {from_x, from_y} = from, {to_x, to_y} = to, opts) do
    start = {floor(from_x), floor(from_y)}
    goal = {floor(to_x), floor(to_y)}

    case Path.find(passable?, start, goal, opts) do
      {:ok, []} -> {:ok, across(from, to)}
      {:ok, tiles} -> {:ok, tiles |> Enum.map(&centre/1) |> List.replace_at(-1, to)}
      :none -> :none
    end
  end

  defp centre({x, y}), do: {x + 0.5, y + 0.5}

  defp across({from_x, from_y}, {to_x, to_y} = to) do
    if abs(to_x - from_x) < 0.01 and abs(to_y - from_y) < 0.01, do: [], else: [to]
  end

  @doc """
  `from` moved `step` along `route`, and what is left of the route.

  A point the step reaches or passes is dropped and the rest of the step carries on
  towards the next one. An empty route, or a step of nothing, leaves both alone.
  """
  @spec advance(t(), point(), number()) :: {point(), t()}
  def advance([], from, _step), do: {from, []}

  def advance(route, from, step) when step <= 0, do: {from, route}

  def advance([{next_x, next_y} = next | rest] = route, {x, y} = from, step) do
    {dx, dy} = {next_x - x, next_y - y}
    distance = :math.sqrt(dx * dx + dy * dy)

    cond do
      distance < 1.0e-9 -> advance(rest, from, step)
      distance <= step -> advance(rest, next, step - distance)
      true -> {{x + dx / distance * step, y + dy / distance * step}, route}
    end
  end

  @doc "Whether there is nowhere left to go."
  @spec arrived?(t()) :: boolean()
  def arrived?(route), do: route == []

  @doc """
  The heading from `from` towards the next point of `route`, in radians with `0` along
  `+x`, or `nil` for a route with nothing left.
  """
  @spec heading(t(), point()) :: float() | nil
  def heading([], _from), do: nil

  def heading([{next_x, next_y} | _rest], {x, y}), do: :math.atan2(next_y - y, next_x - x)

  @doc "Where the route ends, or `nil` when there is nowhere left to go."
  @spec goal(t()) :: point() | nil
  def goal([]), do: nil
  def goal(route), do: List.last(route)
end
