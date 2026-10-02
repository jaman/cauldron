defmodule Linocut.Frames do
  @moduledoc """
  Frames of one animation, lined up and written as a `.pic`.

  `align/2` puts a set of pictures on one canvas, each standing on the same floor and
  lined up by the body above it rather than by its own box, so a stride that reaches wide
  does not shift the whole figure sideways. `to_pic/3` reduces them to one shared palette
  and gives the `.pic` text.
  """

  alias FrenchCurve.Raster
  alias Linocut.Quantise

  @keys ~c"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

  @doc """
  Every picture cropped to what it holds and placed on one canvas.

  ## Options

    * `:alpha` — the alpha at or above which a pixel counts. Default `16`
    * `:anchor` — the fraction of a picture's height, from the top, whose middle the
      pictures are lined up by. Default `0.35`, which is the head and chest of a figure
  """
  @spec align([Raster.t()], keyword()) :: [Raster.t()]
  def align(rasters, opts \\ [])

  def align([], _opts), do: []

  def align(rasters, opts) do
    alpha = Keyword.get(opts, :alpha, 16)
    anchor = Keyword.get(opts, :anchor, 0.35)
    boxes = Enum.map(rasters, &box(&1, alpha))
    cropped = Enum.zip_with(rasters, boxes, &crop/2)
    widest = cropped |> Enum.map(& &1.width) |> Enum.max()
    tallest = cropped |> Enum.map(& &1.height) |> Enum.max()
    middles = Enum.map(cropped, &middle(&1, anchor, alpha))

    Enum.zip_with(cropped, middles, fn raster, middle ->
      place(raster, round(widest / 2 - middle), tallest - raster.height, {widest, tallest})
    end)
  end

  @doc """
  The `.pic` text for `frames`, all reduced to one palette of at most `colours` entries.

  A pixel whose alpha is under `alpha` is written as a clear cell.
  """
  @spec to_pic([Raster.t()], pos_integer(), non_neg_integer()) :: String.t()
  def to_pic(frames, colours, alpha) do
    palette = palette(frames, colours, alpha)
    reduced = Enum.map(frames, &Quantise.to_palette(&1, palette, alpha: alpha))
    keys = palette |> Enum.zip(@keys) |> Map.new(fn {colour, key} -> {colour, <<key>>} end)

    Linocut.Pic.write(%{
      palette: Enum.map(palette, fn colour -> {Map.fetch!(keys, colour), hex(colour)} end),
      frames: Enum.map(reduced, &rows(&1, keys, alpha))
    })
  end

  defp palette(frames, colours, alpha) do
    {width, height} = Raster.dimensions(hd(frames))

    frames
    |> Enum.map(&Raster.to_rgba_binary/1)
    |> IO.iodata_to_binary()
    |> then(&Raster.from_rgba(width, height * length(frames), &1))
    |> Quantise.palette(colours, alpha: alpha)
  end

  defp box(%Raster{width: width, height: height} = raster, alpha) do
    binary = Raster.to_rgba_binary(raster)

    held =
      for y <- 0..(height - 1)//1,
          x <- 0..(width - 1)//1,
          opaque?(binary, y * width + x, alpha),
          do: {x, y}

    case held do
      [] -> {0, 0, width, height}
      points -> span(points)
    end
  end

  defp span(points) do
    xs = Enum.map(points, &elem(&1, 0))
    ys = Enum.map(points, &elem(&1, 1))
    {left, right} = Enum.min_max(xs)
    {top, bottom} = Enum.min_max(ys)

    {left, top, right - left + 1, bottom - top + 1}
  end

  defp crop(raster, {left, top, width, height}),
    do: Raster.crop(raster, {left, top}, {width, height})

  defp middle(%Raster{width: width} = raster, anchor, alpha) do
    binary = Raster.to_rgba_binary(raster)
    rows = max(1, round(raster.height * anchor))

    held =
      for y <- 0..(rows - 1)//1,
          x <- 0..(width - 1)//1,
          opaque?(binary, y * width + x, alpha),
          do: x

    case held do
      [] -> width / 2
      xs -> Enum.sum(xs) / length(xs)
    end
  end

  defp place(%Raster{width: width, height: height} = raster, left, top, {widest, tallest}) do
    for y <- 0..(height - 1)//1, x <- 0..(width - 1)//1, reduce: Raster.new(widest, tallest) do
      canvas ->
        {px, py} = {left + x, top + y}

        if px >= 0 and px < widest and py >= 0 and py < tallest,
          do: Raster.put_pixel(canvas, px, py, Raster.get_pixel(raster, x, y)),
          else: canvas
    end
  end

  defp rows(%Raster{width: width} = raster, keys, alpha) do
    raster
    |> Raster.to_rgba_binary()
    |> then(&for(<<pixel::binary-size(4) <- &1>>, do: pixel))
    |> Enum.chunk_every(width)
    |> Enum.map(fn row -> Enum.map_join(row, &character(&1, keys, alpha)) end)
  end

  defp character(<<_r, _g, _b, a>>, _keys, alpha) when a < alpha, do: "."
  defp character(<<r, g, b, _a>>, keys, _alpha), do: Map.fetch!(keys, {r, g, b})

  defp hex({r, g, b}), do: "#" <> Base.encode16(<<r, g, b>>, case: :lower)

  defp opaque?(binary, index, alpha) do
    <<_r, _g, _b, a>> = binary_part(binary, index * 4, 4)
    a >= alpha
  end
end
