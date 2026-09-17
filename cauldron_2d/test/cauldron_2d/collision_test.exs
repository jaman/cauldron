defmodule Cauldron2D.CollisionTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Collision
  alias Cauldron2D.Collision.Buckets

  defp close?(a, b, eps \\ 1.0e-6), do: abs(a - b) < eps

  defp wall_at(cells) do
    fn cell -> Map.get(cells, cell, :open) end
  end

  describe "inside?/2" do
    test "square tiles are solid throughout" do
      grid = wall_at(%{{3, 3} => :solid})
      assert Collision.inside?(grid, {3.5, 3.5})
      refute Collision.inside?(grid, {2.5, 3.5})
    end

    test "a diagonal tile is solid only in its filled corner" do
      grid = wall_at(%{{0, 0} => {:diagonal, :se}})
      assert Collision.inside?(grid, {0.9, 0.9})
      refute Collision.inside?(grid, {0.1, 0.1})

      grid = wall_at(%{{0, 0} => {:diagonal, :nw}})
      assert Collision.inside?(grid, {0.1, 0.1})
      refute Collision.inside?(grid, {0.9, 0.9})

      grid = wall_at(%{{0, 0} => {:diagonal, :ne}})
      assert Collision.inside?(grid, {0.9, 0.1})
      refute Collision.inside?(grid, {0.1, 0.9})

      grid = wall_at(%{{0, 0} => {:diagonal, :sw}})
      assert Collision.inside?(grid, {0.1, 0.9})
      refute Collision.inside?(grid, {0.9, 0.1})
    end
  end

  describe "sweep/4" do
    test "an open path is clear" do
      grid = wall_at(%{})
      assert {:clear, {5.0, 1.0}} = Collision.sweep(grid, {1.0, 1.0}, {5.0, 1.0}, 0.0)
    end

    test "a wall to the right stops the body short with a leftward normal" do
      grid = wall_at(%{{5, 1} => :solid})

      assert {:blocked, {x, y}, {nx, ny}, {5, 1}} =
               Collision.sweep(grid, {1.0, 1.5}, {6.0, 1.5}, 0.0)

      assert x < 5.0 and x > 4.0
      assert close?(y, 1.5)
      assert close?(nx, -1.0) and close?(ny, 0.0)
    end

    test "a wall below stops the body with an upward normal" do
      grid = wall_at(%{{1, 5} => :solid})

      assert {:blocked, _at, {nx, ny}, {1, 5}} =
               Collision.sweep(grid, {1.5, 1.0}, {1.5, 6.0}, 0.0)

      assert close?(nx, 0.0) and close?(ny, -1.0)
    end

    test "a body's radius touches before its centre does" do
      grid = wall_at(%{{5, 1} => :solid})
      assert {:blocked, {x, _}, _, _} = Collision.sweep(grid, {1.0, 1.5}, {6.0, 1.5}, 0.5)
      assert x <= 4.5 + 0.01
    end

    test "a fast body cannot tunnel through a thin wall" do
      grid = wall_at(%{{50, 1} => :solid})
      assert {:blocked, _, _, {50, 1}} = Collision.sweep(grid, {1.0, 1.5}, {400.0, 1.5}, 0.0)
    end

    test "a diagonal face reflects across its slope" do
      grid = wall_at(%{{5, 5} => {:diagonal, :se}})

      assert {:blocked, _at, {nx, ny}, {5, 5}} =
               Collision.sweep(grid, {5.05, 5.05}, {5.9, 5.9}, 0.0)

      assert close?(nx, -:math.sqrt(0.5)) and close?(ny, -:math.sqrt(0.5))
    end

    test "entering a diagonal tile through its solid side gives that side's normal" do
      grid = wall_at(%{{5, 5} => {:diagonal, :se}})

      assert {:blocked, _at, {nx, ny}, {5, 5}} =
               Collision.sweep(grid, {7.0, 5.9}, {5.5, 5.9}, 0.0)

      assert close?(nx, 1.0) and close?(ny, 0.0)
    end

    test "starting inside a wall is reported at the start" do
      grid = wall_at(%{{1, 1} => :solid})

      assert {:blocked, {1.5, 1.5}, _normal, {1, 1}} =
               Collision.sweep(grid, {1.5, 1.5}, {3.0, 1.5}, 0.0)
    end
  end

  describe "bounce/3" do
    test "reflects the component along the normal and keeps the rest" do
      assert {vx, vy} = Collision.bounce({3.0, 2.0}, {-1.0, 0.0}, 1.0)
      assert close?(vx, -3.0) and close?(vy, 2.0)
    end

    test "restitution scales the reflected component" do
      assert {vx, _} = Collision.bounce({4.0, 0.0}, {-1.0, 0.0}, 0.5)
      assert close?(vx, -2.0)
    end

    test "a velocity already leaving the surface is untouched" do
      assert {-3.0, 2.0} = Collision.bounce({-3.0, 2.0}, {-1.0, 0.0}, 1.0)
    end
  end

  describe "circles" do
    test "overlap when closer than the sum of radii" do
      assert Collision.circles_overlap?({0.0, 0.0}, 1.0, {1.5, 0.0}, 1.0)
      refute Collision.circles_overlap?({0.0, 0.0}, 1.0, {2.5, 0.0}, 1.0)
    end
  end

  describe "Buckets" do
    test "near/3 finds what is within reach and nothing far away" do
      buckets =
        Buckets.new(4)
        |> Buckets.insert(:a, {1.0, 1.0}, 0.5)
        |> Buckets.insert(:b, {2.0, 1.0}, 0.5)
        |> Buckets.insert(:c, {40.0, 40.0}, 0.5)

      assert Enum.sort(Buckets.near(buckets, {1.5, 1.0}, 1.0)) == [:a, :b]
      assert Buckets.near(buckets, {39.0, 40.0}, 1.5) == [:c]
    end

    test "pairs/1 lists each overlapping pair once" do
      buckets =
        Buckets.new(4)
        |> Buckets.insert(:a, {1.0, 1.0}, 0.6)
        |> Buckets.insert(:b, {2.0, 1.0}, 0.6)
        |> Buckets.insert(:c, {3.9, 1.0}, 0.5)
        |> Buckets.insert(:d, {4.1, 1.0}, 0.5)

      assert Enum.sort(Buckets.pairs(buckets)) == [{:a, :b}, {:c, :d}]
    end
  end
end
