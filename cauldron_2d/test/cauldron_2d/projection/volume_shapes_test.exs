defmodule Cauldron2D.Projection.Volume.ShapesTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Projection.Volume.Shapes

  defp crossed(shape, origin, direction) do
    shape
    |> Shapes.span(origin, direction)
    |> Enum.reduce(0.0, fn {from, to}, total -> total + (to - from) end)
  end

  describe "sphere" do
    test "a ray through the middle crosses the diameter" do
      assert_in_delta crossed({:sphere, 2.0, 0.0}, {-9.0, 0.0, 0.0}, {1.0, 0.0, 0.0}),
                      4.0,
                      1.0e-9
    end

    test "one that floats sits above the ground by its height" do
      floating = {:sphere, 1.0, 3.0}

      assert crossed(floating, {-9.0, 0.0, 3.0}, {1.0, 0.0, 0.0}) > 0.0
      assert crossed(floating, {-9.0, 0.0, 0.5}, {1.0, 0.0, 0.0}) == 0.0
    end
  end

  describe "cylinder" do
    test "a ray down the axis crosses its height" do
      assert_in_delta crossed({:cylinder, 3.0, 2.0}, {0.0, 0.0, 9.0}, {0.0, 0.0, -1.0}),
                      2.0,
                      1.0e-9
    end

    test "a ray across the middle crosses the diameter" do
      assert_in_delta crossed({:cylinder, 3.0, 2.0}, {-9.0, 0.0, 1.0}, {1.0, 0.0, 0.0}),
                      6.0,
                      1.0e-9
    end

    test "a ray over the top crosses nothing" do
      assert crossed({:cylinder, 3.0, 2.0}, {-9.0, 0.0, 5.0}, {1.0, 0.0, 0.0}) == 0.0
    end
  end

  describe "cone" do
    test "a ray down the middle reaches the length" do
      quarter = {:cone, 6.0, :math.pi() / 2, 0.0, 2.0}

      assert_in_delta crossed(quarter, {-10.0, 0.0, 1.0}, {1.0, 0.0, 0.0}), 6.0, 1.0e-9
    end

    test "a ray across it is cut by the spread, not the length" do
      quarter = {:cone, 6.0, :math.pi() / 2, 0.0, 2.0}

      assert_in_delta crossed(quarter, {3.0, -10.0, 1.0}, {0.0, 1.0, 0.0}), 6.0, 1.0e-9
    end

    test "nothing outside the spread is inside the cone" do
      quarter = {:cone, 6.0, :math.pi() / 2, 0.0, 2.0}

      assert crossed(quarter, {-10.0, 5.0, 1.0}, {1.0, 0.0, 0.0}) == 0.0
    end

    test "it points along its heading" do
      backwards = {:cone, 6.0, :math.pi() / 2, :math.pi(), 2.0}

      assert crossed(backwards, {-3.0, -10.0, 1.0}, {0.0, 1.0, 0.0}) > 0.0
      assert crossed(backwards, {3.0, -10.0, 1.0}, {0.0, 1.0, 0.0}) == 0.0
    end
  end

  describe "beam" do
    test "a ray along it crosses its length" do
      assert_in_delta crossed({:beam, 8.0, 1.0, 0.0, 2.0}, {-10.0, 0.0, 1.0}, {1.0, 0.0, 0.0}),
                      8.0,
                      1.0e-9
    end

    test "a ray across it crosses its width" do
      assert_in_delta crossed({:beam, 8.0, 1.0, 0.0, 2.0}, {4.0, -10.0, 1.0}, {0.0, 1.0, 0.0}),
                      1.0,
                      1.0e-9
    end

    test "it starts where the volume stands rather than straddling it" do
      assert crossed({:beam, 8.0, 1.0, 0.0, 2.0}, {-4.0, -10.0, 1.0}, {0.0, 1.0, 0.0}) == 0.0
    end
  end

  describe "cells" do
    test "a ray across touching tiles crosses them as one stretch" do
      tiles = {:cells, MapSet.new([{0, 0}, {1, 0}]), 2.0}

      assert [{from, to}] = Shapes.span(tiles, {-1.0, 0.5, 0.5}, {1.0, 0.0, 0.0})
      assert_in_delta to - from, 2.0, 1.0e-6
    end

    test "a ray across a gap crosses each side on its own" do
      tiles = {:cells, MapSet.new([{0, 0}, {2, 0}]), 2.0}

      assert [one, other] = Shapes.span(tiles, {-1.0, 0.5, 0.5}, {1.0, 0.0, 0.0})
      assert elem(one, 1) < elem(other, 0)
    end

    test "a ray straight down an occupied tile crosses its height" do
      tiles = {:cells, MapSet.new([{0, 0}]), 2.0}

      assert_in_delta crossed(tiles, {0.5, 0.5, 9.0}, {0.0, 0.0, -1.0}), 2.0, 1.0e-9
    end

    test "a ray straight down an empty tile crosses nothing" do
      tiles = {:cells, MapSet.new([{0, 0}]), 2.0}

      assert crossed(tiles, {4.5, 0.5, 9.0}, {0.0, 0.0, -1.0}) == 0.0
    end

    test "no tiles is nothing to cross" do
      assert Shapes.span({:cells, MapSet.new(), 2.0}, {0.0, 0.0, 1.0}, {1.0, 0.0, 0.0}) == []
    end
  end

  describe "bounds/1" do
    test "hold the shape" do
      assert Shapes.bounds({:sphere, 2.0, 0.0}) == {{-2.0, -2.0, -2.0}, {2.0, 2.0, 2.0}}
      assert Shapes.bounds({:cylinder, 3.0, 2.0}) == {{-3.0, -3.0, 0.0}, {3.0, 3.0, 2.0}}
    end

    test "a beam's box turns with its heading" do
      {{left, top, _low}, {right, bottom, _high}} =
        Shapes.bounds({:beam, 8.0, 1.0, :math.pi() / 2, 2.0})

      assert_in_delta right - left, 1.0, 1.0e-9
      assert_in_delta bottom - top, 8.0, 1.0e-9
    end

    test "a set of tiles reaches the far edge of the last one" do
      assert Shapes.bounds({:cells, MapSet.new([{0, 0}, {1, 0}]), 2.0}) ==
               {{0.0, 0.0, 0.0}, {2.0, 1.0, 2.0}}
    end
  end
end
