defmodule Cauldron2D.Projection.IsoStampingTest do
  @moduledoc """
  A standing art is stamped with the faces that turn towards the camera, and which faces
  those are is recomputed at every facing of a turn.
  """

  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias Cauldron2D.Projection.Iso
  alias FrenchCurve.Raster

  @tile 16
  @void {255, 0, 255}
  @grass {40, 160, 40, 255}
  @roof {200, 40, 40, 255}

  setup_all do
    Atlas.new(:stamping_test, tile: @tile, void: @void)
    |> Atlas.put(:grass, Raster.new(@tile, @tile, background: @grass))
    |> Atlas.put(:wall, Raster.new(@tile, @tile, background: {160, 120, 80, 255}),
      height: 2,
      faces: %{top: Raster.new(@tile, @tile, background: @roof)}
    )
    |> Atlas.install()

    :ok
  end

  defp field(_position), do: {:grass, [], nil}

  defp walled({13, 9}), do: {:grass, [:wall], nil}
  defp walled(position), do: field(position)

  defp drawn(opts),
    do:
      Iso.compose(
        :stamping_test,
        Keyword.merge([focus: {12.37, 8.61}, cell: &field/1, size: {160, 96}], opts)
      )

  test "a standing art keeps its roof and a shaded side at every facing" do
    for facings <- [8, 16, 32], facing <- 0..(facings - 1) do
      raster = drawn(facings: facings, facing: facing, cell: &walled/1)
      seen = for <<r, g, b, a <- Raster.to_rgba_binary(raster)>>, uniq: true, do: {r, g, b, a}

      assert @roof in seen, "facings #{facings}, facing #{facing} drew no roof"

      assert Enum.any?(seen, fn {r, g, b, _} -> r < 160 and g < 120 and b < 80 and r > 60 end),
             "facings #{facings}, facing #{facing} drew no shaded side"
    end
  end
end
