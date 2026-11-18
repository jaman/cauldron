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
  @height 15
  @start {7.0, 12}
  @home 0
  @water 2..5
  @road 7..10
  @lives 3

  defstruct frog: @start,
            lanes: [],
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

  @impl true
  def init(_opts) do
    lanes =
      [
        Lanes.lane(2, 1, 1.4, 3, 4, 0.0),
        Lanes.lane(3, -1, 1.8, 3, 4, 5.0),
        Lanes.lane(4, 1, 1.1, 4, 3, 9.0),
        Lanes.lane(5, -1, 2.1, 3, 4, 2.0),
        Lanes.lane(7, 1, 2.8, 2, 5, 0.0),
        Lanes.lane(8, -1, 3.6, 2, 5, 7.0),
        Lanes.lane(9, 1, 2.2, 2, 5, 3.0),
        Lanes.lane(10, -1, 4.2, 2, 5, 11.0)
      ]

    %__MODULE__{lanes: lanes}
  end

  @impl true
  def join(%__MODULE__{} = game, _id, _props), do: {:ok, game}

  @impl true
  def leave(%__MODULE__{} = game, _id), do: game

  @impl true
  def handle_input(%__MODULE__{status: :playing} = game, _id, %{action: action})
      when action in [:up, :down, :left, :right] do
    hop(game, action)
  end

  def handle_input(%__MODULE__{} = game, _id, _input), do: game

  @impl true
  def step(%__MODULE__{status: :playing} = game, dt) do
    lanes = Enum.map(game.lanes, &Lanes.step(&1, dt))
    game = %{game | lanes: lanes, elapsed: game.elapsed + dt}

    if elem(game.frog, 1) == @home do
      home(game)
    else
      cross(game, dt)
    end
  end

  def step(%__MODULE__{} = game, _dt), do: game

  @impl true
  def view(%__MODULE__{} = game, _id) do
    %{
      frog: game.frog,
      lanes: game.lanes,
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

  defp ride(%__MODULE__{} = game, lane, x, y, dt) do
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

  # --- the score, and the lives ---------------------------------------------------

  defp home(%__MODULE__{} = game) do
    %{game | score: game.score + 1, frog: @start}
  end

  defp lose(%__MODULE__{lives: lives} = game, _why) when lives <= 1 do
    %{game | lives: 0, status: :over, frog: @start}
  end

  defp lose(%__MODULE__{lives: lives} = game, _why),
    do: %{game | lives: lives - 1, frog: @start}
end
