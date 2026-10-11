defmodule Cauldron3D.Paint.Rgba do
  @moduledoc """
  The paints of `Cauldron3D.Paint` in RGBA, four bytes a pixel, for a picture drawn in
  full colour (`Cauldron3D.Render.draw/3` with `:palette`).

  An indexed texture's colours come from its own palette, or the picture's. Light 128 is
  a texture's own colours; light scales red, green and blue alike, or each by its own
  amount where a paint gives `{r, g, b}` light. A texel of the setup's `clear` index is
  alpha 0, which the overlays leave out. A surface is an RGBA texture already lit.

  A setup with a tint has each pixel's colour and alpha multiplied by it; where it also
  has an `alpha_test`, a pixel whose own alpha is below the test is alpha 0 first.

  `{:warp, ...}`'s `:amplitude` and `:wavelength` may each be `{s, t}`: the move along
  `s` (by the sine of `t`) and the move along `t` (by the sine of `s`).

  Besides `Cauldron3D.Paint`'s paints:

    * `{:skybox, faces}` — a sky at no distance from six RGBA textures, `faces` a map
      with `:front` (looking along +x), `:back`, `:left` (+y), `:right`, `:up` (+z) and
      `:down`, each seen from inside the box with up toward +z (`:up` and `:down` with
      their top toward +x)
    * `{:lit, paint, lighting}` — `paint` (with the setup's tint) and, added to it, the
      light of each of `lighting.lights` (`%{origin:, radius:, colour: {r, g, b}}`, and
      for a spot light `fov:` in degrees with `axes: {forward, right, up}`) on a flat
      surface of normal `lighting.normal`: at the pixel's place `p` in a perspective
      view, with `l` the light's origin less `p`, each channel of the texel of
      `lighting.texture` at the paint's place plus `lighting.offset` (alpha 0 where it
      is colour `lighting.clear`) times
      `max(normal · l / |l|, 0) * max(1 - |l|² / radius², 0)` (times
      `1 - x² - y²` for a spot, `x` and `y` being `p`'s place across and up the light's
      view over its distance along `forward` times `tan(fov / 2)`, and nothing behind
      it) times the colour times the texel's alpha, each light's share held at 0 or above
  """

  alias Cauldron3D.{Setup, Texture, Vec, View}

  @clear <<0, 0, 0, 0>>

  @doc """
  The RGBA bytes of pixels `first` up to `stop` of row `y`, each multiplied by the
  setup's tint there when it has one.
  """
  @spec span(term(), Setup.t(), integer(), integer(), integer(), map()) :: binary()
  def span({:lit, paint, lighting}, setup, first, stop, y, context) do
    base = span(paint, setup, first, stop, y, context)
    view = Map.fetch!(context, :view)
    {w, uw, vw} = row_planes(setup, y)
    texture = lighting.texture
    colours = colours(texture, context)
    {du, dv} = lighting.offset
    clear = Map.get(lighting, :clear)

    for {pixel, x} <- Enum.with_index(words(base), first), into: <<>> do
      {u, v} = uv(w, uw, vw, x)
      place = place(view, x, y, w)
      <<tr, tg, tb, ta>> = texel(texture, colours, floor(u) + du, floor(v) + dv, clear, nil)

      {lr, lg, lb} =
        Enum.reduce(lighting.lights, {0.0, 0.0, 0.0}, &add_light(&1, &2, place, lighting.normal))

      k = ta / 255
      <<r, g, b, a>> = pixel
      <<channel(r + tr * lr * k), channel(g + tg * lg * k), channel(b + tb * lb * k), a>>
    end
  end

  def span(paint, %Setup{tint: {rp, gp, bp, ap}} = setup, first, stop, y, context) do
    base = span(paint, %{setup | tint: nil}, first, stop, y, context)
    {w0, wx} = row_plane(setup.w, y)
    {r0, rx} = row_plane(rp, y)
    {g0, gx} = row_plane(gp, y)
    {b0, bx} = row_plane(bp, y)
    {a0, ax} = row_plane(ap, y)
    threshold = if setup.alpha_test, do: setup.alpha_test * 255, else: 0

    for {<<r, g, b, a>>, x} <- Enum.with_index(words(base), first), into: <<>> do
      xc = x + 0.5
      w = w0 + wx * xc

      if a < threshold,
        do: @clear,
        else:
          <<channel(r * (r0 + rx * xc) / w), channel(g * (g0 + gx * xc) / w),
            channel(b * (b0 + bx * xc) / w), channel(a * (a0 + ax * xc) / w)>>
    end
  end

  def span({:flat, colour}, _setup, first, stop, _y, context),
    do: :binary.copy(flat(colour, context), stop - first)

  def span({:texture, %Texture{} = texture, light}, setup, first, stop, y, context) do
    {w, uw, vw} = row_planes(setup, y)
    colours = colours(texture, context)
    clear = setup.clear
    scale = light_scale(light)

    for x <- first..(stop - 1)//1, into: <<>> do
      {u, v} = uv(w, uw, vw, x)
      texel(texture, colours, floor(u), floor(v), clear, scale)
    end
  end

  def span({:shaded, %Texture{} = texture}, setup, first, stop, y, context) do
    {w, uw, vw} = row_planes(setup, y)
    {l0, lx, ly} = setup.light
    light_origin = l0 + ly * (y + 0.5)
    colours = colours(texture, context)
    clear = setup.clear

    for x <- first..(stop - 1)//1, into: <<>> do
      {u, v} = uv(w, uw, vw, x)
      texel(texture, colours, floor(u), floor(v), clear, (light_origin + lx * (x + 0.5)) / 128)
    end
  end

  def span({:surface, %Texture{} = texture}, setup, first, stop, y, context) do
    {w, uw, vw} = row_planes(setup, y)
    {right, bottom} = {texture.width - 1, texture.height - 1}
    colours = colours(texture, context)

    for x <- first..(stop - 1)//1, into: <<>> do
      {u, v} = uv(w, uw, vw, x)
      column = u |> floor() |> max(0) |> min(right)
      row = v |> floor() |> max(0) |> min(bottom)
      pixel(texture, colours, column, row)
    end
  end

  def span({:warp, %Texture{} = texture, opts}, setup, first, stop, y, context) do
    {w, uw, vw} = row_planes(setup, y)
    {amplitude_s, amplitude_t} = pair(Keyword.get(opts, :amplitude, 8.0))
    {wavelength_s, wavelength_t} = pair(Keyword.get(opts, :wavelength, 128.0))
    {turn_s, turn_t} = {2 * :math.pi() / wavelength_s, 2 * :math.pi() / wavelength_t}
    phase = Keyword.get(opts, :time, 0.0) * Keyword.get(opts, :speed, 1.0) * 2 * :math.pi()
    scale = light_scale(Keyword.get(opts, :light))
    colours = colours(texture, context)

    for x <- first..(stop - 1)//1, into: <<>> do
      {u, v} = uv(w, uw, vw, x)
      su = u + amplitude_s * :math.sin(v * turn_s + phase)
      sv = v + amplitude_t * :math.sin(u * turn_t + phase)
      texel(texture, colours, floor(su), floor(sv), nil, scale)
    end
  end

  def span({:sky, layers, opts}, _setup, first, stop, y, context) do
    view = Map.fetch!(context, :view)
    time = Keyword.get(opts, :time, 0.0)
    clear = Keyword.get(opts, :clear, 0)
    reach_scale = Keyword.get(opts, :scale, 378.0)
    flatten = Keyword.get(opts, :flatten, 3.0)

    for x <- first..(stop - 1)//1, into: <<>> do
      {dx, dy, dz} = View.ray(view, x, y)
      reach = reach_scale / :math.sqrt(dx * dx + dy * dy + dz * flatten * dz * flatten)
      sky(layers, dx * reach, dy * reach, time, clear, context)
    end
  end

  def span({:skybox, faces}, _setup, first, stop, y, context) do
    view = Map.fetch!(context, :view)
    for x <- first..(stop - 1)//1, into: <<>>, do: box(faces, View.ray(view, x, y))
  end

  def span({:fun, fun}, setup, first, stop, y, context), do: fun.(first, stop, y, setup, context)

  @doc "A colour, a palette index or `{r, g, b}`, as RGBA bytes in `context`'s palette."
  @spec flat(byte() | {byte(), byte(), byte()}, map()) :: binary()
  def flat({r, g, b}, _context), do: <<r, g, b, 255>>
  def flat(index, context), do: elem(context.rgba, index)

  defp colours(%Texture{colours: nil}, context), do: context.rgba
  defp colours(%Texture{colours: colours}, _context), do: colours

  defp texel(%Texture{format: :rgba} = texture, _colours, u, v, _clear, scale) do
    %Texture{width: width, height: height, pixels: pixels} = texture
    at = (Integer.mod(v, height) * width + Integer.mod(u, width)) * 4
    <<_::binary-size(^at), r, g, b, a, _::binary>> = pixels
    lit(<<r, g, b, a>>, scale)
  end

  defp texel(texture, colours, u, v, clear, scale) do
    %Texture{width: width, height: height, pixels: pixels} = texture
    index = :binary.at(pixels, Integer.mod(v, height) * width + Integer.mod(u, width))
    if index == clear, do: @clear, else: lit(elem(colours, index), scale)
  end

  defp pixel(%Texture{format: :rgba, width: width, pixels: pixels}, _colours, column, row),
    do: binary_part(pixels, (row * width + column) * 4, 4)

  defp pixel(%Texture{width: width, pixels: pixels}, colours, column, row),
    do: elem(colours, :binary.at(pixels, row * width + column))

  defp lit(colour, nil), do: colour

  defp lit(<<r, g, b, a>>, {sr, sg, sb}),
    do: <<channel(r * sr), channel(g * sg), channel(b * sb), a>>

  defp lit(<<r, g, b, a>>, scale),
    do: <<channel(r * scale), channel(g * scale), channel(b * scale), a>>

  defp channel(value) when value >= 255, do: 255
  defp channel(value) when value <= 0, do: 0
  defp channel(value), do: trunc(value)

  defp light_scale(nil), do: nil
  defp light_scale({r, g, b}), do: {r / 128, g / 128, b / 128}
  defp light_scale(light), do: light / 128

  defp sky([{texture, speed}], u, v, time, _clear, context),
    do:
      texel(
        texture,
        colours(texture, context),
        floor(u + time * speed),
        floor(v + time * speed),
        nil,
        nil
      )

  defp sky([{texture, speed} | deeper], u, v, time, clear, context) do
    index = Texture.at(texture, floor(u + time * speed), floor(v + time * speed))

    if index == clear,
      do: sky(deeper, u, v, time, clear, context),
      else: elem(colours(texture, context), index)
  end

  defp box(faces, direction) do
    {face, s, t} = box_face(direction)

    case Map.get(faces, face) do
      %Texture{width: w, height: h} = texture ->
        column = trunc((s + 1) / 2 * w) |> max(0) |> min(w - 1)
        row = trunc((t + 1) / 2 * h) |> max(0) |> min(h - 1)
        pixel(texture, texture.colours, column, row)

      nil ->
        <<0, 0, 0, 255>>
    end
  end

  defp box_face({dx, dy, dz}), do: box_face({dx, dy, dz}, {abs(dx), abs(dy), abs(dz)})

  defp box_face({dx, dy, dz}, {ax, ay, az}) when ax >= ay and ax >= az and dx > 0,
    do: {:front, -dy / ax, -dz / ax}

  defp box_face({_dx, dy, dz}, {ax, ay, az}) when ax >= ay and ax >= az,
    do: {:back, dy / ax, -dz / ax}

  defp box_face({dx, dy, dz}, {_ax, ay, az}) when ay >= az and dy > 0,
    do: {:left, dx / ay, -dz / ay}

  defp box_face({dx, _dy, dz}, {_ax, ay, az}) when ay >= az,
    do: {:right, -dx / ay, -dz / ay}

  defp box_face({dx, dy, dz}, {_ax, _ay, az}) when dz > 0,
    do: {:up, -dy / az, dx / az}

  defp box_face({dx, dy, _dz}, {_ax, _ay, az}),
    do: {:down, -dy / az, -dx / az}

  defp words(binary), do: for(<<word::binary-4 <- binary>>, do: word)

  defp pair({s, t}), do: {s, t}
  defp pair(both), do: {both, both}

  defp place(view, x, y, {w0, wx}) do
    depth = 1 / (w0 + wx * (x + 0.5))
    View.ray(view, x, y) |> Vec.scale(depth) |> Vec.add(view.origin)
  end

  defp add_light(light, {r, g, b}, place, normal) do
    to_light = Vec.sub(light.origin, place)
    squared = Vec.dot(to_light, to_light)
    radius = light.radius

    if squared >= radius * radius or squared == 0 do
      {r, g, b}
    else
      facing = max(Vec.dot(normal, to_light) / :math.sqrt(squared), 0.0)
      scale = max(facing * (1 - squared / (radius * radius)) * spot(light, place), 0.0)
      {cr, cg, cb} = light.colour
      {r + cr * scale, g + cg * scale, b + cb * scale}
    end
  end

  defp spot(%{fov: fov, axes: {forward, right, up}, origin: origin}, place) when fov > 0 do
    offset = Vec.sub(place, origin)
    along = Vec.dot(offset, forward)

    if along <= 0 do
      0.0
    else
      reach = along * :math.tan(fov * :math.pi() / 360)
      across = Vec.dot(offset, right) / reach
      upward = Vec.dot(offset, up) / reach
      1 - across * across - upward * upward
    end
  end

  defp spot(_light, _place), do: 1.0

  defp row_planes(%Setup{w: w, uw: uw, vw: vw}, y),
    do: {row_plane(w, y), row_plane(uw, y), row_plane(vw, y)}

  defp row_plane({origin, per_x, per_y}, y), do: {origin + per_y * (y + 0.5), per_x}

  defp uv({w0, wx}, {u0, ux}, {v0, vx}, x) do
    xc = x + 0.5
    w = w0 + wx * xc
    {(u0 + ux * xc) / w, (v0 + vx * xc) / w}
  end
end
