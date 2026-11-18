defmodule Cauldron2D.ScreenTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.{Atlas, Screen}
  alias FrenchCurve.Raster

  @red {255, 0, 0, 255}

  setup do
    square =
      for(
        x <- 0..3,
        y <- 0..3,
        reduce: Raster.new(4, 4),
        do: (r -> Raster.put_pixel(r, x, y, @red))
      )

    sheet =
      for(
        x <- 0..1,
        y <- 0..2,
        reduce: Raster.new(3, 3),
        do: (r -> Raster.put_pixel(r, x, y, @red))
      )

    font = Linocut.BitmapFont.from_sheet(sheet, {3, 3}, "A")

    name =
      Atlas.new(:"screen_test_#{System.unique_integer([:positive])}", tile: 4)
      |> Atlas.put(:square, square)
      |> Atlas.put_font(:tiny, font)
      |> Atlas.install()

    %{atlas: name}
  end

  defp lit(raster) do
    rgba = Raster.to_rgba_binary(raster)

    for y <- 0..(raster.height - 1),
        x <- 0..(raster.width - 1),
        :binary.at(rgba, (y * raster.width + x) * 4 + 3) > 0,
        do: {x, y}
  end

  test "an anchor measures from that point of the pane and places that point of the item", %{
    atlas: atlas
  } do
    raster = Screen.compose(atlas, [{:art, :square, {-1, -2}, anchor: :bottom_right}], {10, 10})
    assert Enum.min(lit(raster)) == {5, 4}
    assert Enum.max(lit(raster)) == {8, 7}
  end

  test "a bar shows its fraction of the art", %{atlas: atlas} do
    raster = Screen.compose(atlas, [{:bar, :square, {0, 0}, 0.5}], {8, 8})
    assert lit(raster) |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort() == [0, 1]
  end

  test "centred text in a colour covers its glyph's pixels", %{atlas: atlas} do
    raster =
      Screen.compose(
        atlas,
        [{:text, :tiny, "A", {0, 0}, anchor: :centre, colour: {0, 255, 0}}],
        {6, 6}
      )

    assert lit(raster) ==
             for(y <- 1..3, x <- 2..3, do: {x, y}) |> Enum.sort_by(&{elem(&1, 1), elem(&1, 0)})

    assert Raster.get_pixel(raster, 2, 1) == {0, 255, 0, 255}
  end
end
