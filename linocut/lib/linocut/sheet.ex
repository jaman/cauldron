defmodule Linocut.Sheet do
  @moduledoc """
  A sprite sheet cut into frames.

      Linocut.Sheet.cut(raster, band: 0, gap: 6)

  The sheet's background must already be clear. Rows of frames are found as bands of
  pixels separated by blank rows, and frames within a band as runs of columns separated by
  blank columns. Every frame comes back the same size, each centred across and standing on
  the band's own floor, so a walk cycle keeps its feet on one line.
  """

  alias FrenchCurve.Raster

  @type box :: {integer(), integer(), pos_integer(), pos_integer()}

  @doc """
  The frames of `raster`, left to right.

  ## Options

    * `:band` — which row of frames to cut, counting from the top. Default `0`
    * `:gap` — how many blank columns or rows separate one frame or row from the next.
      Default `6`
    * `:alpha` — the alpha at or above which a pixel counts. Default `16`
  """
  @spec cut(Raster.t(), keyword()) :: [Raster.t()]
  def cut(%Raster{} = raster, opts \\ []) do
    gap = Keyword.get(opts, :gap, 6)
    alpha = Keyword.get(opts, :alpha, 16)
    wanted = Keyword.get(opts, :band, 0)

    case raster |> rows(alpha) |> runs(gap) |> Enum.at(wanted) do
      nil -> []
      band -> frames(raster, band, gap, alpha)
    end
  end

  @doc """
  Every band's frames, top band first, all padded to one size.

  Takes `cut/2`'s `:gap` and `:alpha`.
  """
  @spec cut_all(Raster.t(), keyword()) :: [Raster.t()]
  def cut_all(%Raster{} = raster, opts \\ []) do
    gap = Keyword.get(opts, :gap, 6)
    alpha = Keyword.get(opts, :alpha, 16)

    raster
    |> rows(alpha)
    |> runs(gap)
    |> Enum.flat_map(&frames(raster, &1, gap, alpha))
    |> levelled()
  end

  @doc "The rows of `raster` holding any pixel, as `{row, holds?}`."
  @spec rows(Raster.t(), non_neg_integer()) :: [boolean()]
  def rows(%Raster{width: width, height: height} = raster, alpha) do
    binary = Raster.to_rgba_binary(raster)

    for y <- 0..(height - 1)//1 do
      Enum.any?(0..(width - 1)//1, fn x -> opaque?(binary, y * width + x, alpha) end)
    end
  end

  @doc "Runs of `true` in `flags`, as `{first, last}`, joining runs closer than `gap` apart."
  @spec runs([boolean()], non_neg_integer()) :: [{non_neg_integer(), non_neg_integer()}]
  def runs(flags, gap) do
    flags
    |> Enum.with_index()
    |> Enum.filter(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
    |> join(gap)
  end

  defp join([], _gap), do: []

  defp join([first | rest], gap) do
    rest
    |> Enum.reduce([{first, first}], fn index, [{start, last} | done] ->
      if index - last <= gap,
        do: [{start, index} | done],
        else: [{index, index}, {start, last} | done]
    end)
    |> Enum.reverse()
  end

  defp frames(%Raster{width: width} = raster, {top, bottom}, gap, alpha) do
    binary = Raster.to_rgba_binary(raster)

    columns =
      for x <- 0..(width - 1)//1 do
        Enum.any?(top..bottom//1, fn y -> opaque?(binary, y * width + x, alpha) end)
      end

    boxes = columns |> runs(gap) |> Enum.map(fn {left, right} -> {left, right - left + 1} end)
    tallest = bottom - top + 1
    widest = boxes |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 1 end)

    for {left, span} <- boxes do
      raster
      |> Raster.crop({left, top}, {span, tallest})
      |> centred(widest, tallest)
    end
  end

  defp levelled([]), do: []

  defp levelled(frames) do
    widest = frames |> Enum.map(& &1.width) |> Enum.max()
    tallest = frames |> Enum.map(& &1.height) |> Enum.max()

    Enum.map(frames, &standing(&1, widest, tallest))
  end

  defp standing(%Raster{width: width, height: height} = raster, width, height), do: raster

  defp standing(%Raster{width: width, height: height} = raster, widest, tallest) do
    left = div(widest - width, 2)
    top = tallest - height

    for y <- 0..(height - 1)//1, x <- 0..(width - 1)//1, reduce: Raster.new(widest, tallest) do
      canvas -> Raster.put_pixel(canvas, left + x, top + y, Raster.get_pixel(raster, x, y))
    end
  end

  defp centred(%Raster{width: width} = raster, width, _height), do: raster

  defp centred(%Raster{width: width, height: height} = raster, widest, tallest) do
    left = div(widest - width, 2)

    for y <- 0..(height - 1)//1, x <- 0..(width - 1)//1, reduce: Raster.new(widest, tallest) do
      canvas -> Raster.put_pixel(canvas, left + x, y, Raster.get_pixel(raster, x, y))
    end
  end

  defp opaque?(binary, index, alpha) do
    <<_r, _g, _b, a>> = binary_part(binary, index * 4, 4)
    a >= alpha
  end
end
