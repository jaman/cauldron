defmodule Cauldron2D.OverlapTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.{Mask, Overlap, Shape}

  defp ring do
    Mask.new(3, 3, <<0b11100000, 0b10100000, 0b11100000>>)
  end

  test "rectangles that only meet along an edge do not overlap; one shared pixel does" do
    left = Shape.new({:rectangle, 4, 4}, {0, 0})

    refute Overlap.shapes?(left, Shape.new({:rectangle, 4, 4}, {4, 0}))
    assert Overlap.shapes?(left, Shape.new({:rectangle, 4, 4}, {3, 3}))
  end

  test "a mask's empty pixels collide with nothing" do
    ring = Shape.new({:mask, ring()}, {10, 10})

    refute Overlap.rectangle?(ring, {11, 11, 12, 12})
    assert Overlap.rectangle?(ring, {12, 11, 13, 12})
    refute Overlap.point?(ring, {11.5, 11.5})
  end

  test "mirroring and quarter turns move solid pixels where the drawing puts them" do
    corner = Mask.new(2, 2, <<0b10000000, 0b00000000>>)

    mirrored = Shape.new({:mask, corner}, {10, 10}, origin: {1, 0}, scale: {-1, 1})
    assert Overlap.point?(mirrored, {10.5, 10.5})
    refute Overlap.point?(mirrored, {9.5, 10.5})

    turned = Shape.new({:mask, corner}, {10, 10}, angle: 90)
    assert Overlap.point?(turned, {10.5, 9.5})
    refute Overlap.point?(turned, {10.5, 10.5})
  end

  test "circles and lines meet shapes at the pixels they cover" do
    box = Shape.new({:rectangle, 2, 2}, {10, 10})

    assert Overlap.circle?(box, {8, 11}, 2.6)
    refute Overlap.circle?(box, {8, 11}, 1.4)
    assert Overlap.line?(box, {0, 11}, {20, 11})
    refute Overlap.line?(box, {0, 13}, {20, 13})
  end
end
