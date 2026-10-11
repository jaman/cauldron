defmodule Cauldron2D.Steer do
  @moduledoc """
  Choosing which of eight directions to walk toward a target, trying the next best when
  the best is blocked — the chase that makes a pursuer feel its way round corners
  without finding a path.

      {direction, acc} =
        Cauldron2D.Steer.chase(acc, current, {target_x - x, target_y - y}, &walk/2, &roll/1)

  Directions are `0..7`, east counting round anticlockwise in eighths, so `2` is `+y`,
  and `nil` for standing still. `walk.(acc, direction)` tries a step that way and answers
  `{:ok, acc}` having taken it or `{:blocked, acc}`. `roll.(acc)` gives a random `0..255`
  and the new `acc`, so the choices follow the game's own random stream.

  The pursuer heads diagonally when the target is off both axes, then along the longer
  axis, then the shorter (sometimes the other way round, by chance), then the way it was
  going, then any direction, and turns back on itself only last. A difference of `:slack`
  or less on an axis counts as none. Default `10`.
  """

  @directions 0..7
  @diagonal :math.sqrt(0.5)

  @type direction :: 0..7 | nil

  @doc "The unit step for `direction`, `{dx, dy}`; `{0.0, 0.0}` for `nil`."
  @spec vector(direction()) :: {float(), float()}
  def vector(nil), do: {0.0, 0.0}

  def vector(direction) do
    elem(
      {{1.0, 0.0}, {@diagonal, @diagonal}, {0.0, 1.0}, {-@diagonal, @diagonal}, {-1.0, 0.0},
       {-@diagonal, -@diagonal}, {0.0, -1.0}, {@diagonal, -@diagonal}},
      direction
    )
  end

  @doc "The direction opposite `direction`."
  @spec opposite(direction()) :: direction()
  def opposite(nil), do: nil
  def opposite(direction), do: rem(direction + 4, 8)

  @doc "The direction chosen and taken, and the new `acc`. See the moduledoc."
  @spec chase(
          acc,
          direction(),
          {number(), number()},
          (acc, 0..7 -> {:ok, acc} | {:blocked, acc}),
          (acc -> {0..255, acc}),
          keyword()
        ) ::
          {direction(), acc}
        when acc: term()
  def chase(acc, current, {dx, dy}, walk, roll, opts \\ []) do
    slack = Keyword.get(opts, :slack, 10)
    {chance, acc} = roll.(acc)
    {sweep, acc} = roll.(acc)

    {dx, dy}
    |> preferred(slack, chance)
    |> candidates(current, sweep)
    |> Enum.reduce_while({nil, acc}, fn direction, {_none, inner} ->
      case walk.(inner, direction) do
        {:ok, moved} -> {:halt, {direction, moved}}
        {:blocked, unmoved} -> {:cont, {nil, unmoved}}
      end
    end)
  end

  defp preferred({dx, dy}, slack, chance) do
    across = axis(dx, slack, 0, 4)
    up = axis(dy, slack, 2, 6)
    diagonal = if across != nil and up != nil, do: diagonal(dx, dy)
    {first, second} = if chance > 200 or abs(dy) > abs(dx), do: {up, across}, else: {across, up}
    [diagonal, first, second]
  end

  defp axis(delta, slack, positive, _negative) when delta > slack, do: positive
  defp axis(delta, slack, _positive, negative) when delta < -slack, do: negative
  defp axis(_delta, _slack, _positive, _negative), do: nil

  defp candidates(preferred, current, sweep) do
    back = opposite(current)

    order =
      if Bitwise.band(sweep, 1) == 1,
        do: Enum.to_list(@directions),
        else: Enum.reverse(@directions)

    (Enum.map(preferred, &unless_back(&1, back)) ++
       [current] ++ Enum.reject(order, &(&1 == back)) ++ [back])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp unless_back(direction, back) when direction == back, do: nil
  defp unless_back(direction, _back), do: direction

  defp diagonal(dx, dy) do
    case {dy < 0, dx > 0} do
      {false, false} -> 3
      {false, true} -> 1
      {true, false} -> 5
      {true, true} -> 7
    end
  end
end
