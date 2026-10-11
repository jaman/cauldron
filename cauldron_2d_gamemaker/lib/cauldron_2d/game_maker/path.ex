defmodule Cauldron2D.GameMaker.Path do
  @moduledoc """
  A path (a `PATH` entry): `points`, each `{x, y, speed}` with speed a percentage of the
  speed the path is followed at. `smooth` paths curve through their points `precision`
  times between each pair; `closed` paths join their last point to their first.

  `position/2` is where a path is at a fraction of its length (`path_get_x`,
  `path_get_y`, `path_get_speed`).
  """

  alias Cauldron2D.GameMaker.Bytes

  @enforce_keys [:name, :points]
  defstruct [:name, :smooth, :closed, :precision, points: []]

  @type t :: %__MODULE__{
          name: String.t(),
          smooth: boolean(),
          closed: boolean(),
          precision: non_neg_integer(),
          points: [{number(), number(), number()}]
        }

  @doc "The path at `at`."
  @spec read(binary(), non_neg_integer()) :: t()
  def read(data, at) do
    [_name, smooth, closed, precision, count] = Bytes.u32s(data, at, 5)

    %__MODULE__{
      name: Bytes.string_at(data, at),
      smooth: smooth != 0,
      closed: closed != 0,
      precision: precision,
      points: points(binary_part(data, at + 20, count * 12))
    }
  end

  @doc """
  `{x, y, speed}` at fraction `at` (0–1) of the path's length, as GameMaker computes it:
  a smooth path is first broken into the points of its curve — from its first point, the
  middle of each corner (the quarter-weighted mean of the midpoints and the corner)
  subdivided `precision` times while a half is longer than 4 pixels, to its last point —
  and the position lies along the straight lines between them. `{0, 0, 0}` for a path
  without points.
  """
  @spec position(t(), number()) :: {number(), number(), number()}
  def position(%__MODULE__{points: []}, _at), do: {0, 0, 0}

  def position(%__MODULE__{} = path, at) do
    inner = inner_points(path)
    lengths = lengths(inner)
    total = List.last(lengths)

    cond do
      length(inner) == 1 or total == 0 or at <= 0 -> hd(inner)
      at >= 1 -> List.last(inner)
      true -> along(Enum.zip(inner, lengths), total * at)
    end
  end

  defp along(points, distance) do
    pairs = Enum.zip(points, tl(points))
    count = length(pairs)

    {{{x1, y1, s1}, from}, {{x2, y2, s2}, to}} =
      pairs
      |> Enum.with_index()
      |> Enum.find_value(fn {{_a, {_point, to}} = pair, index} ->
        if distance < to or index == count - 1, do: pair
      end)

    width = to - from

    if width == 0,
      do: {x1, y1, s1},
      else: lerp({x1, y1, s1}, {x2, y2, s2}, (distance - from) / width)
  end

  defp lerp({x1, y1, s1}, {x2, y2, s2}, f),
    do: {x1 + f * (x2 - x1), y1 + f * (y2 - y1), s1 + f * (s2 - s1)}

  defp lengths([first | rest]) do
    rest
    |> Enum.scan({first, 0.0}, fn {x, y, _s} = point, {{px, py, _ps}, length} ->
      {point, length + :math.sqrt((x - px) * (x - px) + (y - py) * (y - py))}
    end)
    |> Enum.map(&elem(&1, 1))
    |> then(&[0.0 | &1])
  end

  defp inner_points(%__MODULE__{smooth: false, closed: closed, points: points}),
    do: if(closed, do: points ++ [hd(points)], else: points)

  defp inner_points(%__MODULE__{
         smooth: true,
         closed: closed,
         points: points,
         precision: precision
       }) do
    count = length(points)
    tuple = List.to_tuple(points)
    last = if closed, do: count - 1, else: count - 3

    pieces =
      for i <- 0..last//1 do
        a = elem(tuple, rem(i, count))
        b = elem(tuple, rem(i + 1, count))
        c = elem(tuple, rem(i + 2, count))
        piece(precision, middle(a, b), b, middle(b, c))
      end
      |> List.flatten()

    if closed,
      do: pieces ++ [hd(pieces ++ [hd(points)])],
      else: [hd(points)] ++ pieces ++ [List.last(points)]
  end

  defp middle({x1, y1, s1}, {x2, y2, s2}), do: {(x1 + x2) / 2, (y1 + y2) / 2, (s1 + s2) / 2}

  defp piece(0, _a, _b, _c), do: []

  defp piece(depth, {x1, y1, s1} = a, {x2, y2, s2} = b, {x3, y3, s3} = c) do
    m = {(x1 + x2 + x2 + x3) / 4, (y1 + y2 + y2 + y3) / 4, (s1 + s2 + s2 + s3) / 4}

    before =
      if (x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1) > 16,
        do: piece(depth - 1, a, middle(b, a), m),
        else: []

    later =
      if (x2 - x3) * (x2 - x3) + (y2 - y3) * (y2 - y3) > 16,
        do: piece(depth - 1, m, middle(c, b), c),
        else: []

    [before, m, later]
  end

  defp points(bytes) do
    for <<x::binary-4, y::binary-4, speed::binary-4 <- bytes>>,
      do: {Bytes.float(x), Bytes.float(y), Bytes.float(speed)}
  end
end
