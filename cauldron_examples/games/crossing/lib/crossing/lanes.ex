defmodule Crossing.Lanes do
  @moduledoc """
  A lane of the board: carts on the road, logs on the water.

  A lane knows its row, which way it runs, how fast, how long its carts or logs are, and
  how many of them there are. Its `phase` is the distance the lane has run, which is the
  only thing `step/2` changes. Where the carts or logs are is worked out from the phase
  when someone asks, so the lane is a value like the game itself.
  """

  defstruct [:row, :dir, :speed, :length, :count, :gap, :phase, :kind, :cycle]

  @type t :: %__MODULE__{
          row: non_neg_integer(),
          dir: 1 | -1,
          speed: float(),
          length: pos_integer(),
          count: pos_integer(),
          gap: non_neg_integer(),
          phase: float(),
          kind: atom(),
          cycle: {float(), float()} | nil
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
          float(),
          keyword()
        ) :: t()
  def lane(row, dir, speed, length, count, gap, phase \\ 0.0, opts \\ []) do
    %__MODULE__{
      row: row,
      dir: dir,
      speed: speed,
      length: length,
      count: count,
      gap: gap,
      phase: phase,
      kind: Keyword.get(opts, :kind, :log),
      cycle: Keyword.get(opts, :cycle)
    }
  end

  @doc """
  Whether what the lane carries can be stood on at `time` seconds into the game.

  Logs always can. Turtles carry a `{up, down}` cycle and are under the water for the
  second part of it; a frog standing on one when it goes down is in the water.
  """
  @spec surfaced?(t(), float()) :: boolean()
  def surfaced?(%__MODULE__{cycle: nil}, _time), do: true

  def surfaced?(%__MODULE__{cycle: {up, down}}, time) do
    :math.fmod(time, up + down) < up
  end

  @doc "The lane after `dt` seconds."
  @spec step(t(), float()) :: t()
  def step(%__MODULE__{} = lane, dt) do
    %{lane | phase: wrap(lane.phase + lane.dir * lane.speed * dt, lane)}
  end

  @doc """
  The left edge of each cart or log, in tiles.

  Positions run from `-length` to `period - length`, so an item can be drawn sliding off
  either edge of the board rather than jumping from one side to the other when it wraps.
  """
  @spec items(t()) :: [float()]
  def items(%__MODULE__{} = lane) do
    for index <- 0..(lane.count - 1) do
      wrap(index * spacing(lane) + lane.phase, lane) - lane.length
    end
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

  @doc """
  How long a gap takes to pass a fixed point, in seconds — the time a frog has to step
  into the lane. The shorter it is, the harder the lane.
  """
  @spec gap_time(t()) :: float()
  def gap_time(%__MODULE__{gap: gap, speed: speed}), do: gap / speed

  @doc "How wide the lane's beat is, in tiles: every item and every gap."
  @spec period(t()) :: float()
  def period(%__MODULE__{} = lane), do: spacing(lane) * lane.count

  defp wrap(value, lane) do
    period = period(lane)
    wrapped = :math.fmod(value, period)
    if wrapped < 0, do: wrapped + period, else: wrapped
  end
end
