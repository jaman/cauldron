defmodule Cauldron2D.FitTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Fit

  test "a 4:3 frame in a wide picture has bars at the sides" do
    assert Fit.letterbox({400, 200}, 1.0, {320, 240}) == {66, 0, 267, 200}
  end

  test "a 4:3 frame in a tall picture has bars above and below" do
    assert Fit.letterbox({320, 400}, 1.0, {320, 240}) == {0, 80, 320, 240}
  end

  test "pixels twice as tall as wide need half the rows" do
    assert Fit.letterbox({320, 120}, 2.0, {320, 240}) == {0, 0, 320, 120}
  end

  test "a point on the bars is outside the frame" do
    assert Fit.within({0.5, 0.5}, {400, 200}, 1.0, {320, 240}) == {0.50187265917603, 0.5}
    assert Fit.within({0.05, 0.5}, {400, 200}, 1.0, {320, 240}) == nil
  end
end
