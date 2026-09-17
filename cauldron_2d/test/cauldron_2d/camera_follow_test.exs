defmodule Cauldron2D.Camera.FollowTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Camera.Follow

  test "the camera closes on its target by a share of the distance each second, never overshooting" do
    follow = Follow.new({0.0, 0.0})
    moved = Follow.follow(follow, {10.0, 0.0}, 0.5, 0.5)
    {x, _} = Follow.focus(moved)
    assert x > 0.0 and x < 10.0

    settled =
      Enum.reduce(1..200, follow, fn _, acc -> Follow.follow(acc, {10.0, 0.0}, 0.05, 0.5) end)

    assert_in_delta elem(Follow.focus(settled), 0), 10.0, 0.01
    snapped = Follow.follow(follow, {10.0, 4.0}, 1.0, 0.0)
    assert Follow.focus(snapped) == {10.0, 4.0}
  end

  test "a shake offsets the focus, fades over its time, and stops" do
    follow = Follow.new({5.0, 5.0}) |> Follow.shake(1.0, 0.5)
    early = Follow.step(follow, 0.05)
    assert Follow.focus(early) != {5.0, 5.0}
    {dx, dy} = Follow.offset(early)
    assert abs(dx) <= 1.0 and abs(dy) <= 1.0
    later = Enum.reduce(1..5, early, fn _, acc -> Follow.step(acc, 0.1) end)
    assert Follow.offset(later) == {0.0, 0.0}
    assert Follow.focus(later) == {5.0, 5.0}
    assert Follow.step(later, 0.1) == later
  end
end
