defmodule Cauldron2D.SurfacePoseTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias Cauldron2D.Surface
  alias FrenchCurve.Raster

  @tile 4

  defp striped(left, right) do
    rgba =
      for _y <- 1..@tile, x <- 1..@tile, into: <<>> do
        if x <= div(@tile, 2), do: left, else: right
      end

    Raster.from_rgba(@tile, @tile, rgba)
  end

  setup_all do
    Atlas.new(:pose_surface, tile: @tile, void: {0, 0, 0})
    |> Atlas.put(:ground, Raster.new(@tile, @tile, background: {20, 20, 20, 255}))
    |> Atlas.put(:knight, striped(<<255, 0, 0, 255>>, <<0, 0, 255, 255>>),
      poses: %{
        front: striped(<<0, 255, 0, 255>>, <<0, 255, 0, 255>>),
        side: striped(<<255, 0, 0, 255>>, <<0, 0, 255, 255>>)
      }
    )
    |> Atlas.install()

    :ok
  end

  defp rows, do: [[{:ground, [], nil}, {:ground, [], nil}]]

  defp drawn(mover),
    do: :pose_surface |> Surface.compose(rows(), [mover]) |> Raster.to_rgba_binary()

  describe "a mover's pose" do
    test "a named pose is drawn instead of the art's own picture" do
      assert drawn({:knight, {0, 0}}) != drawn({:knight, {0, 0}, nil, :front, false})
    end

    test "flipping mirrors the sprite left to right" do
      plain = drawn({:knight, {0, 0}, nil, :side, false})
      flipped = drawn({:knight, {0, 0}, nil, :side, true})

      assert binary_part(plain, 0, 4) == <<255, 0, 0, 255>>
      assert binary_part(flipped, 0, 4) == <<0, 0, 255, 255>>
      assert binary_part(flipped, (@tile - 1) * 4, 4) == <<255, 0, 0, 255>>
    end

    test "a pose the art does not have falls back to its own picture" do
      assert drawn({:knight, {0, 0}, nil, :back, false}) == drawn({:knight, {0, 0}})
    end

    test "the old shapes still draw what they always did" do
      assert drawn({:knight, {0, 0}}) == drawn({:knight, {0, 0}, nil})
    end
  end
end
