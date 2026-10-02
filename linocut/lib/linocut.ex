defmodule Linocut do
  @moduledoc """
  Pictures written in code: a sprite as text with a palette, a shape as an outline, and
  the derivations a game needs — headings, recolouring, tinting, scaling, flipping,
  turning, cutting into frames, strips; and the same read from `.png` and `.pic` files.

  Every function is pure and returns a `FrenchCurve.Raster`.

      ship = Linocut.sprite(\"\"\"
      ..RR..
      .RWWR.
      RRWWRR
      \"\"\", R: "#c33", W: :white)

      headings = Linocut.headings([{15, 0}, {-8, 8}, {-8, -8}], 64, size: {16, 16}, fill: :white)
      team_ship = Linocut.recolour(ship, %{{204, 51, 51, 255} => {51, 51, 204, 255}})

  ## Colours

  A colour in a palette or an option is `"#rgb"`, `"#rrggbb"`, `"#rrggbbaa"`, one of the
  names `Linocut.Palette` knows, or an `{r, g, b}` or `{r, g, b, a}` tuple. `.` and space
  in a picture are transparent.

  ## Shapes

  An outline is a list of `{x, y}` points with `x` to the right and `y` upward, closed
  from the last point back to the first. Heading `0` is the shape as written, pointing
  right; headings turn counter-clockwise on screen.
  """

  alias FrenchCurve.{Draw, Raster}
  alias Linocut.Palette

  @type color_spec :: Palette.spec()
  @type point :: {number(), number()}

  @doc """
  A sprite from a picture and a palette.

  ## Options

    * `:size` — `{width, height}` of the raster, with the picture centred in it. Default:
      the picture's own size
    * `:background` — the colour of `.` and space. Default: transparent
  """
  @spec sprite(String.t(), keyword() | map(), keyword()) :: Raster.t()
  def sprite(picture, palette, opts \\ []) do
    rows =
      picture |> String.split("\n") |> Enum.reject(&(&1 == "")) |> Enum.map(&String.graphemes/1)

    width = rows |> Enum.map(&length/1) |> Enum.max(fn -> 0 end)
    height = length(rows)
    {canvas_width, canvas_height} = Keyword.get(opts, :size, {width, height})
    background = opts |> Keyword.get(:background, {0, 0, 0, 0}) |> Palette.color()
    colours = Map.new(palette, fn {name, spec} -> {to_string(name), Palette.color(spec)} end)
    left = div(canvas_width - width, 2)
    top = div(canvas_height - height, 2)

    for {row, y} <- Enum.with_index(rows),
        {char, x} <- Enum.with_index(row),
        char not in [".", " "],
        reduce: Raster.new(canvas_width, canvas_height, background: background) do
      raster -> Raster.put_pixel(raster, left + x, top + y, colour_of(colours, char))
    end
  end

  defp colour_of(colours, char) do
    case Map.fetch(colours, char) do
      {:ok, colour} -> colour
      :error -> raise ArgumentError, "no colour for #{inspect(char)} in the palette"
    end
  end

  @doc """
  A shape drawn from its outline.

  ## Options

    * `:size` — `{width, height}` of the raster. Required
    * `:fill` — the colour inside. Default: none
    * `:stroke` — the colour of the outline. Default: the fill
    * `:scale` — pixels per shape unit. Default: whatever fits the shape's farthest point
      inside the raster with a one-pixel margin
    * `:rotate` — radians to turn the shape counter-clockwise on screen. Default `0`
  """
  @spec outline([point()], keyword()) :: Raster.t()
  def outline(points, opts) do
    {width, height} = Keyword.fetch!(opts, :size)
    scale = Keyword.get_lazy(opts, :scale, fn -> fit_scale(points, {width, height}) end)
    angle = Keyword.get(opts, :rotate, 0)
    fill = opts |> Keyword.get(:fill) |> maybe_color()
    stroke = opts |> Keyword.get(:stroke, Keyword.get(opts, :fill)) |> maybe_color()
    centre = {width / 2, height / 2}
    placed = Enum.map(points, &place(&1, angle, scale, centre))

    Raster.new(width, height)
    |> paint_fill(placed, fill)
    |> paint_stroke(placed, stroke)
  end

  defp fit_scale(points, {width, height}) do
    radius =
      points |> Enum.map(fn {x, y} -> :math.sqrt(x * x + y * y) end) |> Enum.max(fn -> 1 end)

    (min(width, height) / 2 - 1) / max(radius, 1.0e-9)
  end

  defp place({x, y}, angle, scale, {cx, cy}) do
    cos = :math.cos(angle)
    sin = :math.sin(angle)
    {cx + (x * cos - y * sin) * scale, cy - (x * sin + y * cos) * scale}
  end

  defp paint_fill(raster, _points, nil), do: raster
  defp paint_fill(raster, points, fill), do: Draw.fill_polygon(raster, points, fill)

  defp paint_stroke(raster, _points, nil), do: raster

  defp paint_stroke(raster, points, stroke) do
    rounded = Enum.map(points ++ [hd(points)], fn {x, y} -> {round(x), round(y)} end)
    Draw.polyline(raster, rounded, stroke)
  end

  defp maybe_color(nil), do: nil
  defp maybe_color(spec), do: Palette.color(spec)

  @doc """
  The shape at each of `count` headings, heading `0` first.

  Takes the options of `outline/2`; `:rotate` is added to each heading's turn.
  """
  @spec headings([point()], pos_integer(), keyword()) :: [Raster.t()]
  def headings(points, count, opts) when count > 0 do
    base = Keyword.get(opts, :rotate, 0)

    for heading <- 0..(count - 1) do
      outline(points, Keyword.put(opts, :rotate, base + 2 * :math.pi() * heading / count))
    end
  end

  @doc "Every pixel passed through `mapping`: a map from colour to colour, or a function of a colour."
  @spec recolour(
          Raster.t(),
          %{Raster.color() => color_spec()} | (Raster.color() -> Raster.color())
        ) :: Raster.t()
  def recolour(%Raster{} = raster, mapping) when is_map(mapping) do
    resolved = Map.new(mapping, fn {from, to} -> {from, Palette.color(to)} end)
    recolour(raster, fn colour -> Map.get(resolved, colour, colour) end)
  end

  def recolour(%Raster{} = raster, fun) when is_function(fun, 1), do: map_pixels(raster, fun)

  @doc "Every opaque pixel mixed `amount` (0.0 to 1.0) of the way toward `colour`; transparent ones untouched."
  @spec tint(Raster.t(), color_spec(), number()) :: Raster.t()
  def tint(%Raster{} = raster, colour, amount) do
    {tr, tg, tb, _} = Palette.color(colour)

    map_pixels(raster, fn
      {_r, _g, _b, 0} = clear -> clear
      {r, g, b, a} -> {mix(r, tr, amount), mix(g, tg, amount), mix(b, tb, amount), a}
    end)
  end

  defp mix(from, to, amount), do: round(from + (to - from) * amount)

  @doc """
  The picture scaled to a share of its size on each axis and placed back in a canvas of
  the original size.

  ## Options

    * `:anchor` — `:centre` (default) or `:bottom`, where the scaled picture sits
    * `:lean` — `-1.0..1.0`, how far toward an edge it slides across. Default `0.0`
  """
  @spec squash(Raster.t(), {number(), number()}, keyword()) :: Raster.t()
  def squash(%Raster{width: width, height: height} = raster, {across, down}, opts \\ []) do
    narrow = max(1, round(width * across))
    short = max(1, round(height * down))
    small = Linocut.Resample.to(raster, {narrow, short})
    lean = Keyword.get(opts, :lean, 0.0)
    left = div(width - narrow, 2) + round(lean * (width - narrow) / 2)

    top =
      case Keyword.get(opts, :anchor, :centre) do
        :bottom -> height - short
        _centre -> div(height - short, 2)
      end

    for y <- 0..(short - 1)//1, x <- 0..(narrow - 1)//1, reduce: Raster.new(width, height) do
      canvas -> Raster.put_pixel(canvas, left + x, top + y, Raster.get_pixel(small, x, y))
    end
  end

  @doc "The raster enlarged `factor` times, each pixel becoming a square block."
  @spec scale(Raster.t(), pos_integer()) :: Raster.t()
  def scale(%Raster{} = raster, factor) when is_integer(factor) and factor > 0 do
    {width, height} = Raster.dimensions(raster)

    for y <- 0..(height - 1)//1,
        x <- 0..(width - 1)//1,
        reduce: Raster.new(width * factor, height * factor, background: raster.background) do
      acc ->
        colour = Raster.get_pixel(raster, x, y)

        Draw.fill_rect(
          acc,
          {x * factor, y * factor},
          {x * factor + factor - 1, y * factor + factor - 1},
          colour
        )
    end
  end

  @doc """
  The raster in a file, by its extension: `.png` through `Linocut.Png`, `.pic` through
  `Linocut.Pic` with `opts` as `sprite/3` takes them.
  """
  @spec load(Path.t(), keyword()) :: {:ok, Raster.t()} | {:error, term()}
  def load(path, opts \\ []) do
    case Path.extname(path) do
      ".png" -> with {:ok, bytes} <- File.read(path), do: Linocut.Png.decode(bytes)
      ".pic" -> with {:ok, bytes} <- File.read(path), do: Linocut.Pic.parse(bytes, opts)
      other -> {:error, {:unknown_format, other}}
    end
  end

  @doc "A picture in the `.pic` text form, as `Linocut.Pic.parse/2` reads it."
  @spec pic(String.t(), keyword()) :: {:ok, Raster.t()} | {:error, term()}
  defdelegate pic(text, opts \\ []), to: Linocut.Pic, as: :parse

  @doc "The raster mirrored left to right (`:horizontal`) or top to bottom (`:vertical`)."
  @spec flip(Raster.t(), :horizontal | :vertical) :: Raster.t()
  def flip(%Raster{} = raster, :horizontal) do
    {width, height} = Raster.dimensions(raster)
    transform(raster, {width, height}, fn {x, y} -> {width - 1 - x, y} end)
  end

  def flip(%Raster{} = raster, :vertical) do
    {width, height} = Raster.dimensions(raster)
    transform(raster, {width, height}, fn {x, y} -> {x, height - 1 - y} end)
  end

  @doc "The raster turned `degrees` counter-clockwise on screen, a multiple of 90."
  @spec rotate(Raster.t(), integer()) :: Raster.t()
  def rotate(%Raster{} = raster, degrees) when rem(degrees, 90) == 0 do
    {width, height} = Raster.dimensions(raster)

    case Integer.mod(div(degrees, 90), 4) do
      0 -> raster
      1 -> transform(raster, {height, width}, fn {x, y} -> {y, width - 1 - x} end)
      2 -> transform(raster, {width, height}, fn {x, y} -> {width - 1 - x, height - 1 - y} end)
      3 -> transform(raster, {height, width}, fn {x, y} -> {height - 1 - y, x} end)
    end
  end

  @doc """
  A raster of `size` with every pixel of `raster` put where `fun` sends its position.

  A pixel sent outside the new raster is dropped; a position nothing is sent to keeps
  the background.
  """
  @spec transform(Raster.t(), {pos_integer(), pos_integer()}, (point() -> point())) :: Raster.t()
  def transform(%Raster{} = raster, {new_width, new_height}, fun) when is_function(fun, 1) do
    {width, height} = Raster.dimensions(raster)

    for y <- 0..(height - 1)//1,
        x <- 0..(width - 1)//1,
        reduce: Raster.new(new_width, new_height, background: raster.background) do
      acc ->
        {tx, ty} = fun.({x, y})

        if Raster.in_bounds?(acc, tx, ty),
          do: Raster.put_pixel(acc, tx, ty, Raster.get_pixel(raster, x, y)),
          else: acc
    end
  end

  @doc """
  The raster cut into frames `{width, height}` pixels each, left to right then top to
  bottom. A remainder narrower or shorter than a frame is left out.
  """
  @spec frames(Raster.t(), {pos_integer(), pos_integer()}) :: [Raster.t()]
  def frames(%Raster{} = raster, {frame_width, frame_height}) do
    {width, height} = Raster.dimensions(raster)

    for top <- 0..(height - frame_height)//frame_height,
        left <- 0..(width - frame_width)//frame_width,
        do: Raster.crop(raster, {left, top}, {frame_width, frame_height})
  end

  defp map_pixels(%Raster{} = raster, fun) do
    {width, height} = Raster.dimensions(raster)

    for y <- 0..(height - 1)//1,
        x <- 0..(width - 1)//1,
        reduce: Raster.new(width, height, background: raster.background) do
      acc -> Raster.put_pixel(acc, x, y, fun.(Raster.get_pixel(raster, x, y)))
    end
  end
end
