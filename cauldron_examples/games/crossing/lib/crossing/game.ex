defmodule Crossing.Game do
  @moduledoc """
  A frog crossing a road and a river: the board, the lanes and the rules.

  The board is fifteen tiles square. The frog starts on the grass at the foot; the road
  runs across the middle, the water above it, and the bank at the top is the far side.
  A hop is one tile and one press, and the lanes do not care who is standing in them: a
  cart squashes the frog, a log carries it, and water without a log takes it under.
  """

  @behaviour Cauldron.Game

  alias Crossing.Lanes

  @width 15
  @height 13
  @start {7.0, 12}
  @home 0
  @slots [1, 5, 9, 13]
  @water 1..5
  @road 7..11
  @lives 3

  defstruct frog: @start,
            held: MapSet.new(),
            lanes: [],
            snake: %{x: -1.5},
            homes: MapSet.new(),
            level: 1,
            lives: @lives,
            score: 0,
            elapsed: 0.0,
            status: :playing

  @type t :: %__MODULE__{}

  @doc "The width and height of the board, in tiles."
  @spec size() :: {pos_integer(), pos_integer()}
  def size, do: {@width, @height}

  @doc "Where the frog starts."
  @spec start() :: {float(), non_neg_integer()}
  def start, do: @start

  @doc "The columns of the far bank's homes."
  @spec slots() :: [non_neg_integer()]
  def slots, do: @slots

  @impl true
  def init(_opts), do: %__MODULE__{lanes: lanes(1)}

  # Every level runs the same board a little harder: the traffic and the river speed up,
  # the turtles spend less time up and more under, and the snake comes more often and
  # stays longer.
  @doc false
  def lanes(level) do
    speed = fn base -> base * (1.0 + 0.07 * (level - 1)) end
    up = max(3.0, 6.0 - 0.5 * (level - 1))
    down = min(6.0, 3.0 + 0.45 * (level - 1))

    [
      Lanes.lane(1, 1, speed.(1.2), 4, 2, 5, 0.0, kind: :log),
      Lanes.lane(2, -1, speed.(1.4), 2, 3, 4, 2.0, kind: :turtle, cycle: nil),
      Lanes.lane(3, 1, speed.(1.5), 3, 2, 5, 5.0, kind: :log),
      Lanes.lane(4, -1, speed.(1.8), 3, 2, 4, 1.0, kind: :log),
      Lanes.lane(5, 1, speed.(1.3), 3, 2, 5, 7.0, kind: :turtle, cycle: {up, down}),
      Lanes.lane(7, 1, speed.(2.6), 2, 3, 5, 0.0, kind: :car),
      Lanes.lane(8, -1, speed.(2.2), 3, 3, 6, 4.0, kind: :truck),
      Lanes.lane(9, 1, speed.(3.0), 2, 4, 5, 1.0, kind: :car),
      Lanes.lane(10, -1, speed.(1.8), 4, 2, 7, 6.0, kind: :bus),
      Lanes.lane(11, 1, speed.(2.4), 3, 3, 5, 3.0, kind: :truck)
    ]
  end

  @doc """
  The time a gap in the hardest lane gives a frog to step into it, in seconds, at `level`.
  Below about a second and a half a lane cannot be crossed on reaction alone.
  """
  @spec tightest_gap(pos_integer()) :: float()
  def tightest_gap(level), do: level |> lanes() |> Enum.map(&Lanes.gap_time/1) |> Enum.min()

  @doc "How long the snake is away between crossings, in seconds."
  @spec snake_period(pos_integer()) :: float()
  def snake_period(level), do: max(8.0, 20.0 - 1.6 * (level - 1))

  @doc "How long the snake spends crossing the median, in seconds."
  @spec snake_crossing(pos_integer()) :: float()
  def snake_crossing(level), do: min(14.0, 8.0 + 0.7 * (level - 1))

  @impl true
  def join(%__MODULE__{} = game, _id, _props), do: {:ok, game}

  @impl true
  def leave(%__MODULE__{} = game, _id), do: game

  @impl true
  def handle_input(%__MODULE__{status: :playing} = game, _id, %{held: held}) do
    fresh = MapSet.difference(held, game.held)
    game = %{game | held: held}

    case pressed(fresh) do
      nil -> game
      action -> hop(game, action)
    end
  end

  def handle_input(%__MODULE__{} = game, _id, _input), do: game

  # One hop to a press: an action that is already held does nothing until it is released
  # and pressed again, so holding a key does not run the frog across the board.
  defp pressed(fresh), do: Enum.find([:up, :down, :left, :right], &MapSet.member?(fresh, &1))

  @impl true
  def step(%__MODULE__{status: :playing} = game, dt) do
    lanes = Enum.map(game.lanes, &Lanes.step(&1, dt))
    elapsed = game.elapsed + dt
    snake = snake(game.snake, elapsed, dt, game.level)
    game = %{game | lanes: lanes, elapsed: elapsed, snake: snake}

    cond do
      elem(game.frog, 1) == @home -> home(game)
      bitten?(game) -> lose(game, :bitten)
      true -> cross(game, dt)
    end
  end

  def step(%__MODULE__{} = game, _dt), do: game

  @impl true
  def view(%__MODULE__{} = game, _id) do
    %{
      frog: game.frog,
      lanes: game.lanes,
      snake: game.snake,
      level: game.level,
      homes: game.homes,
      lives: game.lives,
      score: game.score,
      status: game.status,
      elapsed: game.elapsed
    }
  end

  @impl true
  def drain_events(%__MODULE__{} = game), do: {[], game}

  # --- the frog's own moves -------------------------------------------------------

  defp hop(%__MODULE__{frog: {x, y}} = game, action) do
    {dx, dy} = direction(action)
    next = {x + dx, y + dy}

    if inside?(next), do: %{game | frog: next}, else: game
  end

  defp direction(:up), do: {0, -1}
  defp direction(:down), do: {0, 1}
  defp direction(:left), do: {-1, 0}
  defp direction(:right), do: {1, 0}

  defp inside?({x, y}),
    do: x >= 0 and x <= @width - 1 and y >= 0 and y <= @height - 1

  # --- what the lanes do to it ----------------------------------------------------

  defp cross(%__MODULE__{frog: {x, y}} = game, dt) do
    case lane_at(game, y) do
      nil ->
        game

      lane when y in @water ->
        ride(game, lane, x, y, dt)

      lane when y in @road ->
        if Lanes.covers?(lane, trunc(x)), do: lose(game, :squashed), else: game

      _lane ->
        game
    end
  end

  defp ride(%__MODULE__{} = game, lane, x, y, dt), do: ride_surfaced(game, lane, x, y, dt)

  defp ride_surfaced(%__MODULE__{} = game, lane, x, y, dt) do
    index = Lanes.item_at(lane, trunc(x))

    if index != nil and not Lanes.surfaced?(lane, index, game.elapsed) do
      lose(game, :drowned)
    else
      ride_on(game, lane, x, y, dt)
    end
  end

  defp ride_on(%__MODULE__{} = game, lane, x, y, dt) do
    if Lanes.covers?(lane, trunc(x)) do
      drifted = x + lane.dir * lane.speed * dt

      if drifted < -0.4 or drifted > @width - 0.6 do
        lose(game, :drowned)
      else
        %{game | frog: {drifted, y}}
      end
    else
      lose(game, :drowned)
    end
  end

  defp lane_at(%__MODULE__{lanes: lanes}, row), do: Enum.find(lanes, &(&1.row == row))

  # The snake comes and goes: it crosses the median for a few seconds, then is away.
  defp snake(%{x: x}, elapsed, dt, level) do
    if :math.fmod(elapsed, snake_period(level)) < snake_crossing(level) do
      next = x + (2.6 + 0.2 * (level - 1)) * dt
      %{x: if(next > @width + 1.5, do: -1.5, else: next)}
    else
      %{x: -1.5}
    end
  end

  defp bitten?(%__MODULE__{frog: {x, 6}, snake: %{x: sx}, elapsed: elapsed, level: level}) do
    :math.fmod(elapsed, snake_period(level)) < snake_crossing(level) and abs(x - sx) < 0.9
  end

  defp bitten?(%__MODULE__{}), do: false

  # --- the score, and the lives ---------------------------------------------------

  defp home(%__MODULE__{frog: {x, _y}} = game) do
    slot = Enum.min_by(@slots, &abs(&1 - x))

    if MapSet.member?(game.homes, slot) do
      lose(game, :taken)
    else
      game = %{game | homes: MapSet.put(game.homes, slot), score: game.score + 1, frog: @start}
      if MapSet.size(game.homes) == length(@slots), do: level_up(game), else: game
    end
  end

  defp level_up(%__MODULE__{level: level} = game) do
    %{game | level: level + 1, homes: MapSet.new(), lanes: lanes(level + 1)}
  end

  defp lose(%__MODULE__{lives: lives} = game, _why) when lives <= 1 do
    %{game | lives: 0, status: :over, frog: @start}
  end

  defp lose(%__MODULE__{lives: lives} = game, _why),
    do: %{game | lives: lives - 1, frog: @start}
end
