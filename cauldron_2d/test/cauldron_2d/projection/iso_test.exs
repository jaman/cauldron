defmodule Cauldron2D.Projection.IsoTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias Cauldron2D.Projection.Iso
  alias FrenchCurve.Raster

  @tile 8
  @grass {40, 160, 40, 255}
  @roof {200, 40, 40, 255}
  @brick {160, 120, 80, 255}
  @hero {250, 250, 20, 255}
  @back {20, 20, 250, 255}

  setup_all do
    Atlas.new(:iso_test, tile: @tile, void: {6, 7, 11})
    |> Atlas.put(:grass, Raster.new(@tile, @tile, background: @grass))
    |> Atlas.put(:house, Raster.new(@tile, @tile, background: @brick),
      height: 2,
      faces: %{top: Raster.new(@tile, @tile, background: @roof)}
    )
    |> Atlas.put(:hero, Raster.new(@tile, @tile, background: @hero),
      poses: %{back: Raster.new(@tile, @tile, background: @back)}
    )
    |> Atlas.install()

    :ok
  end

  defp colours(raster) do
    for <<r, g, b, a <- Raster.to_rgba_binary(raster)>>, uniq: true, do: {r, g, b, a}
  end

  defp count(raster, colour) do
    Enum.count(
      for(<<r, g, b, a <- Raster.to_rgba_binary(raster)>>, do: {r, g, b, a}),
      &(&1 == colour)
    )
  end

  defp field(_position), do: {:grass, [], nil}

  defp town({3, 3}), do: {:grass, [:house], nil}
  defp town(position), do: field(position)

  test "the raster is the size asked for, floored with the tiles and the void beyond them" do
    raster = Iso.compose(:iso_test, focus: {5.5, 5.5}, cell: &field/1, size: {64, 40})

    assert Raster.dimensions(raster) == {64, 40}
    assert @grass in colours(raster)
    refute {6, 7, 11, 255} in colours(raster)

    bounded = fn {x, y} -> if x in 4..6 and y in 4..6, do: {:grass, [], nil}, else: :void end
    edged = Iso.compose(:iso_test, focus: {5.5, 5.5}, cell: bounded, size: {64, 40})
    assert {6, 7, 11, 255} in colours(edged)
  end

  test "a standing art shows its roof and its shaded sides above the floor" do
    raster = Iso.compose(:iso_test, focus: {3.5, 3.5}, cell: &town/1, size: {64, 48})
    seen = colours(raster)

    assert @roof in seen
    assert Enum.any?(seen, fn {r, g, b, _} -> r < 160 and g < 120 and b < 80 and r > 60 end)
    refute @brick in seen
  end

  test "turning the view puts the house on the other side of the focus" do
    left = fn facing ->
      raster =
        Iso.compose(:iso_test, focus: {3.5, 5.5}, cell: &town/1, size: {64, 48}, facing: facing)

      {width, _} = Raster.dimensions(raster)
      pixels = for <<r, g, b, a <- Raster.to_rgba_binary(raster)>>, do: {r, g, b, a}

      pixels
      |> Enum.with_index()
      |> Enum.filter(fn {pixel, _} -> pixel == @roof end)
      |> Enum.map(fn {_, index} -> rem(index, width) end)
      |> then(&(Enum.sum(&1) / max(length(&1), 1)))
    end

    assert left.(0) > 32
    assert left.(2) < 32
  end

  test "a taller tilt makes the floor diamond taller" do
    flat = Iso.compose(:iso_test, focus: {3.5, 3.5}, cell: &town/1, size: {64, 48}, tilt: 0.5)
    steep = Iso.compose(:iso_test, focus: {3.5, 3.5}, cell: &town/1, size: {64, 48}, tilt: 1.5)

    assert count(steep, @roof) > count(flat, @roof)
  end

  test "a mover is drawn in the pose its heading gives, mirrored for the other way" do
    facing_camera =
      Iso.compose(:iso_test,
        focus: {5.5, 5.5},
        cell: &field/1,
        size: {64, 40},
        movers: [{:hero, {5.5, 5.5}, :math.pi() / 4}]
      )

    facing_away =
      Iso.compose(:iso_test,
        focus: {5.5, 5.5},
        cell: &field/1,
        size: {64, 40},
        movers: [{:hero, {5.5, 5.5}, -3 * :math.pi() / 4}]
      )

    assert @hero in colours(facing_camera)
    assert @back in colours(facing_away)
    refute @back in colours(facing_camera)
  end

  test "a mover with no heading faces the camera" do
    raster =
      Iso.compose(:iso_test,
        focus: {5.5, 5.5},
        cell: &field/1,
        size: {64, 40},
        movers: [{:hero, {5.5, 5.5}}]
      )

    assert @hero in colours(raster)
  end

  test "shrinking draws the same scene smaller, so the pane shows more of it" do
    close = Iso.compose(:iso_test, focus: {3.5, 3.5}, cell: &town/1, size: {64, 48}, shrink: 1)
    far = Iso.compose(:iso_test, focus: {3.5, 3.5}, cell: &town/1, size: {64, 48}, shrink: 2)

    assert count(far, @roof) < count(close, @roof)
    assert count(far, @roof) > 0
  end

  test "a label is drawn at its tile" do
    raster =
      Iso.compose(:iso_test,
        focus: {5.5, 5.5},
        cell: &field/1,
        size: {64, 40},
        labels: [{"HI", {5.5, 5.5}, {255, 255, 255}}]
      )

    assert {255, 255, 255, 255} in colours(raster)
  end

  test "where a screen pixel lands in the world, and back" do
    opts = [focus: {5.5, 5.5}, size: {64, 40}, facing: 1]
    {px, py} = Iso.project(:iso_test, {7.0, 5.0}, opts)
    {wx, wy} = Iso.unproject(:iso_test, {px, py}, opts)

    assert_in_delta wx, 7.0, 0.1
    assert_in_delta wy, 5.0, 0.1
    assert Iso.tile_at(:iso_test, {px, py}, opts) == {7, 5}
  end
end
