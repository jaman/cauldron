defmodule Megablast.Lane do
  @moduledoc """
  The lane the ship flies up: rock walls of changing thickness down both sides, open space
  between them, and gun turrets growing out of the rock.

  A lane is a value built by `new/1`; the game carries it and the client reads it from the
  view. `cells/1` gives the cell function `Cauldron2D.Camera` asks for. `edges/2` gives the
  first and last open column of a row, which is what the ship and the waves are kept
  between. `turret_of/2` gives the turret of a step, the same one every time.

  Every number is a setting of `new/1`, defaulting to `config :megablast, <key>, value` and
  then to the figure declared here.

  ## Settings

    * `:lane_width` — how many tiles wide the lane is, walls included
    * `:wall_least` — the thinnest a wall gets, in tiles
    * `:wall_most` — the thickest a wall gets, in tiles
    * `:wall_period` — how many rows a wall takes to go from one thickness to the next
    * `:turret_every` — how many rows apart turrets may grow
    * `:rock_kinds` — how many rock tiles the walls are built from
  """

  import Bitwise

  @mask 0xFFFFFFFFFFFFFFFF

  @defaults [
    lane_width: 26,
    wall_least: 2,
    wall_most: 7,
    wall_period: 14,
    turret_every: 11,
    rock_kinds: 4
  ]

  @type t :: %__MODULE__{
          width: pos_integer(),
          least: non_neg_integer(),
          most: pos_integer(),
          period: pos_integer(),
          turret_every: pos_integer(),
          rocks: pos_integer()
        }

  @type turret :: %{x: integer(), y: integer(), side: :left | :right}

  @enforce_keys [:width, :least, :most, :period, :turret_every, :rocks]
  defstruct [:width, :least, :most, :period, :turret_every, :rocks]

  @doc "A lane from `overrides`, over the configured defaults."
  @spec new(keyword()) :: t()
  def new(overrides \\ []) do
    %__MODULE__{
      width: setting(overrides, :lane_width),
      least: setting(overrides, :wall_least),
      most: setting(overrides, :wall_most),
      period: setting(overrides, :wall_period),
      turret_every: setting(overrides, :turret_every),
      rocks: setting(overrides, :rock_kinds)
    }
  end

  @doc "The settings and the figures they fall back to."
  @spec defaults() :: keyword()
  def defaults, do: @defaults

  @doc "How many tiles wide the lane is, walls included."
  @spec width(t()) :: pos_integer()
  def width(%__MODULE__{width: width}), do: width

  @doc "The middle of the lane, in tiles."
  @spec middle(t()) :: float()
  def middle(%__MODULE__{width: width}), do: (width - 1) / 2

  @doc "The cell function `Cauldron2D.Camera` reads the lane through."
  @spec cells(t()) :: ({integer(), integer()} -> Cauldron2D.Surface.cell())
  def cells(%__MODULE__{} = lane), do: fn at -> cell(lane, at) end

  @doc "The first and last open column of row `y`."
  @spec edges(t(), number()) :: {integer(), integer()}
  def edges(%__MODULE__{} = lane, y) do
    row = floor(y)
    {thickness(lane, row, 0), lane.width - 1 - thickness(lane, row, 1)}
  end

  @doc "The cell at a tile."
  @spec cell(t(), {integer(), integer()}) :: Cauldron2D.Surface.cell()
  def cell(%__MODULE__{} = lane, {x, y}) do
    {left, right} = edges(lane, y)

    if x < left or x > right, do: {rock(lane, x, y), [], nil}, else: :void
  end

  @doc "Whether a point is inside the open lane."
  @spec open?(t(), number(), number()) :: boolean()
  def open?(%__MODULE__{} = lane, x, y) do
    {left, right} = edges(lane, y)
    x >= left and x <= right
  end

  @doc "Which turret step a row falls in; steps count down the lane as the rows do."
  @spec turret_step(t(), number()) :: integer()
  def turret_step(%__MODULE__{turret_every: every}, y), do: Integer.floor_div(floor(y), every)

  @doc "The turret of a step, or `nil` where that step grew none."
  @spec turret_of(t(), integer()) :: turret() | nil
  def turret_of(%__MODULE__{} = lane, step) do
    if rem(scramble(step), 3) == 0, do: nil, else: turret(lane, step)
  end

  defp setting(overrides, key) do
    Keyword.get_lazy(overrides, key, fn ->
      Application.get_env(:megablast, key, Keyword.fetch!(@defaults, key))
    end)
  end

  defp turret(lane, step) do
    row = step * lane.turret_every
    {left, right} = edges(lane, row)

    if rem(scramble(step * 7 + 1), 2) == 0,
      do: %{x: left - 1, y: row, side: :left},
      else: %{x: right + 1, y: row, side: :right}
  end

  defp thickness(lane, row, side) do
    step = Integer.floor_div(row, lane.period)
    here = sample(lane, step, side)
    there = sample(lane, step + 1, side)
    share = Integer.mod(row, lane.period) / lane.period

    round(here + (there - here) * share)
  end

  defp sample(lane, step, side),
    do: lane.least + Integer.mod(scramble(step * 2 + side), lane.most - lane.least + 1)

  defp rock(lane, x, y),
    do: :"rock_#{Integer.mod(scramble(x * 31 + y * 17), lane.rocks)}"

  defp scramble(value) do
    mixed = band(value * 0x9E3779B97F4A7C15 + 0xBF58476D1CE4E5B9, @mask)

    mixed
    |> bxor(bsr(mixed, 29))
    |> band(@mask)
    |> bxor(bsr(mixed, 17))
    |> band(@mask)
  end
end
