defmodule Cauldron2D.SurfaceLabelsTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.{Atlas, Surface}
  alias FrenchCurve.Raster

  @tile 8

  setup_all do
    Atlas.new(:surface_labels, tile: @tile, void: {0, 0, 0})
    |> Atlas.put(:floor, Raster.new(@tile, @tile, background: {10, 10, 10, 255}))
    |> Atlas.install()

    :ok
  end

  defp pixel(raster, x, y), do: binary_part(raster.rgba, (y * raster.width + x) * 4, 4)

  test "a label is drawn in its colour over the grid and the movers, clipped at the edges" do
    rows = [[{:floor, [], nil}, {:floor, [], nil}]]
    raster = Surface.compose(:surface_labels, rows, [], labels: [{"I", {2, 1}, {255, 255, 0}}])
    assert pixel(raster, 3, 1) == <<255, 255, 0, 255>>
    assert pixel(raster, 2, 2) == <<10, 10, 10, 255>>
    assert pixel(raster, 3, 6) == <<10, 10, 10, 255>>

    clipped = Surface.compose(:surface_labels, rows, [], labels: [{"II", {14, 0}, {0, 255, 0}}])
    assert clipped.width == 16
    assert pixel(clipped, 15, 0) == <<0, 255, 0, 255>>

    scaled =
      Surface.compose(:surface_labels, rows, [], labels: [{"I", {0, 0}, {0, 0, 255}, scale: 2}])

    assert pixel(scaled, 2, 7) == <<0, 0, 255, 255>>
    assert pixel(scaled, 0, 7) == <<10, 10, 10, 255>>
  end

  test "labels take a background and a scale" do
    raster =
      Surface.compose(:surface_labels, [[{:floor, [], nil}]], [],
        labels: [{"A", {0, 0}, {255, 255, 255}, background: {0, 0, 0}}]
      )

    assert pixel(raster, 0, 0) == <<0, 0, 0, 255>>
  end
end
