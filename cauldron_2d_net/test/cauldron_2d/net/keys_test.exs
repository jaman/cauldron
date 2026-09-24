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

defmodule Cauldron2D.Net.KeysPadmapTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Input.Pad
  alias Cauldron2D.Net.Keys

  test "a padmap becomes the browser's: buttons to actions, each axis direction to actions" do
    padmap = Map.merge(Pad.default_map([:left, :right, :up]), %{pick: [:a, :right_bumper]})

    assert Keys.browser_padmap(padmap) == %{
             "buttons" => %{
               "dpad_left" => ["left"],
               "dpad_right" => ["right"],
               "dpad_up" => ["up"],
               "a" => ["pick"],
               "right_bumper" => ["pick"]
             },
             "axes" => %{
               "left_x" => %{"neg" => ["left"], "pos" => ["right"]},
               "left_y" => %{"neg" => ["up"]}
             }
           }
  end

  test "a stick bound to aim goes to the browser by its side" do
    assert %{"aim" => "left", "buttons" => %{"a" => ["pick"]}} =
             Keys.browser_padmap(%{aim: [{:stick, :left}], pick: [:a]})

    refute Map.has_key?(Keys.browser_padmap(%{pick: [:a]}), "aim")
  end

  test "an aim stick's push goes with it, with the rule's numbers filled in" do
    padmap = %{aim: [{:stick, :right, push: [action: :thrust, beyond: 0.6]}]}

    assert %{
             "aim" => "right",
             "push" => %{"action" => "thrust", "beyond" => 0.6, "least" => 0.25, "gain" => 1.6}
           } = Keys.browser_padmap(padmap)
  end
end
