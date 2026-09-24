defmodule Cauldron2D.Projection.VolumePaintTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias Cauldron2D.Projection.{FirstPerson, Iso, Mode7, Oblique}
  alias Cauldron2D.Surface
  alias FrenchCurve.Raster

  @tile 8
  @size {64, 48}
  @grey {128, 128, 128, 255}
  @red {255, 0, 0}
  @strength 0.8

  setup_all do
    Atlas.new(:volume_paint_test, tile: @tile, void: {6, 7, 11})
    |> Atlas.put(:ground, Raster.new(@tile, @tile, background: @grey))
    |> Atlas.install()

    :ok
  end

  defp field(_position), do: {:ground, [], nil}

  defp pixels(raster),
    do: for(<<pixel::binary-size(4) <- Raster.to_rgba_binary(raster)>>, do: pixel)

  defp reddest(raster),
    do: raster |> pixels() |> Enum.map(fn <<red, _, _, _>> -> red end) |> Enum.max()

  defp changed(without, with_volume),
    do: Enum.count(Enum.zip(pixels(without), pixels(with_volume)), fn {a, b} -> a != b end)

  defp dome(at), do: %{at: at, shape: {:sphere, 1.5, 0.0}, colour: @red, strength: @strength}

  @doc false
  defp full, do: 128 + (255 - 128) * @strength

  describe "every projection tints by the volume's strength where it is thickest" do
    test "isometric" do
      opts = [focus: {4.5, 4.5}, cell: &field/1, size: @size, facings: 16, facing: 3]
      with_volume = Iso.compose(:volume_paint_test, [{:volumes, [dome({4.5, 4.5})]} | opts])

      assert reddest(Iso.compose(:volume_paint_test, opts)) == 128
      assert reddest(with_volume) > full() * 0.8
    end

    test "oblique" do
      opts = [focus: {4.5, 4.5}, cell: &field/1, size: @size]
      with_volume = Oblique.compose(:volume_paint_test, [{:volumes, [dome({4.5, 4.5})]} | opts])

      assert reddest(Oblique.compose(:volume_paint_test, opts)) == 128
      assert reddest(with_volume) > full() * 0.8
    end

    test "mode 7" do
      opts = [position: {4.5, 4.5}, heading: 0.0, cell: &field/1, size: @size]
      with_volume = Mode7.render(:volume_paint_test, [{:volumes, [dome({7.0, 4.5})]} | opts])

      assert reddest(with_volume) > full() * 0.8
    end

    test "first person" do
      opts = [position: {4.5, 4.5}, heading: 0.0, cell: &field/1, size: @size]

      with_volume =
        FirstPerson.render(:volume_paint_test, [{:volumes, [dome({7.0, 4.5})]} | opts])

      assert reddest(with_volume) > full() * 0.8
    end

    test "top down" do
      rows = for _y <- 1..6, do: for(_x <- 1..8, do: {:ground, [], nil})
      with_volume = Surface.compose(:volume_paint_test, rows, [], volumes: [dome({4.0, 3.0})])

      assert reddest(Surface.compose(:volume_paint_test, rows)) == 128
      assert reddest(with_volume) > full() * 0.7
    end
  end

  describe "where a volume does not stand" do
    test "nothing is touched" do
      opts = [focus: {4.5, 4.5}, cell: &field/1, size: @size, facings: 16, facing: 3]
      without = Iso.compose(:volume_paint_test, opts)
      far = Iso.compose(:volume_paint_test, [{:volumes, [dome({40.0, 40.0})]} | opts])

      assert changed(without, far) == 0
    end
  end

  describe "marking an area out in whole squares" do
    test "tints its tiles evenly and leaves the rest alone" do
      squares = %{
        at: {4.0, 4.0},
        shape: {:cells, MapSet.new([{0, 0}, {1, 0}]), 1.0},
        colour: @red,
        strength: 0.5,
        falloff: :flat
      }

      rows = for _y <- 1..6, do: for(_x <- 1..8, do: {:ground, [], nil})
      painted = Surface.compose(:volume_paint_test, rows, [], volumes: [squares])
      reds = painted |> pixels() |> Enum.filter(fn <<red, _, _, _>> -> red > 128 end)

      assert reds |> Enum.uniq() |> length() == 1
      assert length(reds) == 2 * @tile * @tile
    end
  end
end
