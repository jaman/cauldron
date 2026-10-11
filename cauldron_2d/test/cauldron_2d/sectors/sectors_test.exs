defmodule Cauldron2D.SectorsTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Sectors.{Blockmap, Move, Sight}
  alias Cauldron2D.Sectors.Map, as: SectorMap
  alias Cauldron2D.Test.TwoRooms

  setup_all do
    map = TwoRooms.map()
    {:ok, map: map, blockmap: Blockmap.build(map)}
  end

  defp world(map, blockmap, door),
    do: %{map: map, blockmap: blockmap, sectors: TwoRooms.door(map, door)}

  defp body(x, y), do: %{x: x, y: y, z: 0.0, radius: 16.0, height: 56.0}

  test "the built BSP finds every point's sector", %{map: map} do
    rooms = [{0, {1, 255}, {1, 255}}, {1, {257, 287}, {97, 159}}, {2, {289, 543}, {1, 255}}]

    for {sector, {x0, x1}, {y0, y1}} <- rooms, x <- x0..x1//23, y <- y0..y1//17 do
      assert SectorMap.sector_at(map, {x * 1.0, y * 1.0}) == sector
    end
  end

  test "a wall stops a body, an open door lets it through, a shut one does not", %{
    map: map,
    blockmap: blockmap
  } do
    open = world(map, blockmap, {0.0, 128.0})
    shut = world(map, blockmap, {0.0, 0.0})

    assert {:blocked, %{reason: :line}} = Move.try(open, body(100.0, 100.0), {10.0, 100.0})
    assert {:ok, %{sector: 2}} = Move.try(open, body(300.0, 128.0), {310.0, 128.0})
    assert {:blocked, %{reason: reason}} = Move.try(shut, body(250.0, 128.0), {262.0, 128.0})
    assert reason in [:tight, :ceiling]
  end

  test "a body climbs a low step and not a high one", %{map: map, blockmap: blockmap} do
    assert {:ok, %{floor: 20.0}} =
             Move.try(world(map, blockmap, {20.0, 128.0}), body(250.0, 128.0), {262.0, 128.0})

    assert {:blocked, %{reason: :step}} =
             Move.try(world(map, blockmap, {30.0, 128.0}), body(250.0, 128.0), {262.0, 128.0})
  end

  test "running into a wall at an angle slides along it", %{map: map, blockmap: blockmap} do
    {moved, _momentum} =
      Move.slide(world(map, blockmap, {0.0, 128.0}), body(100.0, 230.0), {10.0, 20.0})

    assert moved.x > 105.0
    assert moved.y <= 240.0
  end

  test "sight passes an open door and not a shut one", %{map: map, blockmap: blockmap} do
    target = %{x: 400.0, y: 128.0, z: 0.0, height: 56.0}

    assert Sight.visible?(world(map, blockmap, {0.0, 128.0}), {100.0, 128.0, 41.0}, target)
    refute Sight.visible?(world(map, blockmap, {0.0, 0.0}), {100.0, 128.0, 41.0}, target)
  end
end
