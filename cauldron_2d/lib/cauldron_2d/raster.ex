defmodule Cauldron2D.Raster do
  @moduledoc """
  A picture as pixels: what a 2D game's art, atlas entries and drawn scenes are made of.

  A fixed-size RGBA pixel buffer, the value every drawing and backend function operates on.

  A raster has a `width`, a `height`, a `background` colour returned for any pixel never
  written, and its contents in two layers:

    * `rgba` — a dense row-major `width * height * 4` byte base buffer, or `nil` when every
      base pixel is the background
    * `pixels` — a sparse map of `{x, y}` to colour written over the base

  `get_pixel/3` reads the top layer first, so the layering is not something a caller has
  to track. `put_pixel/4` and `put_pixels/3` write into `pixels`; `fill_spans/3` writes
  whole horizontal runs straight into the base buffer, which is the fast way to fill
  large areas. `finalize/1` folds the map into the base buffer.

  Coordinates are zero-based with `{0, 0}` at the top left. Writes outside the bounds are
  dropped rather than raising.

      Cauldron2D.Raster.new(4, 2, background: {0, 0, 0, 255})
      |> Cauldron2D.Raster.put_pixel(1, 0, {255, 0, 0, 255})
      |> Cauldron2D.Raster.to_rgba_binary()
  """

  @type channel() :: FrenchCurve.Raster.channel()
  @type color() :: FrenchCurve.Raster.color()
  @type color_rgb() :: FrenchCurve.Raster.color_rgb()
  @type point() :: FrenchCurve.Raster.point()
  @type span() :: FrenchCurve.Raster.span()
  @type t() :: FrenchCurve.Raster.t()

  @doc """
  Returns the `{width, height}` rectangle of `raster` whose top left is at `{x, y}`.

  The rectangle must lie inside the raster. The result carries the same background and
  a dense buffer.
  """
  @spec crop(t(), point(), {pos_integer(), pos_integer()}) :: t()
  def crop(raster, origin, size), do: FrenchCurve.Raster.crop(raster, origin, size)

  @doc """
  Returns the raster's `{width, height}` in pixels.
  """
  @spec dimensions(t()) :: {pos_integer(), pos_integer()}
  def dimensions(raster), do: FrenchCurve.Raster.dimensions(raster)

  @doc """
  Returns `raster` with every horizontal span in `spans` filled with `color`.

  Each span is `{y, x_from, x_to}`, both ends inclusive and in either order. Spans are
  clipped to the raster and may overlap. Pending `put_pixel/4` writes are folded into the
  base buffer first, so the spans land on top of everything drawn before them. A `color`
  that is not an `{r, g, b, a}` tuple is written pixel by pixel as `put_pixels/3` does.
  """
  @spec fill_spans(t(), [span()], color() | term()) :: t()
  def fill_spans(raster, spans, color), do: FrenchCurve.Raster.fill_spans(raster, spans, color)

  @doc """
  Returns `raster` with its pixel map folded into the dense base buffer.

  Pixel values are unchanged. Call this on a raster that will be sent to a backend more
  than once, so `to_rgba_binary/1` returns the buffer without rebuilding it. Drawing
  after `finalize/1` stays correct.
  """
  @spec finalize(t()) :: t()
  def finalize(raster), do: FrenchCurve.Raster.finalize(raster)

  @doc """
  Builds a raster from an existing dense RGBA buffer.

  `binary` must be exactly `width * height * 4` bytes, four bytes per pixel in red,
  green, blue, alpha order and rows top to bottom; a mismatched size raises
  `FunctionClauseError`. The buffer becomes the raster's base without being copied.

  ## Options

    * `:background` — the `t:color/0` returned for out-of-bounds reads, default
      `{0, 0, 0, 0}`
  """
  @spec from_rgba(pos_integer(), pos_integer(), binary(), keyword()) :: t()
  def from_rgba(width, height, binary, opts \\ []),
    do: FrenchCurve.Raster.from_rgba(width, height, binary, opts)

  @doc """
  Returns the `t:color/0` at `{x, y}`.

  Reads a written pixel first, then the base buffer, and falls back to the raster's
  `background`. Out-of-bounds coordinates return the background rather than raising.
  """
  @spec get_pixel(t(), integer(), integer()) :: color()
  def get_pixel(raster, x, y), do: FrenchCurve.Raster.get_pixel(raster, x, y)

  @doc """
  Returns whether `{x, y}` falls inside the raster.

  True when `x` and `y` are both non-negative and below `width` and `height` respectively.
  """
  @spec in_bounds?(t(), integer(), integer()) :: boolean()
  def in_bounds?(raster, x, y), do: FrenchCurve.Raster.in_bounds?(raster, x, y)

  @doc """
  Builds an empty raster `width` by `height` pixels.

  Both dimensions must be positive integers; anything else raises `FunctionClauseError`.

  ## Options

    * `:background` — the `t:color/0` `get_pixel/3` returns for unwritten pixels, default
      `{0, 0, 0, 0}` (transparent black)
  """
  @spec new(pos_integer(), pos_integer(), keyword()) :: t()
  def new(width, height, opts \\ []), do: FrenchCurve.Raster.new(width, height, opts)

  @doc """
  Returns `raster` with the pixel at `{x, y}` set to `color`.

  `color` is an `{r, g, b, a}` tuple of bytes and replaces whatever was there; there is no
  alpha blending. Coordinates outside the bounds are ignored and the raster is returned
  unchanged.
  """
  @spec put_pixel(t(), integer(), integer(), color()) :: t()
  def put_pixel(raster, x, y, color), do: FrenchCurve.Raster.put_pixel(raster, x, y, color)

  @doc """
  Returns `raster` with every `{x, y}` in `points` set to `color`.

  Equivalent to `put_pixel/4` for each point, in one map merge. Points outside the bounds
  are ignored.
  """
  @spec put_pixels(t(), [{integer(), integer()}], color()) :: t()
  def put_pixels(raster, points, color), do: FrenchCurve.Raster.put_pixels(raster, points, color)

  @doc """
  Returns every pixel as `height` lists of `width` colours, top row first.

  Each element is a `t:color/0`; unwritten positions come back as the background.
  """
  @spec rows(t()) :: [[color()]]
  def rows(raster), do: FrenchCurve.Raster.rows(raster)

  @doc """
  Returns the raster as a dense row-major RGBA buffer.

  The result is exactly `width * height * 4` bytes, four bytes per pixel in red, green,
  blue, alpha order, rows top to bottom.
  """
  @spec to_rgba_binary(t()) :: binary()
  def to_rgba_binary(raster), do: FrenchCurve.Raster.to_rgba_binary(raster)
end
