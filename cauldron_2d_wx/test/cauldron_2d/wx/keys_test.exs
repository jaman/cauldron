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

  test "wx key codes read as Cauldron.Input names them" do
    assert Keys.input_key(?A) == :a
    assert Keys.input_key(314) == :left
    assert Keys.input_key(32) == :" "
    assert Keys.input_key(344) == :f5
    assert Keys.input_key(?[) == :"["
  end
end
