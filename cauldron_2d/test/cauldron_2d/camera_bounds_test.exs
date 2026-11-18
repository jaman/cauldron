defmodule Cauldron2D.CameraBoundsTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Camera
  alias Cauldron2D.Camera.Follow

  test "the view stops at the level's edges, and centres on a level narrower than it" do
    assert Camera.within({2.0, 37.0}, {0, 0, 100, 40}, {12, 6}) == {12.0, 34.0}
    assert Camera.within({50.0, 20.0}, {0, 0, 100, 40}, {12, 6}) == {50.0, 20.0}
    assert Camera.within({3.0, 5.0}, {0, 0, 20, 40}, {12, 6}) == {10.0, 6.0}
  end

  test "inside the deadzone the camera keeps still; outside it, it follows only the overshoot" do
    camera = Follow.new({10.0, 5.0})
    assert Follow.follow(camera, {11.0, 5.5}, 0.1, 0.0, deadzone: {4, 2}).pos == {10.0, 5.0}
    assert Follow.follow(camera, {14.0, 5.0}, 0.1, 0.0, deadzone: {4, 2}).pos == {12.0, 5.0}
  end
end
