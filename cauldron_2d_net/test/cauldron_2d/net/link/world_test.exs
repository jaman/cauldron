defmodule Cauldron2D.Net.Link.WorldTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Atlas
  alias Cauldron2D.Net.Link.World
  alias FrenchCurve.Raster

  setup_all do
    Atlas.new(:link_world_test, tile: 4)
    |> Atlas.put(:wall, Raster.new(4, 4))
    |> Atlas.put(:dot, Raster.new(4, 4))
    |> Atlas.install()

    :ok
  end

  @sheet %{
    arts: %{"wall" => 1, "dot" => 2},
    tile: 4,
    columns: 16,
    frames: [],
    anim: %{},
    url: "/a.png",
    void: {0, 0, 0}
  }
  @map %{width: 3, height: 2, tile: 4, wrap: true, rows: [[1, 0, 0], [0, 1, 0]]}
  @frame %{
    focus: {1.5, 1.0},
    movers: [{2, 1.0, 1.0}, {9, 0.0, 0.0}],
    labels: [{"me", 1.0, 1.5, "#ffff00", 1}],
    hud: [[{"fuel", "#ff0000"}, {"3", nil}]],
    over: nil
  }

  test "a wire view becomes a scene over the local atlas, with movers, labels and a wrapping cell" do
    scene = World.scene(%{wire: @frame, map: @map, sheet: @sheet, arena: "pit"}, :link_world_test)
    assert scene.focus == {1.5, 1.0}
    assert scene.bounds == {3, 2}
    assert scene.cell.({0, 0}) == {:wall, [], nil}
    assert scene.cell.({1, 0}) == :void
    assert scene.cell.({3, 0}) == {:wall, [], nil}
    assert scene.movers == [{:dot, {1.0, 1.0}}]
    assert scene.labels == [{"me", {1.0, 1.5}, {255, 255, 0}, scale: 1}]
    refute Map.has_key?(scene, :subject)

    assert World.scene(
             %{wire: Map.put(@frame, :subject, "bob"), map: @map, sheet: @sheet, arena: "pit"},
             :link_world_test
           ).subject == "bob"
  end

  test "the hud and the outcome read from the wire, and a closed connection says so" do
    view = %{wire: @frame, map: @map, sheet: @sheet, arena: "pit"}
    assert World.hud(view) == [[{"fuel", {255, 0, 0}}, {"3", nil}]]
    assert World.outcome(view) == nil

    assert World.outcome(%{view | wire: %{@frame | over: %{"title" => "Over", "lines" => ["a"]}}}) ==
             %{title: "Over", lines: ["a"]}

    closed = %{wire: nil, map: @map, sheet: @sheet, arena: "pit", closed: :normal}
    assert [[{"connection closed: :normal", _}]] = World.hud(closed)
    assert World.scene(closed, :link_world_test).movers == []
  end
end
