defmodule Cauldron.OpenWorldTest do
  use ExUnit.Case, async: true

  alias Cauldron.OpenWorld.{Cell, Edge, Panel, Window}
  alias Cauldron.OpenWorld.Map, as: World

  defp sloped(address, role \\ :simulated) do
    Cell.sampled(address, 8, 64.0, fn {x, y} -> 2.0 * x + 3.0 * y end, role: role)
  end

  test "the ground between samples lies on the sampled plane, in cells either side of zero" do
    map = World.new(cell_size: 64.0, samples: 8) |> World.put(sloped({0, 0})) |> World.put(sloped({-1, -1}))

    assert_in_delta World.height(map, {10.3, 20.7}), 82.7, 1.0e-3
    assert_in_delta World.height(map, {-0.5, -0.5}), -2.5, 1.0e-3
    assert World.address(map, {-0.5, -0.5}) == {-1, -1}
    assert World.height(map, {70.0, 10.0}) == nil
    assert World.slope(map, {10.3, 20.7}) == {2.0, 3.0}
  end

  test "a grid square is two triangles split from its x corner to its y corner" do
    heights = for height <- [0.0, 0.0, 0.0, 4.0], into: <<>>, do: <<height::little-float-32>>
    map = World.new(cell_size: 1.0, samples: 1) |> World.put(%Cell{address: {0, 0}, heights: heights})

    assert World.height(map, {0.25, 0.25}) == 0.0
    assert World.height(map, {0.75, 0.75}) == 2.0
  end

  test "a mover slides along the line where simulated cells end" do
    map =
      World.new(cell_size: 64.0, samples: 8, edges: [{Edge.Scenery, margin: 1.0}])
      |> World.put(sloped({0, 0}))
      |> World.put(sloped({1, 0}, :shown))

    assert World.travel(map, {60.0, 10.0}, {70.0, 20.0}) == {{60.0, 20.0}, [Edge.Scenery]}
    assert World.travel(map, {30.0, 10.0}, {32.0, 12.0}) == {{32.0, 12.0}, []}
    assert World.role(map, {70.0, 20.0}) == :shown
  end

  test "a mover stops a margin in front of a panel, from either side" do
    panel = %Panel{from: {0.0, 10.0}, to: {100.0, 10.0}, height: 50.0, picture: :hills}
    map = World.new(cell_size: 64.0, samples: 8, edges: [{Edge.Backdrop, margin: 1.0}], panels: [panel])

    assert World.travel(map, {50.0, 5.0}, {50.0, 12.0}) == {{50.0, 9.0}, [Edge.Backdrop]}
    assert World.travel(map, {50.0, 15.0}, {50.0, 8.0}) == {{50.0, 11.0}, [Edge.Backdrop]}
    assert World.travel(map, {150.0, 5.0}, {150.0, 12.0}) == {{150.0, 12.0}, []}
  end

  test "the window holds the cells within reach and lets go only past the keep distance" do
    map = World.new(cell_size: 10.0, samples: 2)

    assert Window.wanted(map, [{5.0, 5.0}], 6.0) ==
             MapSet.new([{0, 0}, {1, 0}, {-1, 0}, {0, 1}, {0, -1}])

    held = MapSet.new([{0, 0}, {3, 0}, {9, 9}])
    step = Window.step(held, map, [{5.0, 5.0}], load: 6.0, keep: 30.0)

    assert Enum.sort(step.load) == [{-1, 0}, {0, -1}, {0, 1}, {1, 0}]
    assert step.drop == [{9, 9}]
    assert Window.levels(map, [{0, 0}, {3, 0}], [{5.0, 5.0}], [10.0, 40.0]) == %{{0, 0} => 0, {3, 0} => 1}
  end
end
