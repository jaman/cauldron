defmodule Crossing.Lanes do
  @moduledoc """
  A lane of the board: carts on the road, logs on the water.

  A lane knows its row, which way it runs, how fast, how long its carts or logs are, and
  how many of them there are. Its `phase` is the distance the lane has run, which is the
  only thing `step/2` changes. Where the carts or logs are is worked out from the phase
  when someone asks, so the lane is a value like the game itself.
  """

  defstruct [:row, :dir, :speed, :length, :count, :gap, :phase]

  @type t :: %__MODULE__{
          row: non_neg_integer(),
          dir: 1 | -1,
          speed: float(),
          length: pos_integer(),
          count: pos_integer(),
          gap: non_neg_integer(),
          phase: float()
        }

  @doc """
  A lane at `row`, running `dir` at `speed` tiles a second: `count` items, each `length`
  tiles long, with `gap` tiles of clear road or water between them.
  """
  @spec lane(
          non_neg_integer(),
          1 | -1,
          float(),
          pos_integer(),
          pos_integer(),
          non_neg_integer(),
          float()
        ) :: t()
  def lane(row, dir, speed, length, count, gap, phase \\ 0.0) do
    %__MODULE__{
      row: row,
      dir: dir,
      speed: speed,
      length: length,
      count: count,
      gap: gap,
      phase: phase
    }
  end

  @doc "The lane after `dt` seconds."
  @spec step(t(), float()) :: t()
  def step(%__MODULE__{} = lane, dt) do
    %{lane | phase: wrap(lane.phase + lane.dir * lane.speed * dt, lane)}
  end

  @doc "The left edge of each cart or log, in tiles."
  @spec items(t()) :: [float()]
  def items(%__MODULE__{} = lane) do
    for index <- 0..(lane.count - 1), do: wrap(index * spacing(lane) + lane.phase, lane)
  end

  @doc "Whether a cart or log covers tile `x` of its row."
  @spec covers?(t(), integer()) :: boolean()
  def covers?(%__MODULE__{} = lane, x) do
    centre = x + 0.5

    Enum.any?(items(lane), fn edge -> centre >= edge and centre < edge + lane.length end)
  end

  @doc "The distance from one item's left edge to the next, in tiles."
  @spec spacing(t()) :: float()
  def spacing(%__MODULE__{length: length, gap: gap}), do: (length + gap) * 1.0

  @doc "How wide the lane's beat is, in tiles: every item and every gap."
  @spec period(t()) :: float()
  def period(%__MODULE__{} = lane), do: spacing(lane) * lane.count

  defp wrap(value, lane) do
    period = period(lane)
    wrapped = :math.fmod(value, period)
    if wrapped < 0, do: wrapped + period, else: wrapped
  end
end
