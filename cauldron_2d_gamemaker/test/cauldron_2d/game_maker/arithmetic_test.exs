defmodule Cauldron2D.GameMaker.ArithmeticTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.GameMaker.Background

  doctest Cauldron2D.GameMaker.Event

  test "a tile's place counts its border on both sides of every cell" do
    tileset = %Background{
      name: "set",
      picture: nil,
      tiles: %{
        size: {16, 16},
        border: {2, 2},
        columns: 16,
        count: 256,
        frames: 1,
        frame_time: 0,
        ids: []
      }
    }

    assert Background.tile_source(tileset, 0) == {2, 2, 16, 16}
    assert Background.tile_source(tileset, 17) == {22, 22, 16, 16}
    assert Background.tile_source(tileset, 15) == {302, 2, 16, 16}
  end
end
