defmodule Cauldron2D.Projection.FirstPersonTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias Cauldron2D.Projection.FirstPerson
  alias FrenchCurve.Raster

  @tile 8
  @grass {40, 160, 40, 255}
  @brick {160, 120, 80, 255}
  @hero {250, 250, 20, 255}
  @side {20, 250, 250, 255}

  setup_all do
    Atlas.new(:fp_test, tile: @tile, void: {6, 7, 11})
    |> Atlas.put(:grass, Raster.new(@tile, @tile, background: @grass))
    |> Atlas.put(:wall, Raster.new(@tile, @tile, background: @brick), height: 1)
    |> Atlas.put(:hero, Raster.new(@tile, @tile, background: @hero),
      poses: %{side: Raster.new(@tile, @tile, background: @side)}
    )
    |> Atlas.install()

    :ok
  end

  defp pixel(raster, x, y) do
    {width, _} = Raster.dimensions(raster)
    <<r, g, b, a>> = binary_part(Raster.to_rgba_binary(raster), (y * width + x) * 4, 4)
    {r, g, b, a}
  end

  defp near?({r1, g1, b1, _}, {r2, g2, b2, _}, tolerance \\ 40),
    do: abs(r1 - r2) <= tolerance and abs(g1 - g2) <= tolerance and abs(b1 - b2) <= tolerance

  defp room({x, _y}) when x == 8, do: {:grass, [:wall], nil}
  defp room({x, y}) when x in 0..7 and y in 0..7, do: {:grass, [], nil}
  defp room(_position), do: :void

  defp view(extra \\ []) do
    FirstPerson.render(
      :fp_test,
      Keyword.merge([position: {4.5, 4.5}, heading: 0.0, cell: &room/1, size: {80, 50}], extra)
    )
  end

  test "the picture is the size asked for, sky at the top, floor at the bottom, wall ahead" do
    raster = view()

    assert Raster.dimensions(raster) == {80, 50}
    refute near?(pixel(raster, 40, 0), @grass)
    assert near?(pixel(raster, 40, 49), @grass)
    assert near?(pixel(raster, 40, 25), @brick, 60)
  end

  test "turning away from the wall shows the floor stretching to the void" do
    raster = view(heading: :math.pi())

    refute near?(pixel(raster, 40, 25), @brick, 30)
    assert near?(pixel(raster, 40, 49), @grass)
  end

  test "pitching down brings the floor up the picture" do
    level = view()
    down = view(pitch: -0.8)

    assert near?(pixel(down, 40, 5), @grass, 60) or near?(pixel(down, 40, 5), @brick, 60)
    refute near?(pixel(level, 40, 5), @grass, 60)
  end

  test "a mover across the way is a billboard in the pose its heading gives" do
    across = view(movers: [{:hero, {6.5, 4.5}, :math.pi() / 2}])
    towards = view(movers: [{:hero, {6.5, 4.5}, :math.pi()}])

    assert Enum.any?(0..49, &near?(pixel(across, 40, &1), @side, 20))
    assert Enum.any?(0..49, &near?(pixel(towards, 40, &1), @hero, 20))
  end

  test "a narrower aspect makes walls taller for the same width" do
    square = view(aspect: 1.0)
    tall = view(aspect: 0.5)

    wall_rows = fn raster -> Enum.count(0..49, &near?(pixel(raster, 40, &1), @brick, 60)) end
    assert wall_rows.(tall) > wall_rows.(square)
  end
end
