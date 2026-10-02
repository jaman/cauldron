defmodule Linocut.Quantise do
  @moduledoc """
  A picture reduced to a small palette.

      {reduced, palette} = Linocut.Quantise.reduce(raster, 16)

  The palette is chosen by median cut over the picture's opaque pixels and every pixel is
  then moved to its nearest entry. A pixel whose alpha is under the threshold stays clear
  and takes no palette entry.
  """

  alias FrenchCurve.Raster

  @type colour :: {0..255, 0..255, 0..255}

  @sample 40_000

  @doc """
  `raster` with at most `count` colours, and the palette it was given.

  ## Options

    * `:alpha` — the alpha at or above which a pixel counts as opaque. Default `128`
  """
  @spec reduce(Raster.t(), pos_integer(), keyword()) :: {Raster.t(), [colour()]}
  def reduce(%Raster{} = raster, count, opts \\ []) do
    palette = palette(raster, count, opts)
    {to_palette(raster, palette, opts), palette}
  end

  @doc """
  At most `count` colours chosen from `raster`'s opaque pixels, darkest first.

  ## Options

    * `:alpha` — the alpha at or above which a pixel counts as opaque. Default `128`
  """
  @spec palette(Raster.t(), pos_integer(), keyword()) :: [colour()]
  def palette(%Raster{} = raster, count, opts \\ []) do
    alpha = Keyword.get(opts, :alpha, 128)

    raster
    |> opaque_pixels(alpha)
    |> boxes(count)
    |> Enum.map(&centre/1)
    |> Enum.uniq()
    |> Enum.sort_by(fn {r, g, b} -> r + g + b end)
  end

  @doc """
  `raster` with every opaque pixel moved to its nearest entry in `palette`.

  ## Options

    * `:alpha` — the alpha at or above which a pixel counts as opaque. Default `128`
  """
  @spec to_palette(Raster.t(), [colour()], keyword()) :: Raster.t()
  def to_palette(%Raster{} = raster, [], _opts), do: raster

  def to_palette(%Raster{width: width, height: height} = raster, palette, opts) do
    threshold = Keyword.get(opts, :alpha, 128)

    rgba =
      for <<r, g, b, a <- Raster.to_rgba_binary(raster)>>, into: <<>> do
        if a < threshold do
          <<0, 0, 0, 0>>
        else
          {nr, ng, nb} = nearest(palette, {r, g, b})
          <<nr, ng, nb, 255>>
        end
      end

    Raster.from_rgba(width, height, rgba)
  end

  @doc "The entry of `palette` closest to `colour`."
  @spec nearest([colour()], colour()) :: colour()
  def nearest(palette, {r, g, b}) do
    Enum.min_by(palette, fn {pr, pg, pb} ->
      (pr - r) * (pr - r) + (pg - g) * (pg - g) + (pb - b) * (pb - b)
    end)
  end

  defp opaque_pixels(%Raster{} = raster, threshold) do
    binary = Raster.to_rgba_binary(raster)
    total = div(byte_size(binary), 4)
    step = max(1, div(total, @sample))

    for index <- 0..(total - 1)//step,
        <<r, g, b, a>> = binary_part(binary, index * 4, 4),
        a >= threshold,
        do: {r, g, b}
  end

  defp boxes([], _count), do: []

  defp boxes(pixels, count) do
    Enum.reduce_while(1..max(count - 1, 1)//1, [pixels], fn _step, boxes ->
      if length(boxes) >= count, do: {:halt, boxes}, else: widen(boxes)
    end)
  end

  defp widen(boxes) do
    boxes
    |> Enum.sort_by(&spread/1, :desc)
    |> Enum.find_value(fn box ->
      case cut(box) do
        nil -> nil
        {low, high} -> {:cont, [low, high | List.delete(boxes, box)]}
      end
    end)
    |> case do
      nil -> {:halt, boxes}
      split -> split
    end
  end

  defp cut(pixels) do
    case widest(pixels) do
      nil ->
        nil

      channel ->
        sorted = Enum.sort_by(pixels, &elem(&1, channel))

        case Enum.split(sorted, div(length(sorted), 2)) do
          {[], _high} -> nil
          {_low, []} -> nil
          halves -> halves
        end
    end
  end

  defp spread(pixels) do
    {span, _channel} = widths(pixels) |> Enum.max()
    span
  end

  defp widest(pixels) do
    case Enum.max(widths(pixels)) do
      {0, _channel} -> nil
      {_span, channel} -> channel
    end
  end

  defp widths(pixels) do
    for channel <- 0..2 do
      values = Enum.map(pixels, &elem(&1, channel))
      {Enum.max(values) - Enum.min(values), channel}
    end
  end

  defp centre(pixels) do
    count = length(pixels)

    {r, g, b} =
      Enum.reduce(pixels, {0, 0, 0}, fn {r, g, b}, {ar, ag, ab} ->
        {ar + r, ag + g, ab + b}
      end)

    {div(r, count), div(g, count), div(b, count)}
  end
end
