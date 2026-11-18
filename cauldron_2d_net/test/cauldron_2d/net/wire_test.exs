defmodule Cauldron2D.Net.WireTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Net.Wire

  test "who draws and the atlas index are read into plain shapes" do
    assert Wire.drawing(%{"world" => "client", "screen" => "server"}) == %{
             world: :client,
             screen: :server
           }

    assert %{tile: 16, url: "/atlas.png", void: {16, 0, 255}, width: 64, height: 32} =
             Wire.sheet(%{
               "tile" => 16,
               "url" => "/atlas.png",
               "void" => "#1000ff",
               "width" => 64,
               "height" => 32,
               "arts" => %{}
             })
  end
end
