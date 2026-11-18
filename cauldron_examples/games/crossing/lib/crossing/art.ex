defmodule Crossing.Art do
  @moduledoc """
  The board's tiles, drawn in code and installed into a `Cauldron2D.Atlas`.

  Each entry is a 16-pixel raster for a terminal with pixels and a two-cell glyph for a
  terminal without them, so the same game plays in both. Nothing here is an image file:
  the grass, the water, a log, a cart and the frog are a handful of rectangles and
  circles, and `install/0` is called on every mount because installing is idempotent.
  """

  alias Cauldron2D.Atlas
  alias FrenchCurve.{Draw, Raster}

  @tile 16
  @name :crossing
  @void {16, 22, 20}

  @catalogue [
    {:grass, "░░", {84, 138, 78}},
    {:water, "≈≈", {58, 108, 168}},
    {:road, "▓▓", {62, 64, 74}},
    {:log, "▬▬", {150, 104, 62}},
    {:cart, "▛▜", {206, 76, 84}},
    {:frog, "♞ ", {132, 214, 96}},
    {:bank, "██", {204, 190, 120}}
  ]

  @doc "The atlas name everything else refers to."
  @spec name() :: atom()
  def name, do: @name

  @doc "Draw the catalogue and install it, returning the atlas name."
  @spec install() :: atom()
  def install do
    if Atlas.installed?(@name) do
      @name
    else
      Enum.reduce(@catalogue, Atlas.new(@name, tile: @tile, void: @void), fn {art, glyph, colour},
                                                                             atlas ->
        Atlas.put(atlas, art, raster(art), glyph: glyph, color: colour)
      end)
      |> Atlas.install()
    end
  end

  defp raster(:grass) do
    {88, 142, 80, 255}
    |> tile()
    |> Draw.fill_rect({2, 4}, {3, 6}, {104, 158, 92, 255})
    |> Draw.fill_rect({9, 10}, {10, 12}, {104, 158, 92, 255})
  end

  defp raster(:water) do
    {54, 104, 166, 255}
    |> tile()
    |> Draw.fill_rect({0, 5}, {15, 6}, {74, 128, 190, 255})
    |> Draw.fill_rect({4, 11}, {15, 12}, {74, 128, 190, 255})
  end

  defp raster(:road) do
    {60, 62, 72, 255}
    |> tile()
    |> Draw.fill_rect({0, 7}, {15, 8}, {96, 98, 112, 255})
  end

  defp raster(:log) do
    {146, 100, 60, 255}
    |> tile()
    |> Draw.fill_rect({0, 3}, {15, 12}, {158, 110, 66, 255})
    |> Draw.fill_circle({3, 8}, 2, {122, 82, 48, 255})
    |> Draw.fill_circle({12, 8}, 2, {122, 82, 48, 255})
  end

  defp raster(:cart) do
    {196, 70, 80, 255}
    |> tile()
    |> Draw.fill_rect({0, 4}, {15, 12}, {212, 84, 92, 255})
    |> Draw.fill_circle({4, 13}, 2, {40, 40, 48, 255})
    |> Draw.fill_circle({11, 13}, 2, {40, 40, 48, 255})
    |> Draw.fill_rect({3, 6}, {7, 7}, {126, 208, 232, 255})
    |> Draw.fill_rect({9, 6}, {12, 7}, {126, 208, 232, 255})
  end

  defp raster(:frog) do
    {0, 0, 0, 0}
    |> tile()
    |> Draw.fill_circle({8, 9}, 6, {126, 206, 92, 255})
    |> Draw.fill_circle({5, 5}, 2, {166, 232, 130, 255})
    |> Draw.fill_circle({11, 5}, 2, {166, 232, 130, 255})
    |> Draw.fill_circle({5, 5}, 1, {24, 32, 24, 255})
    |> Draw.fill_circle({11, 5}, 1, {24, 32, 24, 255})
  end

  defp raster(:bank) do
    {206, 192, 122, 255}
    |> tile()
    |> Draw.fill_rect({0, 12}, {15, 15}, {176, 162, 96, 255})
    |> Draw.fill_circle({8, 6}, 4, {232, 214, 150, 255})
  end

  defp tile(colour), do: Raster.new(@tile, @tile, background: colour)
end
