defmodule Cauldron2D.Projection.OcclusionTest do
  @moduledoc """
  What stands nearer the viewer covers what stands behind it, in every projection that
  has a depth: the isometric view, the oblique view, and mode 7's billboards.
  """

  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias Cauldron2D.Projection.{Iso, Mode7, Oblique}
  alias FrenchCurve.Raster

  @tile 8
  @grass {40, 160, 40, 255}
  @brick {160, 120, 80, 255}
  @roof {200, 40, 40, 255}
  @near {250, 250, 20, 255}
  @far {20, 20, 250, 255}

  setup_all do
    Atlas.new(:occlusion_test, tile: @tile, void: {6, 7, 11})
    |> Atlas.put(:grass, Raster.new(@tile, @tile, background: @grass))
    |> Atlas.put(:wall, Raster.new(@tile, @tile, background: @brick),
      height: 2,
      faces: %{top: Raster.new(@tile, @tile, background: @roof)}
    )
    |> Atlas.put(:near, Raster.new(@tile, @tile, background: @near))
    |> Atlas.put(:far, Raster.new(@tile, @tile, background: @far))
    |> Atlas.install()

    :ok
  end

  defp colours(raster),
    do: for(<<r, g, b, a <- Raster.to_rgba_binary(raster)>>, uniq: true, do: {r, g, b, a})

  defp count(raster, colour),
    do:
      Enum.count(
        for(<<r, g, b, a <- Raster.to_rgba_binary(raster)>>, do: {r, g, b, a}),
        &(&1 == colour)
      )

  defp field(_position), do: {:grass, [], nil}

  defp walled({3, 3}), do: {:grass, [:wall], nil}
  defp walled(position), do: field(position)

  describe "isometric" do
    test "a mover behind a standing art is covered by it" do
      raster =
        Iso.compose(:occlusion_test,
          focus: {3.5, 3.5},
          cell: &walled/1,
          size: {64, 48},
          movers: [{:far, {2.5, 2.5}}]
        )

      assert @roof in colours(raster), "drew no wall"
      refute @far in colours(raster), "drew the mover through the wall"
    end

    test "of two movers in line the nearer covers the farther" do
      alone = movers_drawn([{:far, {4.0, 4.0}}])
      both = movers_drawn([{:far, {4.0, 4.0}}, {:near, {4.5, 4.5}}])

      assert count(alone, @far) > 0, "drew no far mover"
      assert count(both, @near) == count(alone, @far), "clipped the near mover"
      assert count(both, @far) < count(alone, @far), "drew the far mover over the near"
    end

    defp movers_drawn(movers),
      do:
        Iso.compose(:occlusion_test,
          focus: {4.5, 4.5},
          cell: &field/1,
          size: {64, 48},
          movers: movers
        )
  end

  describe "oblique" do
    test "a mover behind a standing art is covered by it" do
      raster =
        Oblique.compose(:occlusion_test,
          focus: {3.5, 3.5},
          cell: &walled/1,
          size: {64, 48},
          movers: [{:far, {3.5, 2.5}}]
        )

      assert @roof in colours(raster)
      refute @far in colours(raster)
    end
  end

  describe "mode 7" do
    test "of two billboards in line the nearer covers the farther" do
      raster =
        Mode7.render(:occlusion_test,
          position: {4.5, 4.5},
          heading: 0.0,
          cell: &field/1,
          size: {64, 48},
          movers: [{:far, {8.5, 4.5}}, {:near, {6.5, 4.5}}]
        )

      assert @near in colours(raster)
      refute @far in colours(raster)
    end
  end
end
