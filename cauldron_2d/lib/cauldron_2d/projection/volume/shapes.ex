defmodule Cauldron2D.Projection.Volume.Shapes do
  @moduledoc """
  The shapes `Cauldron2D.Projection.Volume` knows without being told: a sphere, a
  cylinder, a cone, a beam, and a set of whole grid tiles.

      {:sphere, 1.5, 0.0}                 half a ball standing on the ground
      {:sphere, 1.0, 1.5}                 a ball floating a tile and a half up
      {:cylinder, 3.0, 2.0}               a disc of three tiles, two tiles tall
      {:cone, 6.0, :math.pi() / 2, 0.0, 2.0}   a quarter turn wide, six tiles long
      {:beam, 8.0, 1.0, 0.0, 2.0}         a tile wide and eight long, along `+x`
      {:cells, MapSet.new([{0, 0}, {1, 0}]), 2.0}   two whole tiles

  Everything is measured from the volume's own place on the ground, with `z` running up.
  A sphere's second number is how far its centre floats; at `0.0` it is a dome. A cone
  and a beam run along a heading in radians, `0` along `+x`, and a cone's spread is the
  angle it opens to, less than half a turn. `:cells` covers whole tiles of the grid the
  volume stands on, named by their offset from it, which is how a table that plays by
  squares marks an area out; put the volume on a tile corner for it.

  Nothing below the ground counts, so these shapes do not clip themselves to it.
  """

  @behaviour Cauldron2D.Projection.Volume.Shape

  @far 1.0e18
  @flat 1.0e-12
  @nudge 1.0e-9

  @doc "The shapes this module takes, for a caller checking one before it is drawn."
  @spec kinds() :: [atom()]
  def kinds, do: [:sphere, :cylinder, :cone, :beam, :cells]

  @impl true
  def span({:sphere, radius, height}, {ox, oy, oz}, {dx, dy, dz}) do
    ez = oz - height
    a = dx * dx + dy * dy + dz * dz
    b = 2 * (dx * ox + dy * oy + dz * ez)
    c = ox * ox + oy * oy + ez * ez - radius * radius

    case roots(a, b, c) do
      nil -> []
      pair -> [pair]
    end
  end

  def span({:cylinder, radius, height}, origin, direction),
    do: wrap(column(radius, height, origin, direction))

  def span({:cone, length, spread, heading, height}, origin, direction) do
    half = min(abs(spread), :math.pi() - @flat) / 2

    length
    |> column(height, origin, direction)
    |> clip(edge(heading + half, 1), origin, direction)
    |> clip(edge(heading - half, -1), origin, direction)
    |> wrap()
  end

  def span({:beam, length, width, heading, height}, {ox, oy, oz}, {dx, dy, dz}) do
    {ax, ay} = {:math.cos(heading), :math.sin(heading)}

    slab(ox * ax + oy * ay, dx * ax + dy * ay, 0, length)
    |> meet(slab(oy * ax - ox * ay, dy * ax - dx * ay, -width / 2, width / 2))
    |> meet(slab(oz, dz, 0, height))
    |> wrap()
  end

  def span({:cells, tiles, height} = shape, {ox, oy, oz}, {dx, dy, dz}) do
    cond do
      MapSet.size(tiles) == 0 ->
        []

      abs(dx) < @flat and abs(dy) < @flat ->
        if MapSet.member?(tiles, {floor(ox), floor(oy)}),
          do: wrap(slab(oz, dz, 0, height)),
          else: []

      true ->
        {{left, top, _low}, {right, bottom, _high}} = bounds(shape)

        slab(oz, dz, 0, height)
        |> meet(slab(ox, dx, left, right))
        |> meet(slab(oy, dy, top, bottom))
        |> crossed(tiles, {ox, oy}, {dx, dy})
    end
  end

  defp crossed(nil, _tiles, _origin, _direction), do: []

  defp crossed({from, to}, tiles, origin, direction),
    do: tiles |> march(origin, direction, from, to, []) |> Enum.reverse() |> join()

  @impl true
  def bounds({:sphere, radius, height}),
    do: {{-radius, -radius, height - radius}, {radius, radius, height + radius}}

  def bounds({:cylinder, radius, height}),
    do: {{-radius, -radius, 0.0}, {radius, radius, height}}

  def bounds({:cone, length, _spread, _heading, height}),
    do: {{-length, -length, 0.0}, {length, length, height}}

  def bounds({:beam, length, width, heading, height}) do
    {ax, ay} = {:math.cos(heading), :math.sin(heading)}
    half = width / 2

    corners =
      for along <- [0.0, length],
          across <- [-half, half],
          do: {along * ax - across * ay, along * ay + across * ax}

    xs = Enum.map(corners, &elem(&1, 0))
    ys = Enum.map(corners, &elem(&1, 1))

    {{Enum.min(xs), Enum.min(ys), 0.0}, {Enum.max(xs), Enum.max(ys), height}}
  end

  def bounds({:cells, tiles, height}) do
    case Enum.to_list(tiles) do
      [] ->
        {{0.0, 0.0, 0.0}, {0.0, 0.0, 0.0}}

      list ->
        xs = Enum.map(list, &elem(&1, 0))
        ys = Enum.map(list, &elem(&1, 1))

        {{Enum.min(xs) / 1, Enum.min(ys) / 1, 0.0},
         {(Enum.max(xs) + 1) / 1, (Enum.max(ys) + 1) / 1, height}}
    end
  end

  @impl true
  def thickness({:sphere, radius, _height}), do: 2 * radius

  def thickness({:cylinder, radius, height}), do: diagonal(2 * radius, 2 * radius, height)

  def thickness({:cone, length, _spread, _heading, height}), do: diagonal(length, 0.0, height)

  def thickness({:beam, length, _width, _heading, height}), do: diagonal(length, 0.0, height)

  def thickness({:cells, _tiles, _height} = shape) do
    {{left, top, low}, {right, bottom, high}} = bounds(shape)
    diagonal(right - left, bottom - top, high - low)
  end

  defp diagonal(x, y, z), do: :math.sqrt(x * x + y * y + z * z)

  defp column(radius, height, {ox, oy, oz}, {dx, dy, dz}) do
    a = dx * dx + dy * dy
    b = 2 * (dx * ox + dy * oy)
    c = ox * ox + oy * oy - radius * radius

    disc =
      if a < @flat,
        do: if(c <= 0, do: {-@far, @far}, else: nil),
        else: roots(a, b, c)

    meet(disc, slab(oz, dz, 0, height))
  end

  defp edge(angle, turn) do
    {ex, ey} = {:math.cos(angle), :math.sin(angle)}
    {ey * turn, -ex * turn}
  end

  defp clip(nil, _normal, _origin, _direction), do: nil

  defp clip(interval, {nx, ny}, {ox, oy, _oz}, {dx, dy, _dz}) do
    at = nx * ox + ny * oy
    along = nx * dx + ny * dy

    cond do
      abs(along) < @flat and at >= 0 -> interval
      abs(along) < @flat -> nil
      along > 0 -> meet(interval, {-at / along, @far})
      true -> meet(interval, {-@far, -at / along})
    end
  end

  defp roots(a, b, c) do
    discriminant = b * b - 4 * a * c

    if a < @flat or discriminant <= 0 do
      nil
    else
      root = :math.sqrt(discriminant)
      {(-b - root) / (2 * a), (-b + root) / (2 * a)}
    end
  end

  defp slab(origin, direction, low, high) when abs(direction) < @flat,
    do: if(origin >= low and origin <= high, do: {-@far, @far}, else: nil)

  defp slab(origin, direction, low, high) do
    one = (low - origin) / direction
    other = (high - origin) / direction
    {min(one, other), max(one, other)}
  end

  defp meet(nil, _other), do: nil
  defp meet(_one, nil), do: nil

  defp meet({a, b}, {c, d}) do
    {from, to} = {max(a, c), min(b, d)}
    if to > from, do: {from, to}
  end

  defp wrap(nil), do: []
  defp wrap(interval), do: [interval]

  defp march(_tiles, _origin, _direction, at, to, found) when at >= to, do: found

  defp march(tiles, {ox, oy} = origin, {dx, dy} = direction, at, to, found) do
    tile = {floor(ox + (at + @nudge) * dx), floor(oy + (at + @nudge) * dy)}
    next = at |> Kernel.+(@nudge) |> max(min(to, leaves(origin, direction, tile)))
    found = if MapSet.member?(tiles, tile), do: [{at, min(next, to)} | found], else: found
    march(tiles, origin, direction, next, to, found)
  end

  defp leaves({ox, oy}, {dx, dy}, {tx, ty}), do: min(crosses(ox, dx, tx), crosses(oy, dy, ty))

  defp crosses(_origin, direction, _tile) when abs(direction) < @flat, do: @far
  defp crosses(origin, direction, tile) when direction > 0, do: (tile + 1 - origin) / direction
  defp crosses(origin, direction, tile), do: (tile - origin) / direction

  defp join([]), do: []

  defp join([interval | rest]), do: Enum.reverse(Enum.reduce(rest, [interval], &joined/2))

  defp joined({from, to}, [{held_from, held_to} | rest]) when from - held_to < @nudge * 2,
    do: [{held_from, max(held_to, to)} | rest]

  defp joined(interval, held), do: [interval | held]
end
