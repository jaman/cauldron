defmodule Cauldron2D.Wx.KeysTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Wx.Keys

  test "input key specs become wx key codes" do
    assert Keys.code(:a) == ?A
    assert Keys.code(:A) == ?A
    assert Keys.code(:"3") == ?3
    assert Keys.code(:" ") == 32
    assert Keys.code(:left) == 314
    assert Keys.code(:enter) == 13
    assert Keys.code(:left_shift) == 306
    assert Keys.code(:f5) == 344
    assert Keys.code({:f, [:ctrl]}) == ?F
    assert Keys.code({:mouse, :left}) == {:mouse, :left}
    assert Keys.code(:"[") == ?[
    assert Keys.code(:unknownkey) == nil
  end

  test "a game keymap becomes the wx input's, codes to actions" do
    assert Keys.wx_keymap(%{left: [:a, :left], fire: [:" ", {:mouse, :left}], odd: [:unknownkey]}) ==
             %{?A => :left, 314 => :left, 32 => :fire, {:mouse, :left} => :fire}
  end
end
