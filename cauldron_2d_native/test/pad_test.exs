defmodule Cauldron2D.Native.PadTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Native.Pad

  @screen %{width: 2000, height: 1000, scale: 2.0, insets: {0, 0, 0, 0}}

  defp pad, do: Pad.new(@screen, %{a: "A JUMP", b: "B ROLL", start: "II"})
  defp control(pad, button), do: Enum.find(pad.controls, &(&1.button == button))
  defp touch(id, phase, {x, y}), do: %{id: id, phase: phase, x: x, y: y}
  defp touch(id, phase, %{x: x, y: y}), do: touch(id, phase, {x, y})

  test "the stick sets down where the thumb lands, presses right as it moves right, and lets go when lifted" do
    {pad, [], []} = Pad.touch(pad(), [touch(1, :began, {300, 700})])
    {pad, pressed, []} = Pad.touch(pad, [touch(1, :moved, {300 + pad.stick.radius * 0.8, 700})])
    assert pressed == [%{type: :button, device: 0, button: :dpad_right, pressed: true}]

    {pad, released, []} = Pad.touch(pad, [touch(1, :ended, {380, 700})])
    assert released == [%{type: :button, device: 0, button: :dpad_right, pressed: false}]
    assert pad.stick.origin == nil
  end

  test "a thumb run past the stick's edge drags it, so turning back presses the other way at once" do
    {pad, _events, []} = Pad.touch(pad(), [touch(1, :began, {300, 700})])
    {pad, _events, []} = Pad.touch(pad, [touch(1, :moved, {700, 700})])
    {_pad, events, []} = Pad.touch(pad, [touch(1, :moved, {700 - pad.stick.radius * 1.4, 700})])

    assert %{type: :button, device: 0, button: :dpad_left, pressed: true} in events
    assert %{type: :button, device: 0, button: :dpad_right, pressed: false} in events
  end

  test "a finger sliding from one button onto another lets the first go and presses the second" do
    pad = pad()
    {pad, _pressed, []} = Pad.touch(pad, [touch(1, :began, control(pad, :a))])
    {_pad, events, []} = Pad.touch(pad, [touch(1, :moved, control(pad, :b))])

    assert events == [
             %{type: :button, device: 0, button: :a, pressed: false},
             %{type: :button, device: 0, button: :b, pressed: true}
           ]
  end

  test "unlocked, a thumb landing on the buttons' side well clear of the fan brings the fan under it and presses A" do
    moving = Pad.new(@screen, %{a: "A JUMP", b: "B ROLL"}, buttons: :move)
    {pad, events, []} = Pad.touch(moving, [touch(1, :began, {1300, 500})])
    assert events == [%{type: :button, device: 0, button: :a, pressed: true}]
    assert {control(pad, :a).x, control(pad, :a).y} == {1300.0, 500.0}
  end

  test "a quick tap just off a button presses the nearest one and leaves the fan where it is" do
    pad = pad()
    a = control(pad, :a)
    {after_tap, events, []} = Pad.touch(pad, [touch(1, :began, {a.x - a.radius * 2, a.y + 10})])
    assert events == [%{type: :button, device: 0, button: :a, pressed: true}]
    assert control(after_tap, :a) == a
  end

  test "a fan moved and kept by its offset is put back in the same place" do
    moving = Pad.new(@screen, %{a: "A JUMP"}, buttons: :move, hand: :left)
    {moved, _events, []} = Pad.touch(moving, [touch(1, :began, {600, 520})])
    again = Pad.new(@screen, %{a: "A JUMP"}, hand: :left, offset: Pad.offset(moved))
    assert {round(control(again, :a).x), round(control(again, :a).y)} == {600, 520}
  end

  test "left-handed, the stick sets down on the right and the fan sits on the left" do
    pad = Pad.new(@screen, %{a: "A JUMP"}, hand: :left)
    assert control(pad, :a).x < 1000
    {pad, [], []} = Pad.touch(pad, [touch(1, :began, {1700, 700})])
    assert pad.stick.origin == {1700.0, 700.0}
  end

  test "a finger landing on no control outside the stick's part of the screen is a pointer" do
    {_pad, [], pointers} = Pad.touch(pad(), [%{id: 1, phase: :began, x: 1000, y: 150}])
    assert pointers == [{:down, {1000.0, 150.0}}]
  end
end
