defmodule Cauldron2D.Parallax.Panorama do
  @moduledoc """
  A layer that is one picture, repeated.

      Cauldron2D.Parallax.Panorama.layer(
        name: :mountains,
        art: :mountains,
        size: {20, 12},
        at: {0, 6},
        wrap: :x,
        factor: {0.2, 0.05}
      )

  `art` is one art of the atlas, `size` is how many tiles it covers, and `at` is where its
  top-left corner sits in the layer's own tiles. `wrap` repeats it along `:x`, `:y`, `:both`
  or `:none`, laying down as many copies as the pane needs.

  Every other option is `Cauldron2D.Parallax.Layer.new/1`'s. The picture is copied into the
  pane rather than drawn tile by tile, so a layer of this kind costs no blending.
  """

  alias Cauldron2D.{Atlas, Surface}
  alias Cauldron2D.Parallax.Layer
  alias FrenchCurve.Raster

  @type wrap :: :x | :y | :both | :none
  @type picture :: %{
          art: term(),
          size: {pos_integer(), pos_integer()},
          wrap: wrap(),
          at: {integer(), integer()}
        }

  @doc "A layer drawing `art` across the pane."
  @spec layer(keyword()) :: Layer.t()
  def layer(opts) do
    {art, opts} = Keyword.pop!(opts, :art)
    {size, opts} = Keyword.pop!(opts, :size)
    {wrap, opts} = Keyword.pop(opts, :wrap, :x)
    {at, opts} = Keyword.pop(opts, :at, {0, 0})

    picture = %{art: art, size: size, wrap: wrap, at: at}

    Layer.new([cell: &clear/1, picture: picture] ++ opts)
  end

  @doc "Where copies of a picture `period` tiles long must sit to cover `extent` from `origin`."
  @spec places(boolean(), integer(), integer(), pos_integer(), integer()) :: [integer()]
  def places(false, _origin, _extent, _period, at), do: [at]

  def places(true, origin, extent, period, at) do
    first = at + (Integer.floor_div(origin - at - period, period) + 1) * period

    first
    |> Stream.iterate(&(&1 + period))
    |> Enum.take_while(&(&1 < origin + extent))
  end

  @doc """
  The picture laid across a pane.

  `origin` is the layer's top-left tile, `target` the pane's pixel size, `tile` the pixels
  a tile covers at this scale, and `void` what fills the pane where no copy reaches.
  """
  @spec render(
          Atlas.t(),
          picture(),
          {integer(), integer()},
          {pos_integer(), pos_integer()},
          pos_integer(),
          pos_integer(),
          integer(),
          :opaque | :transparent
        ) :: Raster.t()
  def render(atlas, picture, {ox, oy}, {width, height}, tile, scale, at, void) do
    {rgba, art_width, art_height} = Surface.sprite_rgba(atlas, picture.art, scale, at)
    {tiles_wide, tiles_tall} = picture.size
    {ax, ay} = picture.at
    blank = blank_pixel(atlas, void)

    columns =
      picture.wrap
      |> wraps?(:x)
      |> places(ox, ceil(width / tile), tiles_wide, ax)
      |> Enum.map(&((&1 - ox) * tile))

    rows =
      picture.wrap
      |> wraps?(:y)
      |> places(oy, ceil(height / tile), tiles_tall, ay)
      |> Enum.map(&((&1 - oy) * tile))

    pixels =
      for y <- 0..(height - 1)//1,
          do: row(rgba, {art_width, art_height}, y, {rows, columns}, width, blank)

    Raster.from_rgba(width, height, IO.iodata_to_binary(pixels))
  end

  defp row(rgba, {art_width, art_height}, y, {rows, columns}, width, blank) do
    case Enum.find(rows, fn top -> y >= top and y < top + art_height end) do
      nil -> :binary.copy(blank, width)
      top -> line(rgba, art_width, y - top, columns, width, blank)
    end
  end

  defp clear(_coordinate), do: :void

  defp wraps?(wrap, axis), do: wrap == :both or wrap == axis

  defp blank_pixel(_atlas, :transparent), do: <<0, 0, 0, 0>>

  defp blank_pixel(atlas, :opaque) do
    {r, g, b} = atlas.void
    <<r, g, b, 255>>
  end

  defp line(rgba, art_width, source_row, columns, width, blank) do
    columns
    |> Enum.flat_map(&segment(&1, art_width, width))
    |> Enum.sort()
    |> assemble(rgba, art_width, source_row, width, blank)
  end

  defp segment(left, art_width, width) do
    from = max(left, 0)
    to = min(left + art_width, width)

    if to > from, do: [{from, from - left, to - from}], else: []
  end

  defp assemble(segments, rgba, art_width, source_row, width, blank) do
    {pieces, cursor} =
      Enum.reduce(segments, {[], 0}, fn {destination, offset, length}, {acc, cursor} ->
        gap = :binary.copy(blank, max(0, destination - cursor))
        slice = binary_part(rgba, (source_row * art_width + offset) * 4, length * 4)

        {[slice, gap | acc], max(cursor, destination + length)}
      end)

    Enum.reverse([:binary.copy(blank, max(0, width - cursor)) | pieces])
  end
end
