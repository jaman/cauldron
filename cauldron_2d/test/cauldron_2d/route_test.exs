defmodule Cauldron2D.RouteTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Route

  @size {8, 8}

  defp open?({x, y}), do: x >= 0 and y >= 0 and x < 8 and y < 8 and not (x == 3 and y < 6)

  describe "to/4" do
    test "gives the tile centres to walk through, the one under your feet left out" do
      assert {:ok, [{1.5, 0.5}, {2.5, 0.5}]} =
               Route.to(&open?/1, {0.5, 0.5}, {2.5, 0.5}, size: @size)
    end

    test "starts from the tile a fractional point falls in" do
      assert {:ok, one} = Route.to(&open?/1, {0.1, 0.9}, {2.4, 0.2}, size: @size)
      assert {:ok, other} = Route.to(&open?/1, {0.5, 0.5}, {2.5, 0.5}, size: @size)

      assert Enum.drop(one, -1) == Enum.drop(other, -1)
    end

    test "the last step is where it was sent, not the middle of the tile" do
      assert {:ok, route} = Route.to(&open?/1, {0.5, 0.5}, {2.2, 0.9}, size: @size)

      assert List.last(route) == {2.2, 0.9}
      assert Route.goal(route) == {2.2, 0.9}
    end

    test "standing already where it was sent is a route with nothing in it" do
      assert {:ok, []} = Route.to(&open?/1, {4.8, 4.8}, {4.8, 4.8}, size: @size)
    end

    test "standing elsewhere in the same tile is the one step across it" do
      assert {:ok, [{4.8, 4.8}]} = Route.to(&open?/1, {4.2, 4.2}, {4.8, 4.8}, size: @size)
    end

    test "goes around a wall" do
      assert {:ok, route} = Route.to(&open?/1, {0.5, 0.5}, {5.5, 0.5}, size: @size)
      assert Enum.any?(route, fn {_x, y} -> y >= 6 end)
    end

    test "no way is none" do
      blocked = fn {x, y} -> x >= 0 and y >= 0 and x < 8 and y < 8 and x != 3 end

      assert Route.to(blocked, {0.5, 0.5}, {5.5, 0.5}, size: @size) == :none
    end
  end

  describe "advance/3" do
    test "moves towards the next point without passing it" do
      {at, left} = Route.advance([{4.0, 0.0}], {0.0, 0.0}, 1.0)

      assert at == {1.0, 0.0}
      assert left == [{4.0, 0.0}]
    end

    test "drops a point it reaches" do
      {at, left} = Route.advance([{1.0, 0.0}, {2.0, 0.0}], {0.0, 0.0}, 1.0)

      assert at == {1.0, 0.0}
      assert left == [{2.0, 0.0}]
    end

    test "passes through as many points as the step covers" do
      route = [{1.0, 0.0}, {2.0, 0.0}, {3.0, 0.0}, {4.0, 0.0}]
      {{x, _y}, left} = Route.advance(route, {0.0, 0.0}, 2.5)

      assert_in_delta x, 2.5, 1.0e-9
      assert left == [{3.0, 0.0}, {4.0, 0.0}]
    end

    test "arriving leaves nothing" do
      assert {arrived, []} = Route.advance([{1.0, 0.0}, {2.0, 0.0}], {0.0, 0.0}, 9.0)
      assert arrived == {2.0, 0.0}
    end

    test "an empty route and a step of nothing both stay put" do
      assert Route.advance([], {1.0, 2.0}, 5.0) == {{1.0, 2.0}, []}
      assert Route.advance([{9.0, 9.0}], {1.0, 2.0}, 0) == {{1.0, 2.0}, [{9.0, 9.0}]}
    end
  end

  describe "heading/2, arrived?/1 and goal/1" do
    test "the heading points at the next place to be" do
      assert_in_delta Route.heading([{1.0, 0.0}], {0.0, 0.0}), 0.0, 1.0e-9
      assert_in_delta Route.heading([{0.0, 1.0}], {0.0, 0.0}), :math.pi() / 2, 1.0e-9
      assert Route.heading([], {0.0, 0.0}) == nil
    end

    test "a route with nothing left has arrived and has no goal" do
      assert Route.arrived?([])
      refute Route.arrived?([{1.0, 1.0}])
      assert Route.goal([]) == nil
      assert Route.goal([{1.0, 1.0}, {2.0, 2.0}]) == {2.0, 2.0}
    end
  end
end
