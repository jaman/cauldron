defmodule Greenware.Mend.Check do
  @moduledoc "The tests a mending must pass, written as plain terms so a puzzle is data."

  import Greenware.Mend, only: [filled: 2, filled: 3, mean: 2, at: 3]

  @doc "Run every check of `state`'s puzzle."
  def run(%{puzzle: puzzle} = state) do
    rows =
      Enum.map(puzzle.checks, fn check ->
        {label, ok?, detail} = one(state, puzzle, check)
        %{label: label, ok?: ok?, detail: detail}
      end)

    %{
      ok?: Enum.all?(rows, & &1.ok?),
      rows: rows,
      passed: Enum.count(rows, & &1.ok?),
      total: length(rows)
    }
  end

  defp one(state, puzzle, {:fill, zone, threshold, label}) do
    cells = zone(puzzle, zone)
    fraction = filled(state, cells)
    {label, fraction >= threshold, percent(fraction)}
  end

  defp one(state, _puzzle, {:wire, count, label}) do
    wire = MapSet.size(state.wire)
    {label, wire >= count, "#{wire}/#{count}"}
  end

  defp one(state, _puzzle, {:fired, minimum, label}) do
    {label, state.fired >= minimum, "#{round(state.fired)}/100"}
  end

  defp one(state, _puzzle, {:wet_max, maximum, label}) do
    {label, state.wet <= maximum, "wet #{round(state.wet)}"}
  end

  defp one(state, _puzzle, {:wet_min, minimum, label}) do
    {label, state.wet >= minimum, "wet #{round(state.wet)}"}
  end

  defp one(state, puzzle, {:tune, zones, target, tolerance, label}) do
    values = Enum.map(zones, fn zone -> {zone, mean(state, zone(puzzle, zone))} end)
    ok? = Enum.all?(values, fn {_zone, value} -> abs(value - target) <= tolerance end)

    detail =
      values
      |> Enum.map_join(" ", fn {zone, value} -> "#{zone_name(zone)} #{round(value)}" end)

    {label, ok?, detail}
  end

  defp one(state, puzzle, {:flat, zone, tolerance, label}) do
    cells = zone(puzzle, zone)
    heights = Enum.map(cells, fn {x, y} -> at(state, x, y) end)
    spread = if heights == [], do: 0, else: Enum.max(heights) - Enum.min(heights)
    {label, spread <= tolerance, "spread #{spread}"}
  end

  defp one(state, puzzle, {:seal, zone, threshold, label}) do
    fraction = filled(state, zone(puzzle, zone), 35)
    {label, fraction >= threshold, percent(fraction)}
  end

  defp one(_state, _puzzle, other), do: {inspect(other), false, "?"}

  defp zone(puzzle, name), do: Map.get(puzzle.zones, name, MapSet.new())

  defp zone_name(:note_a), do: "A"
  defp zone_name(:note_b), do: "B"
  defp zone_name(:note_c), do: "C"
  defp zone_name(other), do: other |> to_string() |> String.upcase()

  defp percent(fraction), do: "#{round(fraction * 100)}%"
end
