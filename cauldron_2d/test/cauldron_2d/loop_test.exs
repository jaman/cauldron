defmodule Cauldron2D.LoopTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Loop

  test "the first frame establishes a baseline and owes nothing" do
    {steps, loop} = Loop.advance(Loop.new(60), 10_000)

    assert steps == 0
    assert loop.last == 10_000
  end

  test "a frame runs the whole steps that have come due" do
    loop = Loop.new(100) |> elem_loop(0)

    assert {1, loop} = Loop.advance(loop, 10)
    assert {2, loop} = Loop.advance(loop, 30)
    assert {0, _loop} = Loop.advance(loop, 35)
  end

  test "fractions of a step are carried, not dropped" do
    loop = Loop.new(100) |> elem_loop(0)

    assert {0, loop} = Loop.advance(loop, 7)
    assert {1, loop} = Loop.advance(loop, 14)
    assert {1, _loop} = Loop.advance(loop, 21)
  end

  test "a long stall is dropped rather than replayed" do
    loop = Loop.new(60, max_steps: 5) |> elem_loop(0)

    assert {5, loop} = Loop.advance(loop, 60_000)
    assert loop.accumulator == 0.0
    assert {1, _loop} = Loop.advance(loop, 60_017)
  end

  test "time going backwards does not produce negative steps" do
    loop = Loop.new(60) |> elem_loop(1000)

    assert {0, _loop} = Loop.advance(loop, 500)
  end

  test "dt is constant, which is what makes a simulation reproducible" do
    loop = Loop.new(50)

    assert Loop.dt(loop) == 0.02
    assert {_steps, advanced} = Loop.advance(loop, 0)
    assert Loop.dt(advanced) == Loop.dt(loop)
  end

  test "wait is the time left until the next step falls due, never negative" do
    loop = Loop.new(50)

    assert Loop.wait(loop, 0) == 0

    started = elem_loop(loop, 1000)
    assert Loop.wait(started, 1000) == 20
    assert Loop.wait(started, 1013) == 7
    assert Loop.wait(started, 1045) == 0

    {1, advanced} = Loop.advance(started, 1030)
    assert Loop.wait(advanced, 1030) == 10
  end

  defp elem_loop(loop, at) do
    {0, started} = Loop.advance(loop, at)
    started
  end
end
