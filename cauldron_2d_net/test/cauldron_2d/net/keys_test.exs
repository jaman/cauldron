defmodule Cauldron2D.Net.KeysTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Net.Keys

  test "input key specs become KeyboardEvent codes and mouse buttons" do
    assert Keys.code(:a) == "KeyA"
    assert Keys.code(:A) == "KeyA"
    assert Keys.code(:"1") == "Digit1"
    assert Keys.code(:left) == "ArrowLeft"
    assert Keys.code(:" ") == "Space"
    assert Keys.code(:enter) == "Enter"
    assert Keys.code(:left_shift) == "ShiftLeft"
    assert Keys.code(:"[") == "BracketLeft"
    assert Keys.code({:f, [:ctrl]}) == "KeyF"
    assert Keys.code({:mouse, :left}) == {:mouse, "0"}
    assert Keys.code({:mouse, :right}) == {:mouse, "2"}
    assert Keys.code(:f5) == "F5"
    assert Keys.code(:unknownkey) == nil
  end

  test "a keymap becomes the browser's, codes to action names, mouse buttons under mouse" do
    keymap = %{left: [:a, :left], fire: [:" ", {:mouse, :left}], odd: [:unknownkey]}

    assert Keys.browser_keymap(keymap) == %{
             "KeyA" => "left",
             "ArrowLeft" => "left",
             "Space" => "fire",
             "mouse" => %{"0" => "fire"}
           }
  end
end
