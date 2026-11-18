defmodule Greenware.Canvas do
  @moduledoc """
  A frame under construction in two spaces: the game is laid out in 640 by 360 design
  units, and the frame is drawn at twice that, 1280 by 720, so type, clay and UI stay
  crisp on a modern screen. `Cauldron2D.Blend.render_band/5` lays every piece down in
  one pass.
  """

  alias Cauldron2D.{Blend, Raster, Shapes}

  @k 2

  @type colour :: {0..255, 0..255, 0..255, 0..255}
  @type item :: {binary(), pos_integer(), pos_integer(), binary()}
  @type t :: %{
          width: pos_integer(),
          height: pos_integer(),
          actual_width: pos_integer(),
          actual_height: pos_integer(),
          background: binary() | colour,
          items: [item()]
        }

  def scale, do: @k

  def new(width, height, background) when is_tuple(background) do
    %{
      width: width,
      height: height,
      actual_width: width * @k,
      actual_height: height * @k,
      background: background,
      items: []
    }
  end

  def new(width, height, background) when is_binary(background) do
    actual = width * @k * height * @k * 4

    unless byte_size(background) in [4, actual] do
      raise ArgumentError,
            "background is #{byte_size(background)} bytes, not four or #{actual}"
    end

    %{
      width: width,
      height: height,
      actual_width: width * @k,
      actual_height: height * @k,
      background: background,
      items: []
    }
  end

  @doc "A solid rectangle in design units."
  def rect(canvas, at, size, colour, opts \\ [])

  def rect(canvas, {x, y}, {width, height}, colour, opts) do
    add(canvas, one(colour), 1, 1, %{
      position: {x * @k, y * @k},
      scale: {width * @k, height * @k},
      alpha: Keyword.get(opts, :alpha, 1.0),
      mode: Keyword.get(opts, :mode, :over)
    })
  end

  def box(canvas, at, size, colour, opts \\ [])

  def box(canvas, {x, y}, {width, height}, colour, opts) do
    thickness = Keyword.get(opts, :thickness, 1) * @k
    alpha = Keyword.get(opts, :alpha, 1.0)
    x = x * @k
    y = y * @k
    width = width * @k
    height = height * @k

    canvas
    |> rect_actual({x, y}, {width, thickness}, colour, alpha)
    |> rect_actual({x, y + height - thickness}, {width, thickness}, colour, alpha)
    |> rect_actual({x, y + thickness}, {thickness, height - 2 * thickness}, colour, alpha)
    |> rect_actual(
      {x + width - thickness, y + thickness},
      {thickness, height - 2 * thickness},
      colour,
      alpha
    )
  end

  @doc "A design-space picture, scaled to the frame."
  def sprite(canvas, picture, at, opts \\ [])

  def sprite(canvas, %FrenchCurve.Raster{} = raster, {x, y}, opts) do
    {width, height} = Raster.dimensions(raster)
    sprite(canvas, {Raster.to_rgba_binary(raster), width, height}, {x, y}, opts)
  end

  def sprite(canvas, {rgba, width, height}, {x, y}, opts) do
    scale = Keyword.get(opts, :scale, {1, 1})

    add(canvas, rgba, width, height, %{
      position: {x * @k, y * @k},
      scale: {elem(scale, 0) * @k, elem(scale, 1) * @k},
      alpha: Keyword.get(opts, :alpha, 1.0),
      angle: Keyword.get(opts, :angle, 0),
      blend: Keyword.get(opts, :tint, {255, 255, 255}),
      mode: Keyword.get(opts, :mode, :over)
    })
  end

  @doc "An already-high-resolution picture (twice the design pixels), drawn at its own size."
  def art(canvas, picture, at, opts \\ [])

  def art(canvas, %FrenchCurve.Raster{} = raster, {x, y}, opts) do
    {width, height} = Raster.dimensions(raster)
    art(canvas, {Raster.to_rgba_binary(raster), width, height}, {x, y}, opts)
  end

  def art(canvas, {rgba, width, height}, {x, y}, opts) do
    add(canvas, rgba, width, height, %{
      position: {x * @k, y * @k},
      scale: Keyword.get(opts, :scale, {1, 1}),
      alpha: Keyword.get(opts, :alpha, 1.0),
      angle: Keyword.get(opts, :angle, 0),
      blend: Keyword.get(opts, :tint, {255, 255, 255}),
      mode: Keyword.get(opts, :mode, :over)
    })
  end

  @doc "A background that already fills the whole 1280 by 720 frame."
  def background(canvas, rgba) do
    unless byte_size(rgba) == canvas.actual_width * canvas.actual_height * 4 do
      raise ArgumentError, "background does not fill the frame"
    end

    %{canvas | background: rgba}
  end

  @doc "A line in design units."
  def line(canvas, from, to, colour, opts \\ [])

  def line(canvas, {x1, y1}, {x2, y2}, colour, opts) do
    thickness = Keyword.get(opts, :thickness, 1)
    alpha = Keyword.get(opts, :alpha, 1.0)
    x1 = x1 * @k
    y1 = y1 * @k
    x2 = x2 * @k
    y2 = y2 * @k
    thickness = thickness * @k
    left = min(x1, x2) - thickness
    top = min(y1, y2) - thickness
    right = max(x1, x2) + thickness
    bottom = max(y1, y2) + thickness
    width = right - left + 1
    height = bottom - top + 1

    if width > 0 and height > 0 do
      raster =
        Raster.new(width, height)
        |> Shapes.line({x1 - left, y1 - top}, {x2 - left, y2 - top}, {255, 255, 255, 255})

      art(canvas, raster, {left / @k, top / @k}, tint: rgb(colour), alpha: alpha)
    else
      canvas
    end
  end

  @doc "A filled circle in design units; cached by actual radius."
  def circle(canvas, at, radius, colour, opts \\ [])

  def circle(canvas, {x, y}, radius, colour, opts) do
    actual_radius = max(1, round(radius)) * @k
    disc = disc(actual_radius)

    art(canvas, disc, {x - radius, y - radius},
      tint: rgb(colour),
      alpha: Keyword.get(opts, :alpha, 1.0),
      scale: Keyword.get(opts, :scale, {1, 1})
    )
  end

  @doc "A polygon in design units."
  def polygon(canvas, points, colour, opts \\ []) do
    points = Enum.map(points, fn {x, y} -> {x * @k, y * @k} end)
    xs = Enum.map(points, &elem(&1, 0))
    ys = Enum.map(points, &elem(&1, 1))
    left = floor(Enum.min(xs))
    top = floor(Enum.min(ys))
    width = max(1, ceil(Enum.max(xs)) - left + 1)
    height = max(1, ceil(Enum.max(ys)) - top + 1)
    translated = Enum.map(points, fn {x, y} -> {x - left, y - top} end)

    raster =
      Raster.new(width, height)
      |> Shapes.fill_polygon(translated, {255, 255, 255, 255})

    art(canvas, raster, {left / @k, top / @k},
      tint: rgb(colour),
      alpha: Keyword.get(opts, :alpha, 1.0)
    )
  end

  @doc "Text in a 2x bitmap font, positioned in design units."
  def text(canvas, font, text, at, opts \\ [])

  def text(canvas, font, text, {x, y}, opts) do
    if text in [nil, ""] do
      canvas
    else
      colour = Keyword.get(opts, :colour, {255, 252, 240, 255})
      alpha = Keyword.get(opts, :alpha, 1.0)

      wrap =
        case Keyword.get(opts, :wrap) do
          nil -> nil
          width -> width * @k
        end

      align = Keyword.get(opts, :align, :left)
      kind = if font == Greenware.Fonts.display(), do: :display, else: :body
      font = if kind == :display, do: Greenware.Fonts.display(), else: Greenware.Fonts.body()

      placements = Linocut.BitmapFont.layout(font, text, wrap: wrap, align: align)

      canvas =
        if opts[:outline] do
          outline = opts[:outline] |> rgb()

          for {dx, dy} <- [{-1, 0}, {1, 0}, {0, -1}, {0, 1}, {-1, -1}, {1, -1}, {-1, 1}, {1, 1}],
              {char, {gx, gy}} <- placements,
              {rgba, w, h} = glyph(font, kind, char),
              reduce: canvas do
            acc ->
              art(acc, {rgba, w, h}, {x + gx / @k + dx / @k, y + gy / @k + dy / @k},
                tint: outline,
                alpha: alpha
              )
          end
        else
          canvas
        end

      canvas =
        if opts[:shadow] do
          shadow = opts[:shadow] |> rgb()

          Enum.reduce(placements, canvas, fn {char, {gx, gy}}, acc ->
            {rgba, w, h} = glyph(font, kind, char)

            art(acc, {rgba, w, h}, {x + gx / @k + 1 / @k, y + gy / @k + 1 / @k},
              tint: shadow,
              alpha: alpha
            )
          end)
        else
          canvas
        end

      Enum.reduce(placements, canvas, fn {char, {gx, gy}}, acc ->
        {rgba, w, h} = glyph(font, kind, char)
        art(acc, {rgba, w, h}, {x + gx / @k, y + gy / @k}, tint: rgb(colour), alpha: alpha)
      end)
    end
  end

  defp glyph(font, kind, char) do
    key = {__MODULE__, :glyph, kind, char}

    case :persistent_term.get(key, nil) do
      nil ->
        case Linocut.BitmapFont.glyph(font, char) do
          nil ->
            nil

          %{raster: raster} ->
            {width, height} = Raster.dimensions(raster)
            value = {Raster.to_rgba_binary(raster), width, height}
            :persistent_term.put(key, value)
            value
        end

      value ->
        value
    end
  end

  @doc "The finished 1280 by 720 picture."
  def finish(canvas) do
    background =
      case canvas.background do
        colour when is_tuple(colour) -> one(colour)
        binary -> binary
      end

    rgba =
      Blend.render_band(
        canvas.actual_width,
        0,
        canvas.actual_height,
        background,
        Enum.reverse(canvas.items)
      )

    Raster.from_rgba(canvas.actual_width, canvas.actual_height, rgba)
  end

  @doc "A full-frame RGBA of one colour, at actual size."
  def fill(width, height, colour) do
    :binary.copy(one(colour), width * height)
  end

  @doc "A vertical gradient at actual size; width and height are actual pixels."
  def gradient(width, height, top, bottom) do
    for y <- 0..(height - 1), into: <<>> do
      t = if height <= 1, do: 0.0, else: y / (height - 1)
      :binary.copy(one(Greenware.Palette.mix(top, bottom, t)), width)
    end
  end

  defp add(canvas, rgba, width, height, placement) do
    %{canvas | items: [{rgba, width, height, Blend.transform(placement)} | canvas.items]}
  end

  defp rect_actual(canvas, {x, y}, {width, height}, colour, alpha) do
    add(canvas, one(colour), 1, 1, %{
      position: {x, y},
      scale: {width, height},
      alpha: alpha,
      mode: :over
    })
  end

  defp one({r, g, b, a}), do: <<r, g, b, a>>

  defp rgb({r, g, b, _a}), do: {r, g, b}
  defp rgb({r, g, b}), do: {r, g, b}

  defp disc(radius) do
    key = {__MODULE__, :disc, radius}

    case :persistent_term.get(key, nil) do
      nil ->
        raster =
          Raster.new(radius * 2 + 1, radius * 2 + 1)
          |> Shapes.fill_circle({radius, radius}, radius, {255, 255, 255, 255})

        :persistent_term.put(key, raster)
        raster

      raster ->
        raster
    end
  end
end
