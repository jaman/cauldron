defmodule Town.Rules do
  @moduledoc """
  How far a target is, under the rules a game may measure by: `:euclid` (straight-line
  tiles), `:dnd` (every step one, diagonals included), `:pathfinder` (diagonals
  alternate one and two).
  """

  @type rule :: :euclid | :dnd | :pathfinder

  @rules [:euclid, :dnd, :pathfinder]

  @doc "The rules, in the order `next/1` cycles them."
  @spec rules() :: [rule()]
  def rules, do: @rules

  @doc "The rule after `rule`, wrapping."
  @spec next(rule()) :: rule()
  def next(rule),
    do: Enum.at(@rules, rem(Enum.find_index(@rules, &(&1 == rule)) + 1, length(@rules)))

  @doc "The distance between two tiles under `rule`."
  @spec distance(rule(), {number(), number()}, {number(), number()}) :: number()
  def distance(:euclid, {ax, ay}, {bx, by}),
    do: :math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay))

  def distance(:dnd, {ax, ay}, {bx, by}), do: max(abs(bx - ax), abs(by - ay))

  def distance(:pathfinder, {ax, ay}, {bx, by}) do
    long = max(abs(bx - ax), abs(by - ay))
    short = min(abs(bx - ax), abs(by - ay))
    long + div(short, 2)
  end

  @doc "A distance as the rule writes it: one decimal for `:euclid`, whole tiles otherwise."
  @spec label(rule(), number()) :: String.t()
  def label(:euclid, distance), do: "#{Float.round(distance * 1.0, 1)}"
  def label(_rule, distance), do: "#{distance}"
end
