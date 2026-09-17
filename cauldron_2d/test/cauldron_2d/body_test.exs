defmodule Cauldron2D.BodyTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Body

  defp close?(a, b, eps \\ 1.0e-6), do: abs(a - b) < eps

  describe "headings" do
    test "heading 0 points right and a quarter turn points up, in screen coordinates" do
      body = Body.new(headings: 64)
      assert {dx, dy} = Body.direction(body)
      assert close?(dx, 1.0) and close?(dy, 0.0)

      up = Body.turn(body, 16)
      assert {dx, dy} = Body.direction(up)
      assert close?(dx, 0.0) and close?(dy, -1.0)
    end

    test "turning wraps around the circle" do
      body = Body.new(headings: 8)
      assert Body.turn(body, 9).heading == 1
      assert Body.turn(body, -1).heading == 7
    end

    test "angle is in radians, counter-clockwise from right" do
      body = Body.new(headings: 4) |> Body.turn(1)
      assert close?(Body.angle(body), :math.pi() / 2)
    end
  end

  describe "motion" do
    test "a body integrates its velocity" do
      body = Body.new(pos: {1.0, 1.0}, vel: {2.0, -1.0})
      moved = Body.integrate(body, 0.5)
      assert moved.pos == {2.0, 0.5}
    end

    test "thrust accelerates along the heading" do
      body = Body.new(headings: 4) |> Body.turn(1) |> Body.thrust(10.0, 0.1)
      {vx, vy} = body.vel
      assert close?(vx, 0.0) and close?(vy, -1.0)
    end

    test "drag scales velocity down over time and never reverses it" do
      body = Body.new(vel: {10.0, 0.0}) |> Body.drag(0.5, 1.0)
      {vx, _} = body.vel
      assert vx > 0.0 and vx < 10.0

      still = Body.new(vel: {10.0, 0.0}) |> Body.drag(0.5, 100.0)
      {vx, _} = still.vel
      assert vx >= 0.0
    end

    test "speed is the velocity's length and can be capped" do
      body = Body.new(vel: {3.0, 4.0})
      assert close?(Body.speed(body), 5.0)
      capped = Body.cap_speed(body, 2.5)
      assert close?(Body.speed(capped), 2.5)
      {vx, vy} = capped.vel
      assert close?(vx / vy, 0.75)
    end
  end

  describe "gravity" do
    test "an attracting point pulls the body toward it" do
      field = %{pos: {10.0, 0.0}, strength: 4.0, kind: :attract}
      body = Body.new(pos: {0.0, 0.0}) |> Body.gravitate([field], 1.0)
      {vx, vy} = body.vel
      assert vx > 0.0 and close?(vy, 0.0)
    end

    test "a repelling point pushes it away" do
      field = %{pos: {10.0, 0.0}, strength: 4.0, kind: :repel}
      body = Body.new(pos: {0.0, 0.0}) |> Body.gravitate([field], 1.0)
      {vx, _} = body.vel
      assert vx < 0.0
    end

    test "a uniform field pulls in its direction regardless of distance" do
      field = %{strength: 2.0, kind: {:uniform, {0.0, 1.0}}}
      body = Body.new(pos: {5.0, 5.0}) |> Body.gravitate([field], 0.5)
      assert body.vel == {0.0, 1.0}
    end

    test "a toward field pulls at full strength toward its point from anywhere" do
      field = %{strength: 2.0, kind: {:toward, {0.0, 0.0}}}
      body = Body.new(pos: {30.0, 40.0}) |> Body.gravitate([field], 1.0)
      {vx, vy} = body.vel
      assert close?(vx, -1.2) and close?(vy, -1.6)
      away = Body.new(pos: {30.0, 40.0}) |> Body.gravitate([%{field | strength: -2.0}], 1.0)
      assert elem(away.vel, 0) > 0.0
    end

    test "a clockwise field pushes across the line to its centre" do
      field = %{pos: {0.0, 0.0}, strength: 4.0, kind: :clockwise}
      body = Body.new(pos: {10.0, 0.0}) |> Body.gravitate([field], 1.0)
      {vx, vy} = body.vel
      assert close?(vx, 0.0) and vy > 0.0
    end

    test "a field's pull falls off with distance and is capped close in" do
      near = %{pos: {1.0, 0.0}, strength: 4.0, kind: :attract}
      far = %{pos: {4.0, 0.0}, strength: 4.0, kind: :attract}
      {vn, _} = Body.new() |> Body.gravitate([near], 1.0) |> Map.fetch!(:vel)
      {vf, _} = Body.new() |> Body.gravitate([far], 1.0) |> Map.fetch!(:vel)
      assert vn > vf

      {vzero, _} =
        Body.new() |> Body.gravitate([%{near | pos: {0.0, 0.0}}], 1.0) |> Map.fetch!(:vel)

      assert vzero == 0.0
    end
  end

  describe "wrapping" do
    test "a body leaving a wrapping world comes in the other side" do
      body = Body.new(pos: {-0.5, 20.5}) |> Body.wrap({10, 20})
      assert body.pos == {9.5, 0.5}
    end

    test "a body inside is untouched" do
      body = Body.new(pos: {3.0, 4.0})
      assert Body.wrap(body, {10, 20}).pos == {3.0, 4.0}
    end
  end
end
