defmodule Cauldron2D.TestDriverTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Test
  alias Cauldron2D.TestGames.Race

  test "a game is driven without a world: join, hold, tick, read views and events" do
    driver = Test.new(Race, game_opts: [seed: 3], hz: 10)
    assert Test.state(driver).seed == 3
    {:ok, driver} = Test.join(driver, :alice, %{speed: 2.0})
    {:ok, driver} = Test.join(driver, :bob, %{})
    assert {:error, :full} = Test.join(driver, :carol, %{})

    driver = driver |> Test.hold(:alice, [:forward]) |> Test.tick(5)
    assert_in_delta Test.view(driver, :alice).me, 1.0, 0.0001
    assert Test.view(driver, :bob).me == 0.0
    assert Test.tick_count(driver) == 5
    assert [{:beep, 0}] = Test.events(driver)

    driver = driver |> Test.hold(:alice, []) |> Test.tick(5)
    assert_in_delta Test.view(driver, :alice).me, 1.0, 0.0001
    assert [{:beep, 0}] = Test.events(driver)
    assert Test.events(Test.tick(driver, 1)) == [{:beep, 0}, {:beep, 10}]

    driver = Test.leave(driver, :bob)
    assert Test.view(driver, :alice).others == 0
  end

  test "until runs ticks up to a limit while a condition holds" do
    {:ok, driver} = Race |> Test.new(hz: 10) |> Test.join(:alice, %{speed: 1.0})
    driver = Test.hold(driver, :alice, [:forward])
    assert {:ok, reached} = Test.until(driver, fn d -> Test.view(d, :alice).me >= 0.5 end, 100)
    assert Test.tick_count(reached) == 5
    assert {:timeout, _} = Test.until(driver, fn d -> Test.view(d, :alice).me >= 50.0 end, 10)
  end
end
