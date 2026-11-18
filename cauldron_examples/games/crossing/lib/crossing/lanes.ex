defmodule Crossing.Lanes do
  @moduledoc """
  A lane of the board: carts on the road, logs on the water.

  A lane knows its row, which way it runs, how fast, how long its carts or logs are, and
  how many of them there are. Its `phase` is the distance the lane has run, which is the
  only thing `step/2` changes. Where the carts or logs are is worked out from the phase
  when someone asks, so the lane is a value like the game itself.
  """

  # The lane repeats every so many tiles; a cart that runs off one side comes back on the
  # other. Wider than the board, so there is a gap between the last cart and the first.
  @period 21

  defstruct [:row, :dir, :speed, :length, :count, :phase]

  @type t :: %__MODULE__{
          row: non_neg_integer(),
          dir: 1 | -1,
          speed: float(),
          length: pos_integer(),
          count: pos_integer(),
          phase: float()
        }

  @doc "A lane at `row`, running `dir` at `speed` tiles a second, of `count` items."
  @spec lane(non_neg_integer(), 1 | -1, float(), pos_integer(), pos_integer(), float()) :: t()
  def lane(row, dir, speed, length, count, phase \\ 0.0) do
    %__MODULE__{
      row: row,
      dir: dir,
      speed: speed,
      length: length,
      count: count,
      phase: phase
    }
  end

  @doc "The lane after `dt` seconds."
  @spec step(t(), float()) :: t()
  def step(%__MODULE__{} = lane, dt) do
    %{lane | phase: wrap(lane.phase + lane.dir * lane.speed * dt)}
  end

  @doc "The left edge of each cart or log, in tiles."
  @spec items(t()) :: [float()]
  def items(%__MODULE__{} = lane) do
    spacing = @period / lane.count
    for index <- 0..(lane.count - 1), do: wrap(index * spacing + lane.phase)
  end

  @doc "Whether a cart or log covers tile `x` of its row."
  @spec covers?(t(), integer()) :: boolean()
  def covers?(%__MODULE__{} = lane, x) do
    centre = x + 0.5

    Enum.any?(items(lane), fn edge -> centre >= edge and centre < edge + lane.length end)
  end

  @doc "How wide the lane's beat is, in tiles."
  @spec period() :: pos_integer()
  def period, do: @period

  defp wrap(value) do
    wrapped = :math.fmod(value, @period)
    if wrapped < 0, do: wrapped + @period, else: wrapped
  end
end
