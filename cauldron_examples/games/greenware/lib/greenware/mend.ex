defmodule Greenware.Mend do
  @moduledoc """
  A mending in progress: the clay height field, the wire, what the clay is doing, and
  the tools that change it. Everything is a value; the world keeps it and the renderer
  reads it.
  """

  alias Greenware.Mend.{Check, Shape}

  @width Shape.width()
  @height Shape.height()
  @max_height 255
  @tools [:thumb, :pin, :paddle, :sponge, :wire, :water, :heat]

  def width, do: @width
  def height, do: @height
  def tools, do: @tools

  @type t :: %{
          puzzle: map(),
          heights: tuple(),
          wire: MapSet.t(),
          wet: float(),
          fired: float(),
          clay: float(),
          water: float(),
          fuel: float(),
          rev: integer(),
          undo: [map()],
          result: map() | nil,
          done?: boolean()
        }

  @doc "A fresh mending of `puzzle`."
  def new(%{mask: mask, holes: holes} = puzzle) do
    puzzle = Map.put(puzzle, :area, Shape.grow(mask, 5))

    heights =
      for y <- 0..(@height - 1),
          x <- 0..(@width - 1),
          into: [],
          do:
            if(MapSet.member?(mask, {x, y}) and not MapSet.member?(holes, {x, y}),
              do: 150,
              else: 0
            )

    %{
      puzzle: puzzle,
      heights: List.to_tuple(heights),
      wire: MapSet.new(),
      wet: Map.get(puzzle, :wet, 60) * 1.0,
      fired: Map.get(puzzle, :fired_start, 0) * 1.0,
      clay: Map.get(puzzle, :clay, 80) * 1.0,
      water: 100.0,
      fuel: 100.0,
      rev: 0,
      undo: [],
      result: nil,
      done?: false
    }
  end

  @doc "The current height at a cell, 0..255."
  def at(%{heights: heights}, x, y) when x >= 0 and y >= 0 and x < @width and y < @height,
    do: elem(heights, y * @width + x)

  def at(_state, _x, _y), do: 0

  @doc "The average height of a set of cells."
  def mean(state, cells) do
    if MapSet.size(cells) == 0 do
      0.0
    else
      total = Enum.reduce(cells, 0, fn {x, y}, sum -> sum + at(state, x, y) end)
      total / MapSet.size(cells)
    end
  end

  @doc "The fraction of `cells` at or above the fill height."
  def filled(state, cells, threshold \\ 30) do
    if MapSet.size(cells) == 0 do
      1.0
    else
      count = Enum.count(cells, fn {x, y} -> at(state, x, y) >= threshold end)
      count / MapSet.size(cells)
    end
  end

  @doc "Remember the clay before a stroke."
  def begin(%{undo: undo} = state) do
    snapshot = Map.take(state, [:heights, :wire, :wet, :fired, :clay, :water, :fuel, :rev])
    %{state | undo: Enum.take([snapshot | undo], 14), result: nil}
  end

  @doc "The last stroke undone."
  def undo(%{undo: []} = state), do: state

  def undo(%{undo: [snapshot | rest]} = state) do
    Map.merge(state, Map.put(snapshot, :undo, rest))
  end

  @doc "The mending fresh again, keeping its puzzle."
  def reset(%{puzzle: puzzle}), do: new(puzzle)

  @doc "Apply `tool` at a cell. `pressure` is 0.0..1.0, normally 1.0."
  def apply(state, tool, x, y, pressure \\ 1.0)

  def apply(%{done?: true} = state, _tool, _x, _y, _pressure), do: state

  def apply(state, tool, x, y, pressure) when tool in @tools do
    if tool in [:water, :heat] do
      resource(state, tool, pressure)
    else
      stroke(state, tool, x, y, pressure)
    end
  end

  defp resource(%{fired: fired} = state, :heat, pressure) when fired < 100 do
    if state.fuel <= 0 do
      state
    else
      fuel = max(0.0, state.fuel - 4.0 * pressure)

      %{
        state
        | fired: min(100.0, fired + 9.0 * pressure),
          wet: max(0.0, state.wet - 3.0),
          fuel: fuel,
          rev: state.rev + 1,
          result: nil
      }
    end
  end

  defp resource(%{fired: _} = state, :heat, _pressure), do: state

  defp resource(%{wet: wet} = state, :water, pressure) when wet < 100 do
    if state.water <= 0 do
      state
    else
      %{
        state
        | wet: min(100.0, wet + 14.0 * pressure),
          water: max(0.0, state.water - 4.0),
          rev: state.rev + 1,
          result: nil
      }
    end
  end

  defp resource(state, :water, _pressure), do: state

  defp stroke(%{fired: fired} = state, _tool, _x, _y, _pressure) when fired >= 68, do: state

  defp stroke(%{clay: clay} = state, :thumb, x, y, pressure) when clay > 0 do
    if not area?(state, x, y) do
      state
    else
      wet_factor = 0.35 + state.wet / 100 * 0.65
      radius = 4
      cells = Shape.disc(x, y, radius)

      {heights, added} =
        Enum.reduce(cells, {state.heights, 0}, fn {cx, cy}, {heights, added} ->
          if area?(state, cx, cy) do
            index = cy * @width + cx
            current = elem(heights, index)
            falloff = 1.0 - distance(cx, cy, x, y) / (radius + 1)
            add = round(24.0 * pressure * wet_factor * max(0.12, falloff))
            new = min(@max_height, current + add)

            if new > current do
              {put_elem(heights, index, new), added + (new - current)}
            else
              {heights, added}
            end
          else
            {heights, added}
          end
        end)

      if added == 0 do
        state
      else
        cost = added / @max_height * 0.6

        %{
          state
          | heights: heights,
            clay: max(0.0, state.clay - cost),
            rev: state.rev + 1,
            result: nil
        }
      end
    end
  end

  defp stroke(state, :pin, x, y, pressure) do
    radius = 3
    cells = Shape.disc(x, y, radius)

    {heights, removed} =
      Enum.reduce(cells, {state.heights, 0}, fn {cx, cy}, {heights, removed} ->
        index = cy * @width + cx
        current = elem(heights, index)
        falloff = 1.0 - distance(cx, cy, x, y) / (radius + 1)
        remove = round(40.0 * pressure * max(0.2, falloff))
        new = max(0, current - remove)

        if new < current,
          do: {put_elem(heights, index, new), removed + (current - new)},
          else: {heights, removed}
      end)

    if removed == 0 do
      state
    else
      %{
        state
        | heights: heights,
          clay: min(100.0, state.clay + removed / @max_height * 0.25),
          rev: state.rev + 1,
          result: nil
      }
    end
  end

  defp stroke(state, :paddle, x, y, pressure) do
    cells = Shape.disc(x, y, 5)
    average = round(mean(state, cells) * (1.0 - 0.5 * pressure) + 120 * 0.5 * pressure)

    heights =
      Enum.reduce(cells, state.heights, fn {cx, cy}, heights ->
        if area?(state, cx, cy) do
          index = cy * @width + cx
          put_elem(heights, index, round(elem(heights, index) * 0.35 + average * 0.65))
        else
          heights
        end
      end)

    %{state | heights: heights, rev: state.rev + 1, result: nil}
  end

  defp stroke(state, :sponge, x, y, _pressure) do
    cells = Shape.disc(x, y, 5)

    heights =
      Enum.reduce(cells, state.heights, fn {cx, cy}, heights ->
        if area?(state, cx, cy) do
          index = cy * @width + cx
          neighbours = Shape.disc(cx, cy, 1)
          average = round(mean(%{state | heights: heights}, neighbours))
          put_elem(heights, index, round(elem(heights, index) * 0.4 + average * 0.6))
        else
          heights
        end
      end)

    %{state | heights: heights, rev: state.rev + 1, result: nil}
  end

  defp stroke(state, :wire, x, y, _pressure) do
    cells = Shape.disc(x, y, 2)
    fresh = Enum.reject(cells, &MapSet.member?(state.wire, &1))

    if fresh == [] do
      state
    else
      %{
        state
        | wire: MapSet.union(state.wire, MapSet.new(fresh)),
          rev: state.rev + 1,
          result: nil
      }
    end
  end

  defp stroke(state, _tool, _x, _y, _pressure), do: state

  defp area?(%{puzzle: %{area: area}}, x, y), do: MapSet.member?(area, {x, y})

  defp area?(_state, _x, _y), do: false

  defp distance(x1, y1, x2, y2), do: :math.sqrt((x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2))

  @doc "Let the clay dry for `dt` seconds."
  def step(state, dt) do
    wet = max(0.0, state.wet - dt * 2.0)
    %{state | wet: wet}
  end

  @doc "Run the puzzle's tests, keeping the result on the mending."
  def check(state), do: %{state | result: Check.run(state)}

  @doc "The tests, without changing the mending."
  def passed?(state), do: Check.run(state).ok?

  @doc "Finish the mending if it passes."
  def finish(%{result: %{ok?: true}} = state), do: %{state | done?: true}
  def finish(state), do: state

  @doc "The puzzle this mending is for."
  def puzzle(%{puzzle: puzzle}), do: puzzle

  @doc "Every tool with its label and shortcut."
  def tool_rows do
    [
      {:thumb, "THUMB", "1", "press clay into place"},
      {:pin, "PIN", "2", "carve clay away"},
      {:paddle, "PADDLE", "3", "flatten and widen"},
      {:sponge, "SPONGE", "4", "smooth the surface"},
      {:wire, "WIRE", "5", "add an armature"},
      {:water, "WATER", "6", "wet the clay"},
      {:heat, "HEAT", "7", "fire the clay"}
    ]
  end

  @doc "A short description of the material, for the hud."
  def material(%{wet: wet, fired: fired}) do
    cond do
      fired >= 68 -> :fired
      fired >= 30 -> :hardening
      wet >= 55 -> :wet
      wet >= 25 -> :leather
      true -> :dry
    end
  end
end
