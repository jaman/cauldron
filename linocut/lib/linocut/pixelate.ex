defmodule Linocut.Pixelate do
  @moduledoc """
  A painted or generated picture made into pixel art: its background keyed out, its true
  pixel grid found and sampled, its colours held to a palette, dithered where asked, and
  outlined.

      Linocut.Pixelate.finish(picture,
        key: {255, 0, 255},
        size: {32, 32},
        palette: 16,
        dither: :bayer4,
        outline: {20, 12, 28}
      )

  A picture a model drew "in pixel art" is usually pixel art drawn large and blurred:
  blocks of near-equal colour several pixels across, not always on whole-number edges.
  `grid/1` finds the size and offset of those blocks; `sample/3` takes each block's
  commonest colour, so a block becomes one clean pixel.

  ## Options of `finish/2`

    * `:key` — the background to make clear: `{r, g, b}`, that colour wherever it is,
      or `:border`, the commonest colour of the picture's edge, cleared only where it
      reaches the edge, so the same colour inside the subject stays. `:tolerance`
      (0–441, the distance in RGB within which a colour counts as the key; default 60)
    * `:size` — `{width, height}` of the result, or `:grid` (default) to sample at the
      grid `grid/1` finds
    * `:palette` — a list of `{r, g, b}` to hold every colour to, or a count of colours to
      choose from the picture (`Linocut.Quantise`). Default: the picture's own colours
    * `:dither` — `:none` (default), `:bayer2` or `:bayer4`: ordered dithering between the
      two nearest palette colours, for gradients a small palette cannot hold
    * `:alpha` — the alpha at or above which a pixel stays; below it, it is clear.
      Default `128`; every pixel left is made fully opaque
    * `:outline` — `{r, g, b}` drawn on every clear pixel beside an opaque one. Default none
    * `:trim` — cut the result to its opaque pixels. Default `true`
    * `:fit` — `{width, height}`, the most the result may be each way: a larger one is
      shrunk, keeping its shape, pixel for nearest pixel. Default none
  """

  alias FrenchCurve.Raster
  alias Linocut.Quantise

  @fringe 2.4
  @fringe_reach 4
  @pocket 0.7
  @bayer2 [[0, 2], [3, 1]]
  @bayer4 [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

  @type rgb :: {byte(), byte(), byte()}
  @type grid :: %{cell: {number(), number()}, offset: {number(), number()}}

  @doc "The picture made into pixel art; see the module documentation."
  @spec finish(Raster.t(), keyword()) :: Raster.t()
  def finish(%Raster{} = raster, opts \\ []) do
    raster
    |> keyed(opts[:key], Keyword.get(opts, :tolerance, 60))
    |> sized(Keyword.get(opts, :size, :grid))
    |> solid(Keyword.get(opts, :alpha, 128))
    |> paletted(opts[:palette], Keyword.get(opts, :dither, :none))
    |> outlined(opts[:outline])
    |> trimmed(Keyword.get(opts, :trim, true))
    |> fitted(opts[:fit])
  end

  @doc "`raster` cut to the smallest rectangle holding every opaque pixel; a raster with none is left as it is."
  @spec trim(Raster.t()) :: Raster.t()
  def trim(%Raster{width: width} = raster) do
    opaque =
      for {<<_r, _g, _b, a>>, index} <-
            raster |> Raster.to_rgba_binary() |> chunks() |> Enum.with_index(),
          a > 0,
          do: {rem(index, width), div(index, width)}

    case opaque do
      [] ->
        raster

      points ->
        {xs, ys} = Enum.unzip(points)
        {left, top} = {Enum.min(xs), Enum.min(ys)}
        Raster.crop(raster, {left, top}, {Enum.max(xs) - left + 1, Enum.max(ys) - top + 1})
    end
  end

  defp trimmed(raster, true), do: trim(raster)
  defp trimmed(raster, false), do: raster

  defp fitted(raster, nil), do: raster

  defp fitted(%Raster{width: width, height: height} = raster, {most_w, most_h}) do
    scale = min(1.0, min(most_w / width, most_h / height))
    size = {max(1, round(width * scale)), max(1, round(height * scale))}
    Linocut.Resample.to(raster, size, mode: :nearest)
  end

  @doc """
  The block size and offset of the pixel art drawn large in `raster`, each way: the
  period, from 2 to `:most` (default 32) pixels and not always a whole number, at which
  the picture's colour changes repeat most strongly, and where the first block starts.
  A picture with no such period has cells of one pixel. With `square: true` (the
  default) the pixels are taken to be square, and both ways take the period found
  the more clearly.
  """
  @spec grid(Raster.t(), keyword()) :: grid()
  def grid(%Raster{} = raster, opts \\ []) do
    most = Keyword.get(opts, :most, 32)
    pixels = pixels(raster)
    columns = column_edges(pixels, raster)
    rows = row_edges(pixels, raster)
    {across, left, across_strength} = period(columns, most)
    {down, top, down_strength} = period(rows, most)

    cond do
      not Keyword.get(opts, :square, true) ->
        %{cell: {across, down}, offset: {left, top}}

      across_strength >= down_strength ->
        %{cell: {across, across}, offset: {left, phase_at(rows, across)}}

      true ->
        %{cell: {down, down}, offset: {phase_at(columns, down), top}}
    end
  end

  defp phase_at(edges, period) do
    {c, s} = edges |> Enum.with_index(1) |> wave(period)
    phase(c, s, period)
  end

  @doc """
  `raster` sampled down to one pixel per cell of `grid`, each the commonest opaque colour
  in its cell, or clear where most of the cell is clear.
  """
  @spec sample(Raster.t(), grid()) :: Raster.t()
  def sample(%Raster{} = raster, %{cell: {cw, ch}, offset: {ox, oy}}) do
    pixels = pixels(raster)
    width = max(1, round((raster.width - ox) / cw))
    height = max(1, round((raster.height - oy) / ch))

    rgba =
      for y <- 0..(height - 1), x <- 0..(width - 1), into: <<>> do
        pixels |> block(raster, {ox + x * cw, oy + y * ch}, {cw, ch}) |> commonest()
      end

    Raster.from_rgba(width, height, rgba)
  end

  defp block(pixels, raster, {left, top}, {cw, ch}) do
    {x0, x1} = inner(left, cw)
    {y0, y1} = inner(top, ch)
    for y <- y0..y1, x <- x0..x1, do: at(pixels, raster, x, y)
  end

  defp inner(start, size) do
    margin = size * 0.2
    first = round(start + margin)
    {first, max(first, round(start + size - margin) - 1)}
  end

  @doc "`raster` with every pixel within `tolerance` of `key` made clear."
  @spec key_out(Raster.t(), rgb(), number()) :: Raster.t()
  def key_out(%Raster{} = raster, {kr, kg, kb}, tolerance) do
    limit = tolerance * tolerance

    rgba =
      for <<r, g, b, a <- Raster.to_rgba_binary(raster)>>, into: <<>> do
        distance = (r - kr) ** 2 + (g - kg) ** 2 + (b - kb) ** 2
        if distance <= limit, do: <<0, 0, 0, 0>>, else: <<r, g, b, a>>
      end

    Raster.from_rgba(raster.width, raster.height, rgba)
  end

  @doc "`raster` with every opaque colour moved to `palette`, dithered by `pattern` (`:none`, `:bayer2`, `:bayer4`)."
  @spec to_palette(Raster.t(), [rgb()], :none | :bayer2 | :bayer4) :: Raster.t()
  def to_palette(%Raster{} = raster, palette, :none),
    do: Quantise.to_palette(raster, palette, alpha: 1)

  def to_palette(%Raster{width: width} = raster, palette, pattern) do
    matrix = matrix(pattern)
    size = length(matrix)
    levels = size * size

    rgba =
      raster
      |> Raster.to_rgba_binary()
      |> chunks()
      |> Enum.with_index()
      |> Enum.map(fn
        {<<_r, _g, _b, 0>> = clear, _index} ->
          clear

        {<<r, g, b, a>>, index} ->
          {x, y} = {rem(index, width), div(index, width)}
          threshold = (matrix |> Enum.at(rem(y, size)) |> Enum.at(rem(x, size))) / levels
          {cr, cg, cb} = dithered(palette, {r, g, b}, threshold)
          <<cr, cg, cb, a>>
      end)
      |> IO.iodata_to_binary()

    Raster.from_rgba(width, raster.height, rgba)
  end

  @doc "`raster` with `colour` on every clear pixel that touches an opaque one across or down."
  @spec outline(Raster.t(), rgb()) :: Raster.t()
  def outline(%Raster{width: width, height: height} = raster, {r, g, b}) do
    pixels = pixels(raster)

    rgba =
      for y <- 0..(height - 1), x <- 0..(width - 1), into: <<>> do
        pixel = at(pixels, raster, x, y)
        if edge?(pixels, raster, pixel, {x, y}), do: <<r, g, b, 255>>, else: pixel
      end

    Raster.from_rgba(width, height, rgba)
  end

  defp edge?(pixels, raster, pixel, {x, y}) do
    alpha(pixel) == 0 and
      Enum.any?([{1, 0}, {-1, 0}, {0, 1}, {0, -1}], fn {dx, dy} ->
        alpha(at(pixels, raster, x + dx, y + dy)) > 0
      end)
  end

  defp keyed(raster, nil, _tolerance), do: raster
  defp keyed(raster, :border, tolerance), do: key_border(raster, tolerance)
  defp keyed(raster, key, tolerance), do: key_out(raster, key, tolerance)

  @doc """
  `raster` with its background cleared: the commonest colour on its edge, and every
  pixel within `tolerance` of it that is joined to the edge through others like it, and
  every pixel anywhere very close to it, background caught inside the subject, and
  then the fringe a model blends between background and subject — up to four pixels in
  from the cleared ground, each still within a wider tolerance of the background.
  """
  @spec key_border(Raster.t(), number()) :: Raster.t()
  def key_border(%Raster{width: width, height: height} = raster, tolerance) do
    pixels = pixels(raster)
    edge = edge_points(width, height)

    key =
      edge
      |> Enum.map(fn {x, y} -> rounded(at(pixels, raster, x, y)) end)
      |> Enum.frequencies()
      |> Enum.max_by(&elem(&1, 1))
      |> elem(0)

    {kr, kg, kb} = key
    limit = tolerance * tolerance

    near? = fn <<r, g, b, _a>> ->
      (r - kr * 12) ** 2 + (g - kg * 12) ** 2 + (b - kb * 12) ** 2 <= limit
    end

    starts = Enum.filter(edge, fn {x, y} -> near?.(at(pixels, raster, x, y)) end)

    background =
      flood(
        starts,
        MapSet.new(starts),
        fn {x, y} -> near?.(at(pixels, raster, x, y)) end,
        {width, height}
      )

    tinged? = fn {x, y} ->
      <<r, g, b, _a>> = at(pixels, raster, x, y)
      (r - kr * 12) ** 2 + (g - kg * 12) ** 2 + (b - kb * 12) ** 2 <= limit * @fringe * @fringe
    end

    pockets =
      for y <- 0..(height - 1),
          x <- 0..(width - 1),
          keyed?(
            at(pixels, raster, x, y),
            {kr * 12, kg * 12, kb * 12},
            limit * @pocket * @pocket
          ),
          into: background,
          do: {x, y}

    cleared = fringe(pockets, tinged?, {width, height}, @fringe_reach)

    rgba =
      for y <- 0..(height - 1), x <- 0..(width - 1), into: <<>> do
        if MapSet.member?(cleared, {x, y}), do: <<0, 0, 0, 0>>, else: at(pixels, raster, x, y)
      end

    Raster.from_rgba(width, height, rgba)
  end

  defp keyed?(<<r, g, b, _a>>, {kr, kg, kb}, limit),
    do: (r - kr) ** 2 + (g - kg) ** 2 + (b - kb) ** 2 <= limit

  defp fringe(cleared, _tinged?, _size, 0), do: cleared

  defp fringe(cleared, tinged?, {width, height} = size, reach) do
    ring =
      for {x, y} <- cleared,
          {dx, dy} <- [{1, 0}, {-1, 0}, {0, 1}, {0, -1}],
          point = {x + dx, y + dy},
          inside?(point, width, height),
          not MapSet.member?(cleared, point),
          tinged?.(point),
          uniq: true,
          do: point

    case ring do
      [] -> cleared
      ring -> fringe(Enum.into(ring, cleared), tinged?, size, reach - 1)
    end
  end

  defp edge_points(width, height) do
    across = for x <- 0..(width - 1), y <- [0, height - 1], do: {x, y}
    down = for y <- 1..(height - 2)//1, x <- [0, width - 1], do: {x, y}
    across ++ down
  end

  defp flood([], seen, _near?, _size), do: seen

  defp flood(frontier, seen, near?, {width, height} = size) do
    next =
      for {x, y} <- frontier,
          {dx, dy} <- [{1, 0}, {-1, 0}, {0, 1}, {0, -1}],
          point = {x + dx, y + dy},
          inside?(point, width, height),
          not MapSet.member?(seen, point),
          near?.(point),
          uniq: true,
          do: point

    flood(next, Enum.into(next, seen), near?, size)
  end

  defp inside?({x, y}, width, height), do: x >= 0 and y >= 0 and x < width and y < height

  defp sized(raster, :grid), do: sample(raster, grid(raster))

  defp sized(raster, {width, height}),
    do: sample(raster, %{cell: {raster.width / width, raster.height / height}, offset: {0, 0}})

  defp solid(raster, threshold) do
    rgba =
      for <<r, g, b, a <- Raster.to_rgba_binary(raster)>>, into: <<>> do
        if a >= threshold, do: <<r, g, b, 255>>, else: <<0, 0, 0, 0>>
      end

    Raster.from_rgba(raster.width, raster.height, rgba)
  end

  defp paletted(raster, nil, _dither), do: raster

  defp paletted(raster, count, dither) when is_integer(count),
    do: paletted(raster, Quantise.palette(raster, count), dither)

  defp paletted(raster, palette, dither) when is_list(palette),
    do: to_palette(raster, palette, dither)

  defp outlined(raster, nil), do: raster
  defp outlined(raster, colour), do: outline(raster, colour)

  defp matrix(:bayer2), do: @bayer2
  defp matrix(:bayer4), do: @bayer4

  defp dithered(palette, colour, threshold) do
    [first, second | _] = Enum.sort_by(palette, &distance(&1, colour)) ++ [nil]

    case second do
      nil ->
        first

      second ->
        near = :math.sqrt(distance(first, colour))
        far = :math.sqrt(distance(second, colour))
        share = if near + far == 0, do: 0.0, else: near / (near + far)
        if share > threshold, do: second, else: first
    end
  end

  defp distance({r, g, b}, {r2, g2, b2}), do: (r - r2) ** 2 + (g - g2) ** 2 + (b - b2) ** 2

  defp pixels(raster), do: Raster.to_rgba_binary(raster)

  defp at(_pixels, %{width: w, height: h}, x, y) when x < 0 or y < 0 or x >= w or y >= h,
    do: <<0, 0, 0, 0>>

  defp at(pixels, %{width: w}, x, y), do: binary_part(pixels, (y * w + x) * 4, 4)

  defp alpha(<<_r, _g, _b, a>>), do: a

  defp chunks(rgba), do: for(<<pixel::binary-4 <- rgba>>, do: pixel)

  defp commonest(block) do
    {clear, opaque} = Enum.split_with(block, &(alpha(&1) < 128))

    if length(clear) > length(opaque) do
      <<0, 0, 0, 0>>
    else
      opaque
      |> Enum.frequencies_by(&rounded/1)
      |> Enum.max_by(&elem(&1, 1))
      |> elem(0)
      |> then(&mean_of(opaque, &1))
    end
  end

  defp rounded(<<r, g, b, _a>>), do: {div(r, 12), div(g, 12), div(b, 12)}

  defp mean_of(pixels, bucket) do
    members = Enum.filter(pixels, &(rounded(&1) == bucket))
    count = length(members)

    {r, g, b} =
      Enum.reduce(members, {0, 0, 0}, fn <<r, g, b, _a>>, {ar, ag, ab} ->
        {ar + r, ag + g, ab + b}
      end)

    <<div(r, count), div(g, count), div(b, count), 255>>
  end

  defp column_edges(pixels, %{width: w, height: h} = raster) do
    for x <- 1..(w - 1)//1 do
      Enum.reduce(0..(h - 1)//1, 0, fn y, acc ->
        acc + change(at(pixels, raster, x - 1, y), at(pixels, raster, x, y))
      end)
    end
  end

  defp row_edges(pixels, %{width: w, height: h} = raster) do
    for y <- 1..(h - 1)//1 do
      Enum.reduce(0..(w - 1)//1, 0, fn x, acc ->
        acc + change(at(pixels, raster, x, y - 1), at(pixels, raster, x, y))
      end)
    end
  end

  defp change(<<r, g, b, a>>, <<r2, g2, b2, a2>>),
    do: abs(r - r2) + abs(g - g2) + abs(b - b2) + abs(a - a2)

  defp period(edges, most) do
    total = Enum.sum(edges)
    indexed = Enum.with_index(edges, 1)

    with true <- total > 0,
         {coarse, strength} when strength >= 0.2 <-
           strongest(indexed, total, for(t <- 20..(most * 10), do: t / 10)),
         {fine, peak} <- strongest(indexed, total, around(coarse, 0.15)) do
      chosen = fundamental(indexed, total, {fine, peak}, most)
      {c, s} = wave(indexed, chosen)
      {chosen, phase(c, s, chosen), peak}
    else
      _none -> {1, 0, 0.0}
    end
  end

  defp around(period, reach) do
    steps = round(reach * 100)
    for h <- -steps..steps, do: period + h / 100
  end

  defp fundamental(indexed, total, {period, peak}, most) do
    [3, 2]
    |> Enum.filter(&(period * &1 <= most))
    |> Enum.map(&strongest(indexed, total, around(period * &1, 0.3)))
    |> Enum.find({period, peak}, fn {_longer, strength} -> strength >= peak * 0.6 end)
    |> elem(0)
  end

  defp strongest(indexed, total, periods) do
    periods
    |> Enum.filter(&(&1 >= 2))
    |> Enum.map(fn period ->
      {c, s} = wave(indexed, period)
      {period, :math.sqrt(c * c + s * s) / total}
    end)
    |> Enum.max_by(&elem(&1, 1))
  end

  defp wave(indexed, period) do
    step = 2 * :math.pi() / period

    Enum.reduce(indexed, {0.0, 0.0}, fn {edge, x}, {c, s} ->
      {c + edge * :math.cos(step * x), s + edge * :math.sin(step * x)}
    end)
  end

  defp phase(c, s, period) do
    shift = :math.atan2(s, c) / (2 * :math.pi()) * period
    within = shift - Float.floor(shift / period) * period
    if within > period / 2, do: within - period, else: within
  end
end
