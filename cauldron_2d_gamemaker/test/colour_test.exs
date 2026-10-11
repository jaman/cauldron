defmodule Cauldron2D.GameMaker.ColourTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.GameMaker.Colour

  test "hsv puts the primaries a third of the wheel apart, 255 hue units around" do
    assert Colour.hsv(0, 255, 255) == {255, 0, 0}
    assert Colour.hsv(85, 255, 255) == {0, 255, 0}
    assert Colour.hsv(170, 255, 255) == {0, 0, 255}
    assert Colour.hsv(255, 255, 255) == {255, 0, 0}
  end

  test "hsv with no saturation is grey at the value, and with no value is black" do
    assert Colour.hsv(40, 0, 128) == {128, 128, 128}
    assert Colour.hsv(40, 200, 0) == {0, 0, 0}
  end

  test "merge goes from the first colour to the second by amount" do
    assert Colour.merge({0, 0, 0}, {200, 100, 50}, 0.5) == {100, 50, 25}
    assert Colour.merge({10, 20, 30}, {200, 100, 50}, 0.0) == {10, 20, 30}
  end
end
