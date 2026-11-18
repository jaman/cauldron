defmodule Megablast.Art do
  @moduledoc """
  The game's pictures in the atlas `:megablast`, from `priv/art`: what the image model
  drew and `mix cauldron.assets` finished — the ship, the creatures, the turrets, the
  guardian and the five bosses with their parts, the trader, the stage backdrops and
  rock, the title painting — the hand-drawn bullets, shots, bubbles, blasts, bars, frame
  and cursor, and the font `:pixel`.

  Some pictures are made from others as the atlas is installed:

    * `ship_bank_<n>`, `n` from `-2` to `2` — the ship squashed across as it rolls
    * `<rock>_<n>`, `n` from `0` to `15` — sixteen wall tiles cut from a stage's rock
    * `<backdrop>_tile` — a stage's backdrop above its own mirror image, so it repeats
      up the lane without a seam

  Two tints shade a mover: `:flash`, a struck thing's white, and `:hurt`, a hit ship's red.
  """

  alias Cauldron2D.Atlas
  alias Cauldron2D.Raster

  @name :megablast
  @tile 16
  @banks [{-2, 0.55}, {-1, 0.8}, {0, 1.0}, {1, 0.8}, {2, 0.55}]
  @rocks for n <- 1..5, do: :"rock_#{n}"
  @backdrops for n <- 1..5, do: :"deep_#{n}"

  @doc "The atlas name."
  @spec name() :: Atlas.name()
  def name, do: @name

  @doc "The art directory."
  @spec dir() :: Path.t()
  def dir, do: Path.join(:code.priv_dir(:megablast), "art")

  @doc "Load the directory, make the derived pictures, and install the atlas, once; returns its name."
  @spec install() :: Atlas.name()
  def install do
    if Atlas.installed?(@name) do
      @name
    else
      {:ok, atlas} =
        Atlas.load(@name, dir(),
          tile: @tile,
          void: {6, 4, 16},
          fonts: [pixel: [file: "font.png", cell: {8, 8}, chars: chars(), space: 3]]
        )

      atlas
      |> banks()
      |> rocks()
      |> backdrops()
      |> Atlas.tint(:flash, &flash/1)
      |> Atlas.tint(:hurt, &hurt/1)
      |> Atlas.install()
    end
  end

  @doc "The art of the ship rolled `bank` steps, `-2..2`."
  @spec ship(integer()) :: atom()
  def ship(bank), do: :"ship_bank_#{bank}"

  defp chars, do: " !%'()*+,-./0123456789:<>?ABCDEFGHIJKLMNOPQRSTUVWXYZ_x"

  defp picture(atlas, art),
    do: atlas |> Atlas.entry(art) |> Map.fetch!(:sprite) |> Map.fetch!(:raster)

  defp present?(atlas, art), do: Map.has_key?(atlas.entries, art)

  defp banks(atlas) do
    if present?(atlas, :ship) do
      ship = picture(atlas, :ship)

      Enum.reduce(@banks, atlas, fn {bank, across}, acc ->
        Atlas.put(acc, ship(bank), Cauldron2D.Picture.squash(ship, {across, 1.0}),
          glyph: "^ ",
          color: {200, 220, 255}
        )
      end)
    else
      atlas
    end
  end

  defp rocks(atlas) do
    Enum.reduce(@rocks, atlas, fn rock, acc ->
      if present?(acc, rock), do: cut(acc, rock, picture(acc, rock)), else: acc
    end)
  end

  defp cut(atlas, rock, raster) do
    for n <- 0..15, reduce: atlas do
      acc ->
        tile = Raster.crop(raster, {rem(n, 4) * @tile, div(n, 4) * @tile}, {@tile, @tile})
        Atlas.put(acc, :"#{rock}_#{n}", tile, glyph: "##", color: Atlas.entry(acc, rock).color)
    end
  end

  defp backdrops(atlas) do
    Enum.reduce(@backdrops, atlas, fn backdrop, acc ->
      if present?(acc, backdrop),
        do: Atlas.put(acc, :"#{backdrop}_tile", mirrored(picture(acc, backdrop)), glyph: "  "),
        else: acc
    end)
  end

  defp mirrored(%{width: width, height: height} = raster) do
    below = Cauldron2D.Picture.flip(raster, :vertical)

    Raster.from_rgba(
      width,
      height * 2,
      Raster.to_rgba_binary(raster) <> Raster.to_rgba_binary(below)
    )
  end

  defp flash({r, g, b, a}), do: {div(r + 255 * 3, 4), div(g + 255 * 3, 4), div(b + 255 * 3, 4), a}
  defp hurt({r, g, b, a}), do: {min(255, r + 120), div(g, 2), div(b, 2), a}
end
