defmodule Cauldron2D.Net.RemoteSceneTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.{Atlas, Draw}
  alias Cauldron2D.Net.RemoteScene
  alias FrenchCurve.Raster

  setup_all do
    Atlas.new(:link_world_test, tile: 4)
    |> Atlas.put(:wall, Raster.new(4, 4, background: {0, 0, 200, 255}))
    |> Atlas.install()

    :ok
  end

  @status %{
    focus: {1.5, 1.0},
    subject: "bob",
    hud: [[{"fuel", "#ff0000"}, {"3", nil}]],
    over: nil
  }

  test "a remote view is a picture scene: the server's picture fitted to the size asked, or its scene drawn here" do
    pictured = %{
      remote: %{status: @status, picture: Raster.new(2, 1, background: {9, 9, 9, 255})},
      world: "pit"
    }

    scene = RemoteScene.scene(pictured)
    assert scene.focus == {1.5, 1.0} and scene.subject == "bob"
    assert %Raster{width: 6, height: 3} = scene.picture.({6, 3}, 1.0)

    view =
      Draw.new(atlas: :link_world_test, focus: {1.0, 1.0}, cell: fn _ -> {:wall, [], nil} end)

    drawn = %{remote: %{status: @status, drawn: view, picture: nil}, world: "pit"}
    raster = RemoteScene.scene(drawn).picture.({8, 8}, 1.0)
    assert Raster.get_pixel(raster, 3, 3) == {0, 0, 200, 255}
  end
end
