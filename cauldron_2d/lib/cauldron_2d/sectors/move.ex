defmodule Cauldron2D.Sectors.Move do
  @moduledoc """
  Moving a body through a sector map: whether it fits where it is going, what floor and
  ceiling it finds there, and sliding along a wall it runs into.

      case Move.try(world, body, {x + dx, y + dy}, step: 24.0) do
        {:ok, moved} -> moved.x
        {:blocked, why} -> why.reason
      end

      {moved, momentum} = Move.slide(world, body, {dx, dy}, step: 24.0)

  `world` is `%{map: map, blockmap: blockmap, sectors: sectors}` — the sectors as they are
  now, since floors and ceilings move. A body is `%{x:, y:, z:, radius:, height:}` with
  `z` its feet; its box, `radius` each way from its centre, is what collides.

  A body fits at a point when no line it may not pass crosses its box, no body it may not
  pass overlaps it, the opening there is as tall as it is, its head is below the lowest
  ceiling, the floor is no more than `:step` above its feet, and — unless it may drop —
  no more than `:step` above the lowest floor under its box.

  ## Options

    * `:step` — how far up a body steps without climbing. Default `24.0`
    * `:dropoff` — whether a body may walk off a ledge. Default `true`
    * `:line_blocks?` — `fn line_index -> boolean` for two-sided lines that stop this body;
      a one-sided line always does. Default: lines flagged `:blocks`
    * `:body_blocks?` — `fn {id, point, radius} -> boolean` for overlapping bodies that
      stop it. Default: every body
    * `:except` — the moving body's own id in the blockmap. Default `nil`
  """

  alias Cauldron2D.Sectors.{Blockmap, Trace}
  alias Cauldron2D.Sectors.Map, as: SectorMap

  @type world :: %{map: SectorMap.t(), blockmap: Blockmap.t(), sectors: tuple()}
  @type body :: %{x: number(), y: number(), z: number(), radius: number(), height: number()}
  @type place :: %{
          sector: non_neg_integer(),
          floor: float(),
          ceiling: float(),
          dropoff: float(),
          blocked: nil | {:line, non_neg_integer()} | {:body, term()},
          lines: [non_neg_integer()],
          bodies: [Blockmap.body()]
        }

  @doc "What a body would find at `point`, without moving it. See `t:place/0`."
  @spec check(world(), body(), {number(), number()}, keyword()) :: place()
  def check(world, body, {x, y} = point, opts \\ []) do
    sector_index = SectorMap.sector_at(world.map, point)
    sector = elem(world.sectors, sector_index)
    except = Keyword.get(opts, :except)
    body_blocks? = Keyword.get(opts, :body_blocks?, fn _body -> true end)

    bodies =
      world.blockmap
      |> Blockmap.bodies_near(point, body.radius)
      |> Enum.reject(fn {id, _point, _radius} -> id == except end)

    place = %{
      sector: sector_index,
      floor: sector.floor,
      ceiling: sector.ceiling,
      dropoff: sector.floor,
      blocked:
        Enum.find_value(bodies, fn {id, _p, _r} = other ->
          if body_blocks?.(other), do: {:body, id}
        end),
      lines: [],
      bodies: bodies
    }

    world.blockmap
    |> Blockmap.lines_near(point, body.radius)
    |> Enum.filter(&crosses_box?(world.map, &1, {x, y}, body.radius))
    |> Enum.reduce(place, &line_effect(world, &1, &2, opts))
  end

  defp line_effect(world, index, place, opts) do
    line = elem(world.map.lines, index)

    line_blocks? =
      Keyword.get(opts, :line_blocks?, fn i ->
        MapSet.member?(elem(world.map.lines, i).flags, :blocks)
      end)

    cond do
      line.back == nil ->
        %{place | blocked: place.blocked || {:line, index}}

      line_blocks?.(index) ->
        %{place | blocked: place.blocked || {:line, index}, lines: [index | place.lines]}

      true ->
        opening = opening(world, index)

        %{
          place
          | ceiling: min(place.ceiling, opening.top),
            floor: max(place.floor, opening.bottom),
            dropoff: min(place.dropoff, opening.low),
            lines: [index | place.lines]
        }
    end
  end

  @doc """
  The gap through two-sided line `index`: `%{top:, bottom:, low:, range:}` — the lower
  ceiling, the higher floor, the lower floor and the height between — or `nil` for a
  one-sided line.
  """
  @spec opening(world(), non_neg_integer()) ::
          %{top: float(), bottom: float(), low: float(), range: float()} | nil
  def opening(world, index) do
    line = elem(world.map.lines, index)

    if line.back == nil do
      nil
    else
      front = elem(world.sectors, SectorMap.side_sector(world.map, index, 0))
      back = elem(world.sectors, SectorMap.side_sector(world.map, index, 1))
      top = min(front.ceiling, back.ceiling)
      bottom = max(front.floor, back.floor)
      %{top: top, bottom: bottom, low: min(front.floor, back.floor), range: top - bottom}
    end
  end

  @doc "Whether line `index` crosses the box of `radius` round `point`."
  @spec crosses_box?(SectorMap.t(), non_neg_integer(), {number(), number()}, number()) ::
          boolean()
  def crosses_box?(map, index, {x, y}, radius) do
    {{x1, y1}, {x2, y2}} = SectorMap.ends(map, index)
    {left, right, bottom, top} = {x - radius, x + radius, y - radius, y + radius}

    if max(x1, x2) <= left or min(x1, x2) >= right or max(y1, y2) <= bottom or min(y1, y2) >= top do
      false
    else
      cut = {x1, y1, x2 - x1, y2 - y1}

      [{left, top}, {right, top}, {left, bottom}, {right, bottom}]
      |> Enum.map(&SectorMap.point_side(&1, cut))
      |> Enum.uniq()
      |> length() == 2
    end
  end

  @doc """
  Move the body to `point` if it fits there: `{:ok, %{x:, y:, floor:, ceiling:, dropoff:,
  sector:, crossed:, lines:, bodies:}}`, where `crossed` lists the lines whose side the
  body's centre changed, `lines` the two-sided lines its box touches and `bodies` the bodies
  it overlaps without being stopped, or
  `{:blocked, %{reason:, place:}}` with `reason` one of `:line`, `:body`, `:tight`,
  `:ceiling`, `:step` and `:dropoff`.
  """
  @spec try(world(), body(), {number(), number()}, keyword()) :: {:ok, map()} | {:blocked, map()}
  def try(world, body, {x, y} = point, opts \\ []) do
    place = check(world, body, point, opts)

    if reason = blocked_reason(place, body, opts) do
      {:blocked, %{reason: reason, place: place}}
    else
      crossed = Enum.filter(place.lines, &crossed?(world.map, &1, {body.x, body.y}, point))

      {:ok,
       %{
         x: x * 1.0,
         y: y * 1.0,
         floor: place.floor,
         ceiling: place.ceiling,
         dropoff: place.dropoff,
         sector: place.sector,
         crossed: crossed,
         lines: place.lines,
         bodies: place.bodies
       }}
    end
  end

  defp blocked_reason(%{blocked: {:line, _index}}, _body, _opts), do: :line
  defp blocked_reason(%{blocked: {:body, _id}}, _body, _opts), do: :body

  defp blocked_reason(place, body, opts) do
    step = Keyword.get(opts, :step, 24.0)
    dropoff? = Keyword.get(opts, :dropoff, true)

    cond do
      place.ceiling - place.floor < body.height -> :tight
      place.ceiling - body.z < body.height -> :ceiling
      place.floor - body.z > step -> :step
      not dropoff? and place.floor - place.dropoff > step -> :dropoff
      true -> nil
    end
  end

  defp crossed?(map, index, from, to) do
    {{x1, y1}, {x2, y2}} = SectorMap.ends(map, index)
    cut = {x1, y1, x2 - x1, y2 - y1}
    SectorMap.point_side(from, cut) != SectorMap.point_side(to, cut)
  end

  @doc """
  Move the body by `momentum`, sliding along whatever wall stops it, as Doom's player
  does. Gives `{moved, momentum}`: `moved` as `try/4`'s success, or the body where it was
  with `crossed: []`, and the momentum left after sliding.
  """
  @spec slide(world(), body(), {number(), number()}, keyword()) :: {map(), {float(), float()}}
  def slide(world, body, momentum, opts \\ []),
    do: slide_attempt(world, body, momentum, opts, 1, [])

  defp slide_attempt(world, body, momentum, opts, 3, crossed),
    do: stairstep(world, body, momentum, opts, crossed)

  defp slide_attempt(world, body, momentum, opts, attempt, crossed) do
    case nearest_wall(world, body, momentum, opts) do
      nil -> stairstep(world, body, momentum, opts, crossed)
      wall -> slide_to(world, body, momentum, opts, {attempt, crossed}, wall)
    end
  end

  defp slide_to(world, body, {mx, my} = momentum, opts, {attempt, crossed}, {fraction, line}) do
    fraction = fraction - 1 / 32
    advance = max(fraction, 0.0)

    case partial(world, body, {mx * advance, my * advance}, opts, crossed) do
      :blocked ->
        stairstep(world, body, momentum, opts, crossed)

      {:ok, body, crossed} ->
        slide_rest(
          world,
          body,
          momentum,
          opts,
          {attempt, crossed},
          {1.0 - (fraction + 1 / 32), line}
        )
    end
  end

  defp slide_rest(world, body, momentum, _opts, {_attempt, crossed}, {rest, _line})
       when rest <= 0,
       do: {here(world, body, crossed), momentum}

  defp slide_rest(world, body, {mx, my}, opts, {attempt, crossed}, {rest, line}) do
    rest = min(rest, 1.0)
    {sx, sy} = slid = along(world.map, line, {body.x, body.y}, {mx * rest, my * rest})

    case try(world, body, {body.x + sx, body.y + sy}, opts) do
      {:ok, moved} -> {Map.update!(moved, :crossed, &(crossed ++ &1)), slid}
      {:blocked, _why} -> slide_attempt(world, body, slid, opts, attempt + 1, crossed)
    end
  end

  defp partial(world, body, {dx, dy}, opts, crossed) do
    if dx * dx + dy * dy < 1.0e-12 do
      {:ok, body, crossed}
    else
      case try(world, body, {body.x + dx, body.y + dy}, opts) do
        {:ok, moved} -> {:ok, %{body | x: moved.x, y: moved.y}, crossed ++ moved.crossed}
        {:blocked, _why} -> :blocked
      end
    end
  end

  defp stairstep(world, body, {mx, my}, opts, crossed) do
    case try(world, body, {body.x, body.y + my}, opts) do
      {:ok, moved} ->
        {Map.update!(moved, :crossed, &(crossed ++ &1)), {0.0, my}}

      {:blocked, _why} ->
        case try(world, body, {body.x + mx, body.y}, opts) do
          {:ok, moved} -> {Map.update!(moved, :crossed, &(crossed ++ &1)), {mx, 0.0}}
          {:blocked, _why} -> {here(world, body, crossed), {0.0, 0.0}}
        end
    end
  end

  defp here(world, body, crossed) do
    place =
      check(world, body, {body.x, body.y}, except: :__nobody__, body_blocks?: fn _ -> false end)

    %{
      x: body.x * 1.0,
      y: body.y * 1.0,
      floor: place.floor,
      ceiling: place.ceiling,
      dropoff: place.dropoff,
      sector: place.sector,
      crossed: crossed,
      lines: place.lines,
      bodies: []
    }
  end

  defp nearest_wall(world, body, {mx, my}, opts) do
    {lead_x, trail_x} =
      if mx > 0,
        do: {body.x + body.radius, body.x - body.radius},
        else: {body.x - body.radius, body.x + body.radius}

    {lead_y, trail_y} =
      if my > 0,
        do: {body.y + body.radius, body.y - body.radius},
        else: {body.y - body.radius, body.y + body.radius}

    [{lead_x, lead_y}, {trail_x, lead_y}, {lead_x, trail_y}]
    |> Enum.flat_map(fn {sx, sy} ->
      world.map
      |> Trace.run(world.blockmap, {sx, sy}, {sx + mx, sy + my}, bodies: false)
      |> Enum.find(&blocking_slide?(world, body, &1.line, opts))
      |> List.wrap()
    end)
    |> Enum.min_by(& &1.fraction, fn -> nil end)
    |> case do
      nil -> nil
      %{fraction: fraction, line: line} -> {fraction, line}
    end
  end

  defp blocking_slide?(world, body, index, opts) do
    line = elem(world.map.lines, index)
    step = Keyword.get(opts, :step, 24.0)

    if line.back == nil do
      {{x1, y1}, {x2, y2}} = SectorMap.ends(world.map, index)
      SectorMap.point_side({body.x, body.y}, {x1, y1, x2 - x1, y2 - y1}) == 0
    else
      opening = opening(world, index)

      opening.range < body.height or opening.top - body.z < body.height or
        opening.bottom - body.z > step
    end
  end

  defp along(map, index, {x, y}, {dx, dy}) do
    {{x1, y1}, {x2, y2}} = SectorMap.ends(map, index)
    {lx, ly} = {x2 - x1, y2 - y1}

    cond do
      ly == 0 ->
        {dx, 0.0}

      lx == 0 ->
        {0.0, dy}

      true ->
        line_angle = :math.atan2(ly, lx)
        side = SectorMap.point_side({x, y}, {x1, y1, lx, ly})
        line_angle = if side == 1, do: line_angle + :math.pi(), else: line_angle
        move_angle = :math.atan2(dy, dx)
        length = :math.sqrt(dx * dx + dy * dy) * :math.cos(move_angle - line_angle)
        {length * :math.cos(line_angle), length * :math.sin(line_angle)}
    end
  end
end
