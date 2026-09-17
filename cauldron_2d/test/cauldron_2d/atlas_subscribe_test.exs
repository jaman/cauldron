defmodule Cauldron2D.AtlasSubscribeTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias FrenchCurve.Raster

  @tile 4

  defp atlas(colour) do
    Atlas.new(:atlas_subscribe, tile: @tile)
    |> Atlas.put(:floor, Raster.new(@tile, @tile, background: colour))
  end

  test "a subscriber hears when the atlas it watches is installed changed" do
    Atlas.install(atlas({1, 1, 1, 255}))
    :ok = Atlas.subscribe(:atlas_subscribe)

    Atlas.install(atlas({1, 1, 1, 255}))
    refute_receive {:cauldron_atlas, :atlas_subscribe, :changed}, 50

    Atlas.install(atlas({2, 2, 2, 255}))
    assert_receive {:cauldron_atlas, :atlas_subscribe, :changed}

    Atlas.unsubscribe(:atlas_subscribe)
    Atlas.install(atlas({3, 3, 3, 255}))
    refute_receive {:cauldron_atlas, :atlas_subscribe, :changed}, 50
  end

  test "a first install is told too, so a watcher started early sees the art arrive" do
    :ok = Atlas.subscribe(:atlas_subscribe_first)
    Atlas.install(Atlas.new(:atlas_subscribe_first, tile: @tile))
    assert_receive {:cauldron_atlas, :atlas_subscribe_first, :changed}
  end
end
