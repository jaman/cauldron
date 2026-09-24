defmodule Cauldron2D.Projection.Canvas do
  @moduledoc """
  A framebuffer of RGBA rows that stamps are painted onto, and the stamps themselves.

  A canvas is a map from row index to that row's pixels, `width * 4` bytes each. A stamp
  is an image reduced to its opaque runs, `%{width, height, runs: [{y, x, pixels}]}`,
  so painting it copies whole runs and skips transparent pixels. `paint/4` clips to the
  canvas.

      canvas = Canvas.new(64, 32, {6, 7, 11})
      stamp = Canvas.stamp(%{width: 8, height: 8, rgba: rgba})
      canvas |> Canvas.paint(stamp, {10, 4}) |> Canvas.to_raster()
  """

  alias FrenchCurve.Raster

  @type image :: %{width: pos_integer(), height: pos_integer(), rgba: binary()}
  @type stamp :: %{
          width: pos_integer(),
          height: pos_integer(),
          runs: [{integer(), integer(), binary()}]
        }
  @type t :: %{
          width: pos_integer(),
          height: pos_integer(),
          rows: %{non_neg_integer() => binary()}
        }

  @doc "A canvas of `width` by `height` filled with `colour`."
  @spec new(pos_integer(), pos_integer(), {byte(), byte(), byte()}) :: t()
  def new(width, height, {red, green, blue}) do
    row = :binary.copy(<<red, green, blue, 255>>, width)
    %{width: width, height: height, rows: Map.new(0..(height - 1)//1, &{&1, row})}
  end

  @doc "A fully transparent canvas of `width` by `height`, to build a stamp on."
  @spec blank(pos_integer(), pos_integer()) :: t()
  def blank(width, height) do
    row = :binary.copy(<<0, 0, 0, 0>>, width)
    %{width: width, height: height, rows: Map.new(0..(height - 1)//1, &{&1, row})}
  end

  @doc "The canvas as an image, for `stamp/1`."
  @spec to_image(t()) :: image()
  def to_image(%{width: width, height: height, rows: rows}),
    do: %{
      width: width,
      height: height,
      rgba: IO.iodata_to_binary(for y <- 0..(height - 1)//1, do: Map.fetch!(rows, y))
    }

  @doc "The canvas as a raster."
  @spec to_raster(t()) :: Raster.t()
  def to_raster(%{width: width, height: height, rows: rows}) do
    Raster.from_rgba(
      width,
      height,
      IO.iodata_to_binary(for y <- 0..(height - 1)//1, do: Map.fetch!(rows, y))
    )
  end

  @doc "The `width` by `height` window of the canvas whose top-left corner is at `{x, y}`."
  @spec crop(t(), {non_neg_integer(), non_neg_integer()}, {pos_integer(), pos_integer()}) :: t()
  def crop(%{rows: rows}, {x0, y0}, {width, height}) do
    cropped =
      Map.new(0..(height - 1)//1, fn y ->
        {y, binary_part(Map.fetch!(rows, y0 + y), x0 * 4, width * 4)}
      end)

    %{width: width, height: height, rows: cropped}
  end

  @doc "An image reduced to its opaque runs. A pixel is opaque from alpha 128."
  @spec stamp(image()) :: stamp()
  def stamp(%{width: width, height: height, rgba: rgba}) do
    runs =
      Enum.flat_map(0..(height - 1)//1, fn y ->
        row = binary_part(rgba, y * width * 4, width * 4)
        pixels = for <<pixel::binary-size(4) <- row>>, do: pixel

        pixels
        |> Enum.with_index()
        |> Enum.chunk_by(&opaque?/1)
        |> Enum.filter(&opaque?(hd(&1)))
        |> Enum.map(fn [{_pixel, x} | _] = chunk ->
          {y, x, IO.iodata_to_binary(Enum.map(chunk, &solid/1))}
        end)
      end)

    %{width: width, height: height, runs: runs}
  end

  defp opaque?({<<_, _, _, alpha>>, _x}), do: alpha >= 128
  defp solid({<<red, green, blue, _>>, _x}), do: <<red, green, blue, 255>>

  @doc "Paint `stamp` with its top-left corner at `{x, y}`, clipped to the canvas."
  @spec paint(t(), stamp(), {integer(), integer()}) :: t()
  def paint(%{width: width, height: height, rows: rows} = canvas, %{runs: runs}, {x0, y0}) do
    painted =
      Enum.reduce(runs, rows, fn {run_y, run_x, run}, acc ->
        paint_run(acc, y0 + run_y, clip(x0 + run_x, run, width), width, height)
      end)

    %{canvas | rows: painted}
  end

  defp paint_run(rows, y, _clipped, _width, height) when y < 0 or y >= height, do: rows
  defp paint_run(rows, _y, nil, _width, _height), do: rows

  defp paint_run(rows, y, {x, segment}, width, _height),
    do: Map.update!(rows, y, &splice(&1, x, segment, width))

  defp clip(x, run, width) do
    length = div(byte_size(run), 4)
    from = max(0, -x)
    to = min(length, width - x)

    if to > from, do: {x + from, binary_part(run, from * 4, (to - from) * 4)}, else: nil
  end

  defp splice(row, x, segment, width) do
    length = div(byte_size(segment), 4)

    <<binary_part(row, 0, x * 4)::binary, segment::binary,
      binary_part(row, (x + length) * 4, (width - x - length) * 4)::binary>>
  end

  @doc "The image at `1 / factor` of its size, sampling every `factor`th pixel."
  @spec shrink(image(), pos_integer()) :: image()
  def shrink(image, 1), do: image

  def shrink(%{width: width, height: height, rgba: rgba}, factor) do
    new_width = max(1, div(width, factor))
    new_height = max(1, div(height, factor))

    shrunk =
      for y <- 0..(new_height - 1)//1, x <- 0..(new_width - 1)//1, into: <<>> do
        binary_part(rgba, (y * factor * width + x * factor) * 4, 4)
      end

    %{width: new_width, height: new_height, rgba: shrunk}
  end

  @doc """
  Paints the parallelogram `origin + u * across + v * down`, `u` and `v` running `0..1`,
  taking each pixel from `texel.(u, v)`; a pixel the function answers `nil` for is left
  alone, as is one outside the canvas.

  The two edge vectors must not be parallel.
  """
  @spec quad(
          t(),
          {number(), number()},
          {number(), number()},
          {number(), number()},
          (float(), float() -> binary() | nil)
        ) :: t()
  def quad(canvas, {ox, oy}, {ax, ay}, {dx, dy}, texel) do
    determinant = ax * dy - ay * dx

    if abs(determinant) < 1.0e-9 do
      canvas
    else
      corners = [{ox, oy}, {ox + ax, oy + ay}, {ox + dx, oy + dy}, {ox + ax + dx, oy + ay + dy}]
      left = corners |> Enum.map(&elem(&1, 0)) |> Enum.min() |> floor() |> max(0)
      right = corners |> Enum.map(&elem(&1, 0)) |> Enum.max() |> ceil() |> min(canvas.width - 1)
      top = corners |> Enum.map(&elem(&1, 1)) |> Enum.min() |> floor() |> max(0)
      bottom = corners |> Enum.map(&elem(&1, 1)) |> Enum.max() |> ceil() |> min(canvas.height - 1)

      Enum.reduce(max(top, 0)..bottom//1, canvas, fn y, acc ->
        paint_span(acc, y, left..right//1, {ox, oy}, {ax, ay}, {dx, dy}, determinant, texel)
      end)
    end
  end

  defp paint_span(canvas, y, columns, {ox, oy}, {ax, ay}, {dx, dy}, determinant, texel) do
    row = Map.fetch!(canvas.rows, y)

    painted =
      Enum.reduce(columns, row, fn x, row ->
        px = x + 0.5 - ox
        py = y + 0.5 - oy
        u = (px * dy - py * dx) / determinant
        v = (ax * py - ay * px) / determinant

        put_texel(row, x, inside(u, v) && texel.(u, v))
      end)

    %{canvas | rows: Map.put(canvas.rows, y, painted)}
  end

  defp inside(u, v), do: u >= 0 and u < 1 and v >= 0 and v < 1

  defp put_texel(row, _x, falsey) when falsey in [nil, false], do: row
  defp put_texel(row, _x, <<_, _, _, alpha>>) when alpha < 128, do: row

  defp put_texel(row, x, pixel),
    do:
      binary_part(row, 0, x * 4) <>
        pixel <> binary_part(row, (x + 1) * 4, byte_size(row) - (x + 1) * 4)

  @doc "The image mirrored left to right."
  @spec flip(image()) :: image()
  def flip(%{width: width, height: height, rgba: rgba}) do
    flipped =
      for y <- 0..(height - 1)//1, x <- (width - 1)..0//-1, into: <<>> do
        binary_part(rgba, (y * width + x) * 4, 4)
      end

    %{width: width, height: height, rgba: flipped}
  end

  @doc "The image with `fun` applied to every pixel's four bytes."
  @spec map_pixels(image(), (binary() -> binary())) :: image()
  def map_pixels(%{rgba: rgba} = image, fun) do
    %{image | rgba: for(<<pixel::binary-size(4) <- rgba>>, into: <<>>, do: fun.(pixel))}
  end

  @doc "The pixel of a square `size` texture at `u`, `v` in `0.0..1.0`."
  @spec texel(binary(), pos_integer(), number(), number()) :: binary()
  def texel(texture, size, u, v) do
    column = u |> Kernel.*(size) |> trunc() |> min(size - 1) |> max(0)
    row = v |> Kernel.*(size) |> trunc() |> min(size - 1) |> max(0)
    binary_part(texture, (row * size + column) * 4, 4)
  end

  @doc """
  `pixel` mixed towards `fog` by `mix` in `0.0..1.0` after its colour is multiplied by
  `factor`; a transparent pixel is left alone.
  """
  @spec shade(binary(), number(), {byte(), byte(), byte()}, number()) :: binary()
  def shade(<<_, _, _, alpha>> = pixel, _factor, _fog, _mix) when alpha < 128, do: pixel

  def shade(<<red, green, blue, _>>, factor, {fog_red, fog_green, fog_blue}, mix) do
    <<channel(red * factor, fog_red, mix), channel(green * factor, fog_green, mix),
      channel(blue * factor, fog_blue, mix), 255>>
  end

  defp channel(value, fog, mix),
    do: value |> Kernel.+((fog - value) * mix) |> round() |> min(255) |> max(0)

  @doc "The value under `key` in the ETS `table`, built by `build` and kept when absent."
  @spec memo(atom(), term(), (-> term())) :: term()
  def memo(table, key, build) do
    case :ets.lookup(table, key) do
      [{^key, value}] ->
        value

      [] ->
        value = build.()
        :ets.insert(table, {key, value})
        value
    end
  end
end
