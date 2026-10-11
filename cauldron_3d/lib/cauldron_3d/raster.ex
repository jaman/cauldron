defmodule Cauldron3D.Raster do
  @moduledoc """
  Draws prepared polygons (`Cauldron3D.Setup`) into rows of pixels.

  Each row keeps the runs of pixels where one polygon is nearest; a polygon added to the
  row takes the pixels where it is nearer than what is there, found from its `:near`
  plane, so every pixel is painted once, by the polygon in front, whatever order the
  polygons come in. Where two are equally near the one added first keeps the pixel.
  See-through, blended and always-on-top setups (`Cauldron3D.Setup.overlay?/1`) are
  painted after, over the row: first the unblended, in the order given, each pixel taken
  where it is nearer than what is there and its alpha passes, keeping its own nearness;
  then the blended, in the order given, mixed over what is there where they are nearer,
  leaving the nearness as it was. In a picture in full colour the depth test reads the
  nearness of every overlay already drawn; in an indexed picture only that of the runs.

      Cauldron3D.Raster.rows(setups, 0..199, width, paint_context)
      #=> binary of 200 rows
  """

  alias Cauldron3D.Paint
  alias Cauldron3D.Paint.Rgba
  alias Cauldron3D.Setup

  @type run :: {non_neg_integer(), non_neg_integer(), Setup.t()}

  @doc """
  The pixels of `rows` (a range of row numbers) in a picture `width` wide, every row in
  turn, with `context` handed to `Cauldron3D.Paint.span/6`.
  """
  @spec rows([Setup.t()], Range.t(), pos_integer(), Paint.context()) :: binary()
  def rows(setups, first..last//1, width, context) do
    {overlays, solids} =
      setups
      |> Enum.filter(&(&1.bottom >= first and &1.top <= last))
      |> Enum.split_with(&Setup.overlay?/1)

    solid_rows = by_row(Enum.sort_by(solids, &(-&1.nearest)), first)
    overlay_rows = by_row(overlays, first)

    {pixels, _active} =
      Enum.reduce(first..last//1, {[], {[], []}}, fn y, {acc, {solid, over}} ->
        solid = live(Map.get(solid_rows, y, []) ++ solid, y)
        over = live(over ++ Map.get(overlay_rows, y, []), y)
        runs = runs(solid, y, width)
        base = row(runs, y, width, context)
        {[overlay(base, runs, over, y, width, context) | acc], {solid, over}}
      end)

    pixels |> Enum.reverse() |> IO.iodata_to_binary()
  end

  defp by_row(setups, first), do: Enum.group_by(setups, &max(&1.top, first))

  defp live(setups, y), do: Enum.filter(setups, &(&1.bottom >= y))

  @doc "The visible runs of row `y`, left to right, as `{first, last, setup}`."
  @spec runs([Setup.t()], integer(), pos_integer()) :: [run()]
  def runs(setups, y, width) do
    Enum.reduce(setups, [], fn setup, runs ->
      case Setup.span(setup, y, width) do
        nil -> runs
        {first, last} -> insert(runs, first, last + 1, setup, y)
      end
    end)
  end

  defp row(runs, y, width, context) do
    {parts, filled} =
      Enum.reduce(runs, {[], 0}, fn {first, stop, setup}, {acc, at} ->
        gap = if first > at, do: [background(context, y, at, first - at)], else: []
        {[Paint.span(setup.paint, setup, first, stop, y, context) | gap ++ acc], stop}
      end)

    tail = if filled < width, do: [background(context, y, filled, width - filled)], else: []
    Enum.reverse(tail ++ parts)
  end

  defp overlay(base, _runs, [], _y, _width, _context), do: base

  defp overlay(base, runs, overlays, y, width, %{rgba: _} = context) do
    base = IO.iodata_to_binary(base)
    {opaque, blended} = Enum.split_with(overlays, &Setup.opaque?/1)

    top =
      Enum.reduce(opaque ++ blended, %{}, fn setup, acc ->
        case Setup.span(setup, y, width) do
          nil -> acc
          {first, last} -> overlay_rgba(acc, base, setup, first, last, runs, y, context)
        end
      end)

    composite_rgba(top, base, width)
  end

  defp overlay(base, runs, overlays, y, width, context) do
    painted =
      Enum.reduce(overlays, %{}, fn setup, acc ->
        case Setup.span(setup, y, width) do
          nil -> acc
          {first, last} -> overlay_span(acc, setup, first, last, runs, y, context)
        end
      end)

    base = IO.iodata_to_binary(base)

    for x <- 0..(width - 1), into: <<>> do
      case painted do
        %{^x => colour} -> <<colour>>
        _ -> <<:binary.at(base, x)>>
      end
    end
  end

  defp composite_rgba(top, base, _width) when map_size(top) == 0, do: base

  defp composite_rgba(top, base, width) do
    for x <- 0..(width - 1), into: <<>> do
      case top do
        %{^x => {colour, _near}} -> colour
        _ -> binary_part(base, x * 4, 4)
      end
    end
  end

  defp overlay_span(painted, setup, first, last, runs, y, context) do
    colours = Paint.span(setup.paint, setup, first, last + 1, y, context)

    colours
    |> :binary.bin_to_list()
    |> Enum.with_index(first)
    |> Enum.reduce(painted, fn {colour, x}, acc ->
      if colour != setup.clear and in_front?(setup, runs, x, y),
        do: Map.put(acc, x, colour),
        else: acc
    end)
  end

  defp overlay_rgba(top, base, setup, first, last, runs, y, context) do
    colours = Paint.span(setup.paint, setup, first, last + 1, y, context)
    rules = %{threshold: alpha_threshold(setup), opaque?: Setup.opaque?(setup)}

    for(<<colour::binary-4 <- colours>>, do: colour)
    |> Enum.with_index(first)
    |> Enum.reduce(top, &cover(&2, &1, base, setup, rules, runs, y))
  end

  defp alpha_threshold(%{alpha_test: test, tint: nil}) when is_number(test), do: test * 255
  defp alpha_threshold(_setup), do: 0

  defp cover(top, {<<_, _, _, a>> = colour, x}, base, setup, rules, runs, y) do
    near = Setup.at(setup.near, x, y)
    {under, under_near} = under(top, base, runs, x, y)

    cond do
      a == 0 or a < rules.threshold -> top
      setup.depth != :always and near <= under_near -> top
      rules.opaque? -> Map.put(top, x, {opaque(colour), near})
      true -> Map.put(top, x, {mix({colour, setup.blend}, under), under_near})
    end
  end

  defp under(top, base, runs, x, y) do
    case top do
      %{^x => held} -> held
      _ -> {binary_part(base, x * 4, 4), solid_near(runs, x, y)}
    end
  end

  defp solid_near(runs, x, y) do
    case Enum.find(runs, fn {first, stop, _} -> x >= first and x < stop end) do
      nil -> -1.0e300
      {_, _, solid} -> Setup.at(solid.near, x, y)
    end
  end

  defp opaque(<<r, g, b, _a>>), do: <<r, g, b, 255>>

  defp mix({<<r, g, b, a>>, {:alpha, amount}}, under),
    do: blend(<<r, g, b>>, under, min(amount * a / 255, 1.0))

  defp mix({<<r, g, b, a>>, {:add, amount}}, <<ur, ug, ub, ua>>) do
    k = amount * a / 255
    <<min(ur + trunc(r * k), 255), min(ug + trunc(g * k), 255), min(ub + trunc(b * k), 255), ua>>
  end

  defp mix({<<r, g, b, a>>, {:premultiplied, amount}}, <<ur, ug, ub, ua>>) do
    k = 1 - min(amount * a / 255, 1.0)

    <<min(trunc(r * amount + ur * k), 255), min(trunc(g * amount + ug * k), 255),
      min(trunc(b * amount + ub * k), 255), ua>>
  end

  defp mix({<<r, g, b, _a>>, {:darken, amount}}, <<ur, ug, ub, ua>>),
    do:
      <<trunc(ur * (1 - min(amount * r / 255, 1.0))),
        trunc(ug * (1 - min(amount * g / 255, 1.0))),
        trunc(ub * (1 - min(amount * b / 255, 1.0))), ua>>

  defp blend(<<r, g, b>>, <<ur, ug, ub, ua>>, k),
    do:
      <<trunc(r * k + ur * (1 - k)), trunc(g * k + ug * (1 - k)), trunc(b * k + ub * (1 - k)),
        ua>>

  defp in_front?(%Setup{depth: :always}, _runs, _x, _y), do: true

  defp in_front?(setup, runs, x, y) do
    case Enum.find(runs, fn {first, stop, _} -> x >= first and x < stop end) do
      nil -> true
      {_, _, solid} -> Setup.at(setup.near, x, y) > Setup.at(solid.near, x, y)
    end
  end

  defp background(%{rgba: _, backdrop: {width, pixels}}, y, x, count),
    do: binary_part(pixels, (y * width + x) * 4, count * 4)

  defp background(%{rgba: _} = context, _y, _x, count),
    do:
      :binary.copy(
        Rgba.flat(Map.get(context, :background, {0, 0, 0}), context),
        count
      )

  defp background(context, _y, _x, count),
    do: :binary.copy(<<Map.get(context, :background, 0)>>, count)

  defp insert(runs, first, stop, setup, y), do: insert(runs, first, stop, setup, y, [])

  defp insert([], at, stop, setup, _y, acc) do
    Enum.reverse(if at < stop, do: [{at, stop, setup} | acc], else: acc)
  end

  defp insert(runs, at, stop, _setup, _y, acc) when at >= stop, do: Enum.reverse(acc, runs)

  defp insert([{_s0, s1, _q} = run | rest], at, stop, setup, y, acc) when s1 <= at,
    do: insert(rest, at, stop, setup, y, [run | acc])

  defp insert([{s0, _s1, _q} | _] = runs, at, stop, setup, y, acc) when s0 > at do
    gap_end = min(s0, stop)
    insert(runs, gap_end, stop, setup, y, [{at, gap_end, setup} | acc])
  end

  defp insert([{s0, s1, held} | rest], at, stop, setup, y, acc) do
    overlap_end = min(s1, stop)
    before = if s0 < at, do: [{s0, at, held}], else: []
    after_part = if overlap_end < s1, do: [{overlap_end, s1, held}], else: []
    contested = contest(at, overlap_end, held, setup, y)
    acc = Enum.reverse(before ++ contested, acc)
    insert(after_part ++ rest, overlap_end, stop, setup, y, acc)
  end

  defp contest(from, stop, held, setup, y) do
    {c, k} = difference(setup, held, y)
    first = c + k * (from + 0.5)
    last = c + k * (stop - 0.5)

    cond do
      first > 0 and last > 0 -> [{from, stop, setup}]
      first <= 0 and last <= 0 -> [{from, stop, held}]
      true -> split(from, stop, held, setup, c, k)
    end
  end

  defp split(from, stop, held, setup, c, k) do
    boundary = (floor(-c / k - 0.5) + 1) |> max(from + 1) |> min(stop - 1)

    if k > 0,
      do: [{from, boundary, held}, {boundary, stop, setup}],
      else: [{from, boundary, setup}, {boundary, stop, held}]
  end

  defp difference(%Setup{near: {a0, ax, ay}}, %Setup{near: {b0, bx, by}}, y),
    do: {a0 - b0 + (ay - by) * (y + 0.5), ax - bx}
end
