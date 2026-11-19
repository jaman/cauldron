defmodule Crossing.GameTest do
  use ExUnit.Case, async: true

  alias Crossing.{Game, Lanes}

  defp game, do: Game.init([])

  defp hop(game, action) do
    game = Game.handle_input(game, :player, %{held: MapSet.new([action])})
    Game.handle_input(game, :player, %{held: MapSet.new()})
  end

  test "a hop moves the frog a tile" do
    game = hop(game(), :up)
    assert game.frog == {7.0, 11}
  end

  test "holding a direction does not run the frog across the board" do
    game = Game.handle_input(game(), :player, %{held: MapSet.new([:up])})
    assert game.frog == {7.0, 11}

    game = Game.handle_input(game, :player, %{held: MapSet.new([:up])})
    assert game.frog == {7.0, 11}
  end

  test "a direction pressed again hops again" do
    game = hop(game(), :up)
    game = hop(game, :up)
    assert game.frog == {7.0, 10}
  end

  test "the frog stays on the board" do
    game = %{game() | frog: {0.0, 12}}
    assert hop(game, :left).frog == {0.0, 12}
  end

  test "the far bank scores and sends the frog home" do
    game = %{game() | frog: {7.0, 1}}
    game = hop(game, :up)
    assert game.frog == {7.0, 0}
    game = Game.step(game, 1 / 60)
    assert game.score == 1
    assert game.frog == Game.start()
  end

  test "a cart squashes the frog" do
    game = game()
    lane = Enum.find(game.lanes, &(&1.row == 7))
    x = Enum.find(0..14, fn x -> Lanes.covers?(lane, x) end)
    game = %{game | frog: {x / 1, 7}, lives: 3}
    game = Game.step(game, 1 / 60)
    assert game.lives == 2
    assert game.frog == Game.start()
  end

  test "a log carries the frog" do
    game = game()
    lane = Enum.find(game.lanes, &(&1.row == 1))
    x = Enum.find(0..14, fn x -> Lanes.covers?(lane, x) end)
    game = %{game | frog: {x / 1, 1}}
    carried = Game.step(game, 1 / 60)
    assert carried.frog |> elem(0) > x
  end

  test "every row between the banks is a lane" do
    rows = game().lanes |> Enum.map(& &1.row)
    assert rows == [1, 2, 3, 4, 5, 7, 8, 9, 10, 11]
  end

  test "an item's left edge can be off the board, so it slides in and out" do
    lane = Lanes.lane(8, -1, 3.0, 2, 5, 3)

    assert Enum.min(Lanes.items(lane)) < 0
    assert Enum.max(Lanes.items(lane)) > 15
  end

  test "each lane runs at its own pace and spacing" do
    spacings = game().lanes |> Enum.map(&Lanes.spacing/1) |> Enum.uniq()
    speeds = game().lanes |> Enum.map(& &1.speed) |> Enum.uniq()

    assert length(spacings) > 3
    assert length(speeds) > 3
  end

  test "water without a log drowns the frog" do
    game = game()
    lane = Enum.find(game.lanes, &(&1.row == 2))
    x = Enum.find(0..14, fn x -> not Lanes.covers?(lane, x) end)
    game = %{game | frog: {x / 1, 2}}
    game = Game.step(game, 1 / 60)
    assert game.lives == 2
    assert game.frog == Game.start()
  end

  test "a turtle that has gone under drops the frog" do
    game = game()
    lane = Enum.find(game.lanes, &(&1.cycle != nil))
    x = Enum.find(0..14, fn x -> Lanes.covers?(lane, x) end)

    # the diving lane is up for six seconds, then down for three
    game = %{game | frog: {x / 1, lane.row}, elapsed: 7.0}
    game = Game.step(game, 1 / 60)

    assert game.lives == 2
    assert game.frog == Game.start()
  end

  test "a turtle that is up carries the frog" do
    game = game()
    lane = Enum.find(game.lanes, &(&1.cycle != nil))
    x = Enum.find(0..14, fn x -> Lanes.covers?(lane, x) end)

    game = %{game | frog: {x / 1, lane.row}, elapsed: 1.0}
    carried = Game.step(game, 1 / 60)

    assert carried.lives == 3
    assert carried.frog |> elem(0) > x
  end

  test "the snake bites while it is crossing" do
    game = game()
    game = %{game | frog: {2.0, 6}, snake: %{x: 2.0}, elapsed: 1.0}
    game = Game.step(game, 1 / 60)

    assert game.lives == 2
  end

  test "the snake is away for part of the time" do
    game = game()
    game = %{game | frog: {2.0, 6}, snake: %{x: 2.0}, elapsed: 12.0}
    game = Game.step(game, 1 / 60)

    assert game.lives == 3
  end

  test "filling the five slots clears the level and makes it harder" do
    game =
      Enum.reduce([1.0, 4.0, 7.0, 10.0, 13.0], game(), fn x, game ->
        game = %{game | frog: {x, 0}}
        Game.step(game, 1 / 60)
      end)

    assert game.level == 2
    assert game.score == 5
    assert MapSet.size(game.homes) == 0

    assert Enum.max(Enum.map(game.lanes, & &1.speed)) >
             Enum.max(Enum.map(game().lanes, & &1.speed))
  end

  test "landing on a filled slot costs a life" do
    game = %{game() | frog: {7.0, 0}, homes: MapSet.new([7])}
    game = Game.step(game, 1 / 60)

    assert game.lives == 2
  end

  test "the snake comes more often and stays longer as levels rise" do
    assert Game.snake_period(3) < Game.snake_period(1)
    assert Game.snake_crossing(3) > Game.snake_crossing(1)
  end

  test "the turtles spend less time up as levels rise" do
    {up_one, down_one} = Enum.find(game().lanes, &(&1.cycle != nil)).cycle
    {up_four, down_four} = Enum.find(Game.lanes(4), &(&1.cycle != nil)).cycle

    assert up_four < up_one
    assert down_four > down_one
  end

  test "the last life ends the game" do
    game = %{game() | lives: 1, frog: {0.0, 2}}
    lane = Enum.find(game.lanes, &(&1.row == 2))
    x = Enum.find(0..14, fn x -> not Lanes.covers?(lane, x) end)
    game = %{game | frog: {x / 1, 2}}
    game = Game.step(game, 1 / 60)
    assert game.status == :over
  end
end
