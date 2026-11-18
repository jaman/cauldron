defmodule Cauldron.Net.KeysTest do
  use ExUnit.Case, async: true

  alias Cauldron.Net.Keys

  test "a browser's key names read as Cauldron.Input names them, and back" do
    for {browser, input} <- [
          {"ArrowLeft", :left},
          {" ", :" "},
          {"q", :q},
          {"Q", :Q},
          {"?", :"?"},
          {"F5", :f5},
          {"Escape", :escape}
        ] do
      assert Keys.input_key(browser) == input
      assert Keys.browser_key(input) == browser
    end

    assert Keys.input_key("Dead") == nil
    assert Keys.input_mods(["ctrl", "hyper", "shift"]) == [:ctrl, :shift]
  end

  test "a modifier key reads by its side, as a terminal names it, and back" do
    for {key, code, input} <- [
          {"Shift", "ShiftLeft", :left_shift},
          {"Shift", "ShiftRight", :right_shift},
          {"Control", "ControlLeft", :left_control},
          {"Alt", "AltRight", :right_alt},
          {"Meta", "MetaLeft", :left_super}
        ] do
      assert Keys.input_key(key, code) == input
      assert Keys.browser_key(input) == key
      assert Keys.browser_code(input) == code
    end

    assert Keys.input_key("a", "KeyA") == :a
  end
end
