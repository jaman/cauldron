defmodule Crossing.GameTest do
  use ExUnit.Case, async: true

  alias Crossing.{Game, Lanes}

  defp game, do: Game.init([])

  defp hop(game, action), do: Game.handle_input(game, :player, %{action: action})

  test "a hop moves the frog a tile" do
    game = hop(game(), :up)
    assert game.frog == {7.0, 11}
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

  test "the last life ends the game" do
    game = %{game() | lives: 1, frog: {0.0, 2}}
    lane = Enum.find(game.lanes, &(&1.row == 2))
    x = Enum.find(0..14, fn x -> not Lanes.covers?(lane, x) end)
    game = %{game | frog: {x / 1, 2}}
    game = Game.step(game, 1 / 60)
    assert game.status == :over
  end
end
