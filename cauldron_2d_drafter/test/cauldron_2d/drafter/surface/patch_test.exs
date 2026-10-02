defmodule Cauldron2D.Drafter.Surface.PatchTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Drafter.Surface.Patch

  @picture {960, 400}
  @cell {8, 16}

  describe "plan/4" do
    test "nothing moving needs no patch" do
      assert Patch.plan([], @picture, @cell, 0.4) == {:patches, []}
    end

    test "a spot grows out to the cell edges around it" do
      assert Patch.plan([{10, 20, 4, 4}], @picture, @cell, 0.4) ==
               {:patches, [{8, 16, 8, 16}]}
    end

    test "a spot already on cell edges is left as it is" do
      assert Patch.plan([{16, 32, 16, 32}], @picture, @cell, 0.4) ==
               {:patches, [{16, 32, 16, 32}]}
    end

    test "a spot is clipped to the picture" do
      {:patches, [{x, y, w, h}]} = Patch.plan([{-30, -30, 100, 100}], @picture, @cell, 0.4)

      assert {x, y} == {0, 0}
      assert {w, h} == {72, 80}
    end

    test "a spot wholly outside the picture is dropped" do
      assert Patch.plan([{-200, -200, 50, 50}], @picture, @cell, 0.4) == {:patches, []}
      assert Patch.plan([{2000, 20, 50, 50}], @picture, @cell, 0.4) == {:patches, []}
    end

    test "spots far apart stay apart" do
      {:patches, rects} = Patch.plan([{0, 0, 8, 16}, {400, 200, 8, 16}], @picture, @cell, 0.4)

      assert length(rects) == 2
    end

    test "overlapping spots become one rectangle" do
      assert Patch.plan([{0, 0, 40, 40}, {16, 16, 40, 40}], @picture, @cell, 0.4) ==
               {:patches, [{0, 0, 56, 64}]}
    end

    test "merging runs until nothing touches" do
      spots = for step <- 0..9, do: {step * 20, 0, 24, 16}
      {:patches, rects} = Patch.plan(spots, @picture, @cell, 0.9)

      assert [{0, 0, 208, 16}] = rects
    end

    test "rectangles that only abut are merged" do
      assert Patch.plan([{0, 0, 8, 16}, {8, 0, 8, 16}], @picture, @cell, 0.4) ==
               {:patches, [{0, 0, 16, 16}]}
    end

    test "moving parts covering more than the room asked for want the whole picture" do
      assert Patch.plan([{0, 0, 960, 200}], @picture, @cell, 0.4) == :whole
    end

    test "the same spots fit under a larger room" do
      assert {:patches, _} = Patch.plan([{0, 0, 960, 200}], @picture, @cell, 0.6)
    end

    test "many small spots count their merged area, not their own" do
      spots = for step <- 0..9, do: {step * 8, 0, 8, 16}

      assert Patch.plan(spots, @picture, @cell, 0.01) == {:patches, [{0, 0, 80, 16}]}
    end
  end
end
