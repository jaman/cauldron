defmodule Cauldron3D.Paint do
  @moduledoc """
  How a polygon's pixels get their colours.

    * `{:flat, colour}` — one colour
    * `{:texture, texture, light}` — a `Cauldron3D.Texture` repeated across the polygon
      by its `uvs`, through the light table at `light` (0 to 255, 128 the texture's own
      colours), or as it is when `light` is `nil`
    * `{:shaded, texture}` — as `:texture`, the light carried across from the
      polygon's `lights`
    * `{:surface, texture}` — a texture already lit, its edge pixels repeated beyond it
    * `{:warp, texture, opts}` — a texture rippling as liquid does: each place on it
      moved by `:amplitude` pixels (default 8.0) along a sine of the other axis, of
      `:wavelength` pixels (default 128.0), moving with `:time` seconds at `:speed`
      (default 1.0) turns a second; `:light` as `:texture`'s, default `nil`
    * `{:sky, layers, opts}` — a sky at no distance: `layers` is a list of
      `{texture, speed}`, nearest first, each drawn where the one before is colour
      `:clear` (default 0) and moving `speed` pixels a second with `:time`; `:scale`
      (default 378.0) is how far across the sky a view straight ahead reaches, and
      `:flatten` (default 3.0) squashes it toward the horizon
    * `{:fun, fun}` — `fun.(first, stop, y, setup, context)` returns the `stop - first`
      colours of the run itself

  The context is a map: `:light_table` (rows of 256 colours, brightest first),
  `:light_rows` (how many rows it has), `:background` (the colour behind every polygon),
  and `:view`, which `{:sky, ...}` reads. Light value `v` uses row
  `(255 - v) * light_rows / 256`, held inside the table.
  """

  alias Cauldron3D.Paint.Rgba
  alias Cauldron3D.{Setup, Texture, Vec, View}

  @type context :: %{optional(atom()) => term()}

  @doc """
  The colours of pixels `first` up to `stop` of row `y`, as a binary: a byte a pixel, or
  in a full-colour picture (a context with `:rgba`) four, as `Cauldron3D.Paint.Rgba`
  paints them.
  """
  @spec span(term(), Setup.t(), integer(), integer(), integer(), context()) :: binary()
  def span(paint, setup, first, stop, y, %{rgba: _} = context),
    do: Rgba.span(paint, setup, first, stop, y, context)

  def span({:flat, colour}, _setup, first, stop, _y, _context),
    do: :binary.copy(<<colour>>, stop - first)

  def span({:texture, %Texture{} = texture, nil}, setup, first, stop, y, _context) do
    {w, uw, vw} = row_planes(setup, y)
    %Texture{width: width, height: height, pixels: pixels} = texture

    for x <- first..(stop - 1)//1, into: <<>> do
      {u, v} = uv(w, uw, vw, x)
      <<:binary.at(pixels, Integer.mod(floor(v), height) * width + Integer.mod(floor(u), width))>>
    end
  end

  def span({:texture, %Texture{} = texture, light}, setup, first, stop, y, context) do
    {w, uw, vw} = row_planes(setup, y)
    %Texture{width: width, height: height, pixels: pixels} = texture
    table = context.light_table
    offset = light_row(light, context) * 256

    for x <- first..(stop - 1)//1, into: <<>> do
      {u, v} = uv(w, uw, vw, x)

      texel =
        :binary.at(pixels, Integer.mod(floor(v), height) * width + Integer.mod(floor(u), width))

      <<:binary.at(table, offset + texel)>>
    end
  end

  def span({:shaded, %Texture{} = texture}, setup, first, stop, y, context) do
    {w, uw, vw} = row_planes(setup, y)
    {l0, lx, ly} = setup.light
    light_origin = l0 + ly * (y + 0.5)
    %Texture{width: width, height: height, pixels: pixels} = texture
    table = context.light_table

    for x <- first..(stop - 1)//1, into: <<>> do
      {u, v} = uv(w, uw, vw, x)

      texel =
        :binary.at(pixels, Integer.mod(floor(v), height) * width + Integer.mod(floor(u), width))

      row = light_row(light_origin + lx * (x + 0.5), context)
      <<:binary.at(table, row * 256 + texel)>>
    end
  end

  def span({:surface, %Texture{} = texture}, setup, first, stop, y, _context) do
    {w, uw, vw} = row_planes(setup, y)
    %Texture{width: width, height: height, pixels: pixels} = texture
    {right, bottom} = {width - 1, height - 1}

    for x <- first..(stop - 1)//1, into: <<>> do
      {u, v} = uv(w, uw, vw, x)
      column = u |> floor() |> max(0) |> min(right)
      row = v |> floor() |> max(0) |> min(bottom)
      <<:binary.at(pixels, row * width + column)>>
    end
  end

  def span({:warp, %Texture{} = texture, opts}, setup, first, stop, y, context) do
    {w, uw, vw} = row_planes(setup, y)
    %Texture{width: width, height: height, pixels: pixels} = texture
    amplitude = Keyword.get(opts, :amplitude, 8.0)
    turn = 2 * :math.pi() / Keyword.get(opts, :wavelength, 128.0)
    phase = Keyword.get(opts, :time, 0.0) * Keyword.get(opts, :speed, 1.0) * 2 * :math.pi()
    lit = lighting(Keyword.get(opts, :light), context)

    for x <- first..(stop - 1)//1, into: <<>> do
      {u, v} = uv(w, uw, vw, x)
      su = u + amplitude * :math.sin(v * turn + phase)
      sv = v + amplitude * :math.sin(u * turn + phase)

      texel =
        :binary.at(pixels, Integer.mod(floor(sv), height) * width + Integer.mod(floor(su), width))

      <<lit.(texel)>>
    end
  end

  def span({:sky, layers, opts}, _setup, first, stop, y, context) do
    view = Map.fetch!(context, :view)
    time = Keyword.get(opts, :time, 0.0)
    clear = Keyword.get(opts, :clear, 0)
    scale = Keyword.get(opts, :scale, 378.0)
    flatten = Keyword.get(opts, :flatten, 3.0)

    for x <- first..(stop - 1)//1, into: <<>> do
      {dx, dy, dz} = View.ray(view, x, y)
      reach = scale / Vec.length({dx, dy, dz * flatten})
      <<sky_colour(layers, dx * reach, dy * reach, time, clear)>>
    end
  end

  def span({:fun, fun}, setup, first, stop, y, context), do: fun.(first, stop, y, setup, context)

  @doc "The light table row for light value `light` (0 to 255, brighter higher)."
  @spec light_row(number(), context()) :: non_neg_integer()
  def light_row(light, context) do
    rows = Map.get(context, :light_rows, 64)
    trunc((255 - light) * rows / 256) |> max(0) |> min(rows - 1)
  end

  defp lighting(nil, _context), do: & &1

  defp lighting(light, context) do
    table = context.light_table
    offset = light_row(light, context) * 256
    &:binary.at(table, offset + &1)
  end

  defp sky_colour([{texture, speed}], u, v, time, _clear),
    do: Texture.at(texture, floor(u + time * speed), floor(v + time * speed))

  defp sky_colour([{texture, speed} | deeper], u, v, time, clear) do
    case Texture.at(texture, floor(u + time * speed), floor(v + time * speed)) do
      ^clear -> sky_colour(deeper, u, v, time, clear)
      colour -> colour
    end
  end

  defp row_planes(%Setup{w: w, uw: uw, vw: vw}, y),
    do: {row_plane(w, y), row_plane(uw, y), row_plane(vw, y)}

  defp row_plane({origin, per_x, per_y}, y), do: {origin + per_y * (y + 0.5), per_x}

  defp uv({w0, wx}, {u0, ux}, {v0, vx}, x) do
    xc = x + 0.5
    w = w0 + wx * xc
    {(u0 + ux * xc) / w, (v0 + vx * xc) / w}
  end
end
