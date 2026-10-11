defmodule Cauldron2D.Blend do
  @moduledoc """
  Source-over compositing of two equal-sized RGBA rectangles.

      Cauldron2D.Blend.over(beneath, above)

  Both binaries are four bytes per pixel and must be the same length. The result is the
  same length: `above` laid over `beneath`, premultiplied by `above`'s alpha.

  `available?/0` says whether the C library loaded. Where it did not the same picture is
  produced in Elixir, some fifty times slower.
  """

  @on_load :load_nif

  @doc false
  def load_nif do
    "blend_nif"
    |> Cauldron2D.Native.path()
    |> :erlang.load_nif(0)
    |> then(&:persistent_term.put({__MODULE__, :native}, &1 == :ok))
  end

  @doc "Whether the library is loaded and compositing is done in C."
  @spec available?() :: boolean()
  def available?, do: :persistent_term.get({__MODULE__, :native}, false)

  @doc "`above` laid over `beneath`, both RGBA of the same length."
  @spec over(binary(), binary()) :: binary()
  def over(beneath, above) when byte_size(beneath) == byte_size(above),
    do: elixir_over(beneath, above, [])

  @doc false
  @spec elixir_over(binary(), binary(), iodata()) :: binary()
  def elixir_over(<<>>, <<>>, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  def elixir_over(<<br, bg, bb, ba, beneath::binary>>, <<_r, _g, _b, 0, above::binary>>, acc),
    do: elixir_over(beneath, above, [<<br, bg, bb, ba>> | acc])

  def elixir_over(<<_r, _g, _b, _a, beneath::binary>>, <<tr, tg, tb, 255, above::binary>>, acc),
    do: elixir_over(beneath, above, [<<tr, tg, tb, 255>> | acc])

  def elixir_over(<<br, bg, bb, ba, beneath::binary>>, <<tr, tg, tb, ta, above::binary>>, acc) do
    top_alpha = ta / 255
    base_alpha = ba / 255 * (1 - top_alpha)
    alpha = top_alpha + base_alpha

    pixel =
      <<mix(tr, br, top_alpha, base_alpha, alpha), mix(tg, bg, top_alpha, base_alpha, alpha),
        mix(tb, bb, top_alpha, base_alpha, alpha), round(alpha * 255)>>

    elixir_over(beneath, above, [pixel | acc])
  end

  defp mix(above, beneath, top_alpha, base_alpha, alpha),
    do: round((above * top_alpha + beneath * base_alpha) / alpha)

  @doc """
  `picture` drawn over `canvas`, both RGBA, placed by `placement`, as a new canvas.

  `placement` is a map:

    * `:position` — `{x, y}`, the canvas pixel the picture's origin lands on; fractions
      allowed
    * `:origin` — `{x, y}` in the picture's pixels, default `{0, 0}`
    * `:scale` — `{x, y}`, default `{1, 1}`; a negative scale mirrors along that axis
      and a zero scale draws nothing
    * `:angle` — degrees, counter-clockwise as seen on the canvas, default `0`
    * `:blend` — `{r, g, b}` multiplied into the picture's colours, default white
    * `:alpha` — `0.0`–`1.0` multiplied into the picture's alpha, default `1.0`
    * `:mode` — `:over` (the default), `:add` or `:subtract`; or `{:gamemaker, mode}`, the
      same blend with GameMaker's blend factors applied to the alpha channel as well as
      the colours, as GameMaker draws onto a surface: over `colour × As + beneath × (1 −
      As)` and alpha `As² + Ad × (1 − As)`; add `colour × As + beneath` and alpha `As² +
      Ad`; subtract `beneath × (1 − colour)` and alpha `Ad × (1 − As)`

  Every canvas pixel whose centre falls inside the turned and scaled picture takes the
  nearest picture pixel, laid over the canvas as `over/2` lays one pixel over another —
  or, with `mode: :add`, its colour times its alpha added to the canvas's, each channel
  at most 255, as GameMaker's additive blend mode adds it — or, with `mode: :subtract`,
  each canvas channel times one less the picture's colour times its alpha, the canvas's
  alpha kept, as GameMaker's `bm_subtract` takes it away.
  Pixels outside the canvas are dropped. `native: false` draws in Elixir where the C
  library is loaded.
  """
  @spec draw(
          binary(),
          {pos_integer(), pos_integer()},
          binary(),
          {pos_integer(), pos_integer()},
          map(),
          keyword()
        ) :: binary()
  def draw(canvas, {canvas_width, canvas_height}, picture, {width, height}, placement, opts \\ []) do
    sized!(canvas, canvas_width, canvas_height, "canvas")
    sized!(picture, width, height, "picture")
    draw = if Keyword.get(opts, :native, true), do: &draw/7, else: &elixir_draw/7
    draw.(canvas, canvas_width, canvas_height, picture, width, height, transform(placement))
  end

  @doc false
  @spec draw(
          binary(),
          pos_integer(),
          pos_integer(),
          binary(),
          pos_integer(),
          pos_integer(),
          binary()
        ) :: binary()
  def draw(canvas, canvas_width, canvas_height, picture, width, height, transform),
    do: elixir_draw(canvas, canvas_width, canvas_height, picture, width, height, transform)

  @doc false
  @spec elixir_draw(
          binary(),
          pos_integer(),
          pos_integer(),
          binary(),
          pos_integer(),
          pos_integer(),
          binary()
        ) :: binary()
  def elixir_draw(canvas, canvas_width, canvas_height, picture, width, height, transform),
    do: draw_rows(canvas, canvas_width, {0, canvas_height}, {picture, width, height, transform})

  @doc """
  The rows `top` up to `bottom` of a canvas `width` pixels wide, starting as
  `background` — four RGBA bytes repeated, or those rows' own pixels — with each of
  `items` drawn over it in order. An
  item is `{picture, picture_width, picture_height, transform}`, `transform` as
  `transform/1` builds it. The rows are drawn exactly as the same rows of the whole
  canvas would be.
  """
  @spec render_band(pos_integer(), non_neg_integer(), non_neg_integer(), binary(), list()) ::
          binary()
  def render_band(width, top, bottom, background, items),
    do: elixir_render_band(width, top, bottom, background, items)

  @doc false
  @spec elixir_render_band(pos_integer(), non_neg_integer(), non_neg_integer(), binary(), list()) ::
          binary()
  def elixir_render_band(width, top, bottom, background, items)
      when is_integer(width) and width > 0 and is_integer(top) and top >= 0 and
             is_integer(bottom) and bottom >= top and is_list(items) do
    band_size = width * (bottom - top) * 4

    unless byte_size(background) in [4, band_size] do
      raise ArgumentError,
            "a band's background is 4 bytes or #{band_size}, not #{byte_size(background)}"
    end

    Enum.each(items, fn {picture, picture_width, picture_height, _transform} ->
      sized!(picture, picture_width, picture_height, "picture")
    end)

    band =
      if byte_size(background) == 4,
        do: :binary.copy(background, width * (bottom - top)),
        else: background

    Enum.reduce(items, band, &draw_rows(&2, width, {top, bottom}, &1))
  end

  def elixir_render_band(width, top, bottom, _background, _items),
    do:
      raise(
        ArgumentError,
        "not a band: width #{inspect(width)}, rows #{inspect(top)}..#{inspect(bottom)}"
      )

  @doc """
  Raises `ArgumentError` unless `rgba` is a picture of `width` by `height` pixels, both
  positive, four bytes each. `name` says what the picture is in the message.
  """
  @spec sized!(binary(), integer(), integer(), String.t()) :: :ok
  def sized!(rgba, width, height, _name)
      when is_binary(rgba) and is_integer(width) and width > 0 and is_integer(height) and
             height > 0 and byte_size(rgba) == width * height * 4,
      do: :ok

  def sized!(rgba, width, height, name) do
    raise ArgumentError,
          "a #{name} of #{inspect(width)}x#{inspect(height)} pixels needs positive sizes and " <>
            "#{inspect(width)} * #{inspect(height)} * 4 bytes, not #{inspect(byte_size_of(rgba))}"
  end

  defp byte_size_of(rgba) when is_binary(rgba), do: byte_size(rgba)
  defp byte_size_of(other), do: other

  @doc "The 104-byte transform `placement` (as `draw/6` takes it) is drawn with."
  @spec transform(map()) :: binary()
  def transform(placement) do
    {x, y} = Map.fetch!(placement, :position)
    {origin_x, origin_y} = Map.get(placement, :origin, {0, 0})
    {scale_x, scale_y} = Map.get(placement, :scale, {1, 1})
    {cos, sin} = Cauldron2D.Turn.cos_sin(Map.get(placement, :angle, 0))
    {red, green, blue} = Map.get(placement, :blend, {255, 255, 255})

    for value <- [
          x,
          y,
          origin_x,
          origin_y,
          scale_x,
          scale_y,
          cos,
          sin,
          red / 255,
          green / 255,
          blue / 255,
          Map.get(placement, :alpha, 1.0),
          mode(Map.get(placement, :mode, :over))
        ],
        into: <<>>,
        do: <<value * 1.0::float-64-native>>
  end

  defp mode(:over), do: 0.0
  defp mode(:add), do: 1.0
  defp mode(:subtract), do: 2.0
  defp mode({:gamemaker, mode}), do: 10.0 + mode(mode)

  defp draw_rows(band, canvas_width, {first, last}, {picture, width, height, transform}) do
    stamp = stamp(transform, width, height)

    case covered(stamp, canvas_width, {first, last}) do
      nil ->
        band

      {left, top, right, bottom} ->
        stride = canvas_width * 4
        before = binary_part(band, 0, (top - first) * stride)
        after_rows = binary_part(band, (bottom - first) * stride, (last - bottom) * stride)

        rows =
          for row <- top..(bottom - 1)//1 do
            line = binary_part(band, (row - first) * stride, stride)
            middle = binary_part(line, left * 4, (right - left) * 4)

            [
              binary_part(line, 0, left * 4),
              drawn_row(middle, left, row, stamp, picture),
              binary_part(line, right * 4, stride - right * 4)
            ]
          end

        IO.iodata_to_binary([before, rows, after_rows])
    end
  end

  defp stamp(<<_::binary-104>> = transform, width, height) do
    [x, y, origin_x, origin_y, scale_x, scale_y, cos, sin, red, green, blue, alpha, mode] =
      for <<bits::binary-8 <- transform>>, do: double(bits)

    if Enum.all?([x, y, origin_x, origin_y, scale_x, scale_y, cos, sin], &is_float/1) do
      %{
        x: x,
        y: y,
        origin: {origin_x, origin_y},
        scale: {scale_x, scale_y},
        cos: cos,
        sin: sin,
        blend: {unit(red), unit(green), unit(blue)},
        alpha: unit(alpha),
        mode: mode,
        size: {width, height}
      }
    end
  end

  defp stamp(transform, _width, _height),
    do: raise(ArgumentError, "a transform is 104 bytes, not #{byte_size(transform)}")

  defp double(<<value::float-64-native>>), do: value

  defp double(<<bits::unsigned-64-native>>) do
    mantissa = Bitwise.band(bits, 0xFFFFFFFFFFFFF)

    cond do
      mantissa != 0 -> :nan
      Bitwise.bsr(bits, 63) == 0 -> :infinity
      true -> :neg_infinity
    end
  end

  defp unit(:infinity), do: 1.0
  defp unit(value) when is_float(value) and value > 1.0, do: 1.0
  defp unit(value) when is_float(value) and value > 0.0, do: value
  defp unit(_value), do: 0.0

  defp covered(nil, _width, _rows), do: nil

  defp covered(%{scale: {scale_x, scale_y}, alpha: alpha}, _width, _rows)
       when scale_x == 0.0 or scale_y == 0.0 or alpha <= 0.0,
       do: nil

  defp covered(stamp, canvas_width, {first, last}) do
    {width, height} = stamp.size

    corners =
      for {u, v} <- [{0, 0}, {width, 0}, {0, height}, {width, height}],
          do: corner(stamp, u * 1.0, v * 1.0)

    {xs, ys} = Enum.unzip(corners)
    left = xs |> Enum.min() |> floor() |> max(0)
    right = xs |> Enum.max() |> ceil() |> min(canvas_width)
    top = ys |> Enum.min() |> floor() |> max(first)
    bottom = ys |> Enum.max() |> ceil() |> min(last)

    if left < right and top < bottom, do: {left, top, right, bottom}
  end

  defp corner(%{origin: {origin_x, origin_y}, scale: {scale_x, scale_y}} = stamp, u, v) do
    dx = (u - origin_x) * scale_x
    dy = (v - origin_y) * scale_y
    {stamp.x + dx * stamp.cos + dy * stamp.sin, stamp.y - dx * stamp.sin + dy * stamp.cos}
  end

  defp drawn_row(middle, left, row, stamp, picture) do
    {pixels, _column} =
      for <<pixel::binary-4 <- middle>>, reduce: {[], left} do
        {acc, column} -> {[drawn_pixel(pixel, column, row, stamp, picture) | acc], column + 1}
      end

    Enum.reverse(pixels)
  end

  defp drawn_pixel(base, column, row, stamp, picture) do
    case source(stamp, column + 0.5, row + 0.5) do
      nil -> base
      {u, v} -> laid(base, binary_part(picture, (v * elem(stamp.size, 0) + u) * 4, 4), stamp)
    end
  end

  defp source(%{origin: {origin_x, origin_y}, scale: {scale_x, scale_y}} = stamp, px, py) do
    rx = px - stamp.x
    ry = py - stamp.y
    u = (rx * stamp.cos - ry * stamp.sin) / scale_x + origin_x
    v = (rx * stamp.sin + ry * stamp.cos) / scale_y + origin_y
    {width, height} = stamp.size

    if u >= 0.0 and u < width and v >= 0.0 and v < height, do: {floor(u), floor(v)}
  end

  defp laid(<<br, bg, bb, ba>>, <<tr, tg, tb, ta>>, %{mode: mode, blend: blend} = stamp)
       when mode >= 10.0 do
    top_alpha = ta * stamp.alpha / 255.0
    base_alpha = ba / 255.0
    kind = trunc(mode - 10.0)

    colours =
      for {above, beneath, tint} <- Enum.zip([[tr, tg, tb], [br, bg, bb], Tuple.to_list(blend)]),
          into: <<>> do
        colour = above / 255.0 * tint
        beneath = beneath / 255.0

        result =
          case kind do
            2 -> beneath * (1.0 - colour)
            1 -> colour * top_alpha + beneath
            _ -> colour * top_alpha + beneath * (1.0 - top_alpha)
          end

        <<byte(result * 255.0)>>
      end

    alpha =
      case kind do
        2 -> base_alpha * (1.0 - top_alpha)
        1 -> top_alpha * top_alpha + base_alpha
        _ -> top_alpha * top_alpha + base_alpha * (1.0 - top_alpha)
      end

    colours <> <<byte(alpha * 255.0)>>
  end

  defp laid(
         <<br, bg, bb, ba>> = base,
         <<tr, tg, tb, ta>>,
         %{mode: 1.0, blend: {red, green, blue}} = stamp
       ) do
    top_alpha = ta * stamp.alpha / 255.0

    if top_alpha <= 0.0 do
      base
    else
      <<added(br, tr * red, top_alpha), added(bg, tg * green, top_alpha),
        added(bb, tb * blue, top_alpha), min(255, trunc(ba + top_alpha * 255.0 + 0.5))>>
    end
  end

  defp laid(
         <<br, bg, bb, ba>> = base,
         <<tr, tg, tb, ta>>,
         %{mode: 2.0, blend: {red, green, blue}} = stamp
       ) do
    top_alpha = ta * stamp.alpha / 255.0

    if top_alpha <= 0.0 do
      base
    else
      <<kept(br, tr * red, top_alpha), kept(bg, tg * green, top_alpha),
        kept(bb, tb * blue, top_alpha), ba>>
    end
  end

  defp laid(<<br, bg, bb, ba>> = base, <<tr, tg, tb, ta>>, %{blend: {red, green, blue}} = stamp) do
    top_alpha = ta * stamp.alpha / 255.0

    if top_alpha <= 0.0 do
      base
    else
      base_alpha = ba / 255.0 * (1.0 - top_alpha)
      alpha = top_alpha + base_alpha

      <<channel(tr * red, br, top_alpha, base_alpha, alpha),
        channel(tg * green, bg, top_alpha, base_alpha, alpha),
        channel(tb * blue, bb, top_alpha, base_alpha, alpha), trunc(alpha * 255.0 + 0.5)>>
    end
  end

  defp added(beneath, above, top_alpha), do: min(255, trunc(beneath + above * top_alpha + 0.5))

  defp byte(value), do: value |> Kernel.+(0.5) |> trunc() |> max(0) |> min(255)

  defp kept(beneath, above, top_alpha),
    do: max(0, trunc(beneath * (1.0 - above / 255.0 * top_alpha) + 0.5))

  defp channel(above, beneath, top_alpha, base_alpha, alpha),
    do: trunc((above * top_alpha + beneath * base_alpha) / alpha + 0.5)
end
