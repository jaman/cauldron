defmodule Cauldron2D.Projection.ObliqueTurnTest do
  @moduledoc """
  The quarter turns the oblique view can be drawn at, which leave its grid square on the
  screen and so need no resampling.
  """

  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias Cauldron2D.Projection.Oblique
  alias FrenchCurve.Raster

  @tile 8
  @size {160, 96}

  setup_all do
    Atlas.new(:oblique_turn, tile: @tile, void: {6, 7, 11})
    |> Atlas.put(:grass, Raster.new(@tile, @tile, background: {40, 160, 40, 255}))
    |> Atlas.put(:wall, Raster.new(@tile, @tile, background: {160, 120, 80, 255}), height: 1)
    |> Atlas.put(:hero, Raster.new(@tile, @tile, background: {250, 250, 20, 255}),
      poses: %{
        front: Raster.new(@tile, @tile, background: {250, 250, 20, 255}),
        back: Raster.new(@tile, @tile, background: {20, 20, 250, 255}),
        side: Raster.new(@tile, @tile, background: {250, 20, 20, 255})
      }
    )
    |> Atlas.install()

    :ok
  end

  defp town({x, y}) when x > y, do: {:grass, [:wall], nil}
  defp town(_position), do: {:grass, [], nil}

  defp opts(extra \\ []),
    do: Keyword.merge([focus: {4.0, 6.0}, cell: &town/1, size: @size, squash: 0.5], extra)

  defp pixels(raster), do: Raster.to_rgba_binary(raster)

  test "a view asked for no facings is drawn as it always was, whatever facing is passed" do
    plain = Oblique.compose(:oblique_turn, opts())

    for facing <- 0..3 do
      assert pixels(Oblique.compose(:oblique_turn, opts(facing: facing))) == pixels(plain)
    end
  end

  test "at four facings a quarter turn draws a different picture" do
    straight = Oblique.compose(:oblique_turn, opts(facings: 4, facing: 0))
    turned = Oblique.compose(:oblique_turn, opts(facings: 4, facing: 1))

    refute pixels(straight) == pixels(turned)
  end

  test "four quarter turns come back to where they started" do
    straight = Oblique.compose(:oblique_turn, opts(facings: 4, facing: 0))
    round = Oblique.compose(:oblique_turn, opts(facings: 4, facing: 4))

    assert pixels(round) == pixels(straight)
  end

  test "a pixel maps back to the world it was drawn from at every facing" do
    for facing <- 0..3, px <- [0, 37, 159], py <- [0, 23, 95] do
      settings = opts(facings: 4, facing: facing)
      {wx, wy} = Oblique.unproject(:oblique_turn, {px, py}, settings)
      {bx, by} = Oblique.project(:oblique_turn, {wx, wy}, settings)

      assert_in_delta bx, px, 0.000001
      assert_in_delta by, py, 0.000001
    end
  end

  test "the ground map walks to the same points unproject answers at every facing" do
    for facing <- 0..3 do
      settings = opts(facings: 4, facing: facing)
      {{ox, oy}, {rx, ry}, {dx, dy}} = Oblique.ground_map(:oblique_turn, settings)

      for px <- [0, 37, 159], py <- [0, 23, 95] do
        {ux, uy} = Oblique.unproject(:oblique_turn, {px, py}, settings)

        assert_in_delta ox + px * rx + py * dx, ux, 0.000001
        assert_in_delta oy + px * ry + py * dy, uy, 0.000001
      end
    end
  end

  test "the focus stays at the middle of the picture at every facing" do
    {cx, cy} = {80.0, 48.0}

    for facing <- 0..3 do
      settings = opts(facings: 4, facing: facing)

      assert Oblique.project(:oblique_turn, {4.0, 6.0}, settings) == {cx, cy}
    end
  end

  test "a quarter turn moves a world point a quarter of the way round the focus" do
    settings = opts(facings: 4, facing: 1)
    {cx, cy} = {80.0, 48.0}

    assert {px, py} = Oblique.project(:oblique_turn, {5.0, 6.0}, settings)
    assert_in_delta px - cx, 0.0, 0.000001
    assert py < cy
  end

  test "the cells shown change with the facing" do
    straight = Oblique.cells(:oblique_turn, opts(facings: 4, facing: 0))
    turned = Oblique.cells(:oblique_turn, opts(facings: 4, facing: 1))

    refute MapSet.new(straight) == MapSet.new(turned)
  end

  test "a mover keeps facing the viewer as the view turns under it" do
    walking = [{:hero, {4.0, 6.0}, 0.0}]

    poses =
      for facing <- 0..3 do
        Oblique.compose(:oblique_turn, opts(facings: 4, facing: facing, movers: walking))
        |> pixels()
      end

    assert length(Enum.uniq(poses)) > 1
  end
end
