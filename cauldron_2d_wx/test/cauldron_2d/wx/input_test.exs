defmodule Cauldron2D.Wx.InputTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Wx.Input

  @keymap %{?A => :left, ?D => :right, 315 => :jump, 32 => :act, {:mouse, :left} => :act}

  test "keys held and released, a steering key clearing the aim, buttons, and what is sent" do
    input = Input.new(@keymap, steering: [:left, :right])
    assert Input.state(input) == %{held: [], aim: nil}

    {input, true} = Input.press(input, ?A)
    {input, true} = Input.press(input, 32)
    {input, false} = Input.press(input, ?Z)
    assert Enum.sort(Input.state(input).held) == ["act", "left"]

    input = Input.aim(input, {3.5, 4.0})
    assert Input.state(input).aim == [3.5, 4.0]
    {input, true} = Input.press(input, ?D)
    assert Input.state(input).aim == nil

    {input, true} = Input.release(input, ?A)
    {input, true} = Input.release(input, ?D)
    assert Input.state(input).held == ["act"]

    {input, true} = Input.release(input, 32)
    assert Input.state(input).held == []
    input = Input.button(input, :left, true)
    assert Input.state(input).held == ["act"]
    input = Input.button(input, :left, false)
    assert Input.state(input).held == []

    assert Input.state(Input.drop(Input.press(input, ?A) |> elem(0))).held == []
  end
end
