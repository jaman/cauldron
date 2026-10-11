defmodule Cauldron2D.Sectors.Light do
  @moduledoc """
  Light as table lookups: a ramp of light tables built from a palette, and which table a
  surface at some light level and distance is drawn through.

      tables = Light.tables(palette)
      Light.table(160, 384.0)

  A light table maps a colour index to the index of that colour darkened, so lighting a
  picture costs one lookup a pixel whatever the light. `tables/2` builds `maps` of them,
  table `0` the palette as it is and each further table darker, the last nearly black.
  A game may instead bring its own tables made for its palette.

  A surface's light level is `0..255`. `start/2` turns it into the table it is drawn
  through close up, and `table/3` moves that table brighter or darker with distance:
  `start - floor(fade / distance)`, clamped to the tables, so nearer is brighter and a
  surface fades by its light level's own amount as it recedes.

  ## Options

    * `:maps` — how many tables the ramp has. Default `32`
    * `:levels` — how many steps the `0..255` light level is cut into. Default `16`
    * `:fade` — how strongly distance darkens, in world units. Default `1280.0`
  """

  @type option :: {:maps, pos_integer()} | {:levels, pos_integer()} | {:fade, number()}

  @doc """
  `maps` light tables for a 768-byte `palette`, darkening towards black: table `n` holds
  for each colour the palette entry nearest that colour scaled by `(maps - n) / maps`.
  """
  @spec tables(binary(), [option()]) :: binary()
  def tables(palette, opts \\ []) when byte_size(palette) == 768 do
    maps = Keyword.get(opts, :maps, 32)
    colours = for <<r, g, b <- palette>>, do: {r, g, b}
    indexed = Enum.with_index(colours)

    for map <- 0..(maps - 1), {r, g, b} <- colours, into: <<>> do
      share = (maps - map) / maps
      <<nearest(indexed, {r * share, g * share, b * share})>>
    end
  end

  defp nearest(indexed, {r, g, b}) do
    indexed
    |> Enum.min_by(fn {{pr, pg, pb}, _index} ->
      (pr - r) * (pr - r) + (pg - g) * (pg - g) + (pb - b) * (pb - b)
    end)
    |> elem(1)
  end

  @doc "The table a surface at `light` (`0..255`) is drawn through close up."
  @spec start(integer(), [option()]) :: integer()
  def start(light, opts \\ []) do
    maps = Keyword.get(opts, :maps, 32)
    levels = Keyword.get(opts, :levels, 16)
    bucket = light |> div(div(256, levels)) |> max(0) |> min(levels - 1)
    div((levels - 1 - bucket) * 2 * maps, levels)
  end

  @doc "The table a surface at `light` is drawn through from `distance` away."
  @spec table(integer(), number(), [option()]) :: non_neg_integer()
  def table(light, distance, opts \\ []) do
    maps = Keyword.get(opts, :maps, 32)
    fade = Keyword.get(opts, :fade, 1280.0)

    (start(light, opts) - floor(fade / max(distance, 1.0)))
    |> max(0)
    |> min(maps - 1)
  end
end
