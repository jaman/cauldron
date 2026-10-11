defmodule Cauldron2D.Sectors.View do
  @moduledoc """
  Draws a sector map from a point inside it: walls, floors, ceilings and sky, and the
  things standing in it, nearest in front, into a `Cauldron2D.Sectors.Frame`.

      %{frame: frame, seen: lines} =
        Cauldron2D.Sectors.View.render(frame, pictures, map, %{
          x: 1056.0, y: -3616.0, z: 41.0, angle: :math.pi() / 2,
          sectors: sectors, sides: sides, things: things
        }, sky: %{picture: sky, flat: sky_flat, columns: 1024 / (2 * :math.pi()), mid: 100.0, step: 1.0})

  `map` is a `Cauldron2D.Sectors.Map` with its BSP. The view gives the eye's `x`, `y` and
  height `z`, its heading `angle` in radians (`0` along `+x`), and the `sectors` and
  `sides` as they are now — a door's ceiling moves and a switch's picture changes, so the
  game passes its own copies rather than the map's. `pitch` moves the horizon up (`> 0`)
  or down by that many pixels. `things` are what stand in the sectors:

      %{x:, y:, z:, sector:, picture:, offset: {left, top}, flip: false, bright: false, shimmer: false}

  where `z` is the height of the thing's feet, `offset` where the picture's origin is —
  `left` texels from its left edge, `top` texels above its bottom row at the feet — and
  `bright` draws it unlit. A `shimmer` thing is drawn as a blur of what is behind it.

  The result's `seen` is the set of line indexes some of which was drawn, for an automap.

  ## Options

    * `:sky` — `%{picture:, flat:, columns:, mid:, step:}`: a ceiling whose picture is
      `flat` shows picture `picture` wrapped around the view, `columns` picture columns
      per radian, its row `mid` at the horizon and `step` rows a pixel; default none
    * `:stretch` — how many times taller than wide a world unit is drawn. Default `1.0`
    * `:contrast` — light added to walls running along `y` and taken from walls running
      along `x`, so corners read. Default `0`
    * `:extra_light` — light added everywhere. Default `0`
    * `:fixed` — a light table to draw everything through instead of lighting it. Default `nil`
    * `:light` — options for `Cauldron2D.Sectors.Light`
    * `:fov` — the horizontal field of view in radians. Default `π/2`
  """

  alias Cauldron2D.Sectors.{Bsp, Frame, Light, Pictures}
  alias Cauldron2D.Sectors.Map, as: SectorMap
  alias Cauldron2D.Sectors.View.{Things, Walls}

  @infinity 1_000_000

  @type thing :: %{
          required(:x) => number(),
          required(:y) => number(),
          required(:z) => number(),
          required(:sector) => non_neg_integer(),
          required(:picture) => non_neg_integer(),
          optional(:offset) => {number(), number()},
          optional(:flip) => boolean(),
          optional(:bright) => boolean(),
          optional(:shimmer) => boolean()
        }

  @type eye :: %{
          required(:x) => number(),
          required(:y) => number(),
          required(:z) => number(),
          required(:angle) => number(),
          required(:sectors) => tuple(),
          required(:sides) => tuple(),
          optional(:things) => [thing()],
          optional(:pitch) => number()
        }

  @doc "Draw `map` as seen by `eye` onto `frame`. See the moduledoc."
  @spec render(Frame.t(), Pictures.t(), SectorMap.t(), eye(), keyword()) :: %{
          frame: Frame.t(),
          seen: MapSet.t(non_neg_integer())
        }
  def render(%Frame{} = frame, %Pictures{} = pictures, %SectorMap{} = map, eye, opts \\ []) do
    state = setup(frame, pictures, map, eye, opts)

    state =
      Bsp.walk(map, {state.vx, state.vy}, state, &subsector/2, fn box, acc ->
        box_visible?(acc, box)
      end)

    frame =
      frame
      |> Frame.columns(pictures, state.walls)
      |> draw_planes(state)

    {frame, _state} = Things.draw(frame, state, Map.get(eye, :things, []))
    %{frame: frame, seen: state.seen}
  end

  defp setup(frame, pictures, map, eye, opts) do
    {width, height} = {frame.width, frame.height}
    fov = Keyword.get(opts, :fov, :math.pi() / 2)
    center_x = width / 2
    focal_x = center_x / :math.tan(fov / 2)
    center_y = height / 2 + Map.get(eye, :pitch, 0)
    angle = eye.angle * 1.0

    rays =
      for x <- 0..(width - 1), into: [] do
        offset = :math.atan((center_x - (x + 0.5)) / focal_x)
        {:math.cos(angle + offset), :math.sin(angle + offset), :math.cos(offset)}
      end

    %{
      width: width,
      height: height,
      center_x: center_x,
      center_y: center_y,
      focal_x: focal_x,
      focal_y: focal_x * Keyword.get(opts, :stretch, 1.0),
      clip: fov / 2,
      vx: eye.x * 1.0,
      vy: eye.y * 1.0,
      vz: eye.z * 1.0,
      angle: angle,
      rays: List.to_tuple(rays),
      map: map,
      pictures: pictures,
      sectors: eye.sectors,
      sides: eye.sides,
      sky: Keyword.get(opts, :sky),
      contrast: Keyword.get(opts, :contrast, 0),
      extra: Keyword.get(opts, :extra_light, 0),
      fixed: Keyword.get(opts, :fixed),
      light: Keyword.get(opts, :light, []),
      solid: [{-@infinity, -1}, {width, @infinity}],
      ceiling_clip: :binary.copy(<<-1::16-little-signed>>, width),
      floor_clip: :binary.copy(<<height::16-little-signed>>, width),
      planes: %{},
      latest: %{},
      walls: [],
      drawsegs: [],
      seen: MapSet.new(),
      visible: MapSet.new(),
      floor_plane: nil,
      ceiling_plane: nil
    }
  end

  @doc false
  def light_table(state, light, distance) do
    case state.fixed do
      nil -> Light.table(light + state.extra, distance, state.light)
      fixed -> fixed
    end
  end

  @doc false
  def sky?(%{sky: nil}, _picture), do: false
  def sky?(%{sky: %{flat: flat}}, picture), do: picture == flat

  defp subsector(index, state) do
    sub = elem(state.map.subsectors, index)
    sector = elem(state.sectors, sub.sector)

    state = %{
      state
      | visible: MapSet.put(state.visible, sub.sector),
        floor_plane:
          if(sector.floor < state.vz,
            do: plane_key(state, sector.floor, sector.floor_picture, sector.light)
          ),
        ceiling_plane:
          if(sector.ceiling > state.vz or sky?(state, sector.ceiling_picture),
            do: plane_key(state, sector.ceiling, sector.ceiling_picture, sector.light)
          )
    }

    Enum.reduce(sub.first..(sub.first + sub.count - 1)//1, state, fn seg_index, acc ->
      add_seg(acc, elem(state.map.segs, seg_index), sub.sector)
    end)
  end

  defp plane_key(state, height, picture, light) do
    if sky?(state, picture), do: :sky, else: {height, picture, light}
  end

  defp add_seg(state, seg, sector_index) do
    case columns_of(state, seg.from, seg.to) do
      nil -> state
      {first, last} -> clip_seg(state, seg, sector_index, first, last)
    end
  end

  @doc false
  def columns_of(state, {x1, y1}, {x2, y2}) do
    a1 = :math.atan2(y1 - state.vy, x1 - state.vx)
    a2 = :math.atan2(y2 - state.vy, x2 - state.vx)
    span = normal(a1 - a2)

    if span >= :math.pi() or span == 0.0,
      do: nil,
      else: angles_to_columns(state, in_view(state, signed(a1 - state.angle), span))
  end

  defp in_view(state, left, span) do
    turn = 2 * :math.pi()

    {left, right} =
      if left < -state.clip, do: {left + turn, left - span + turn}, else: {left, left - span}

    {min(left, state.clip), max(right, -state.clip)}
  end

  defp angles_to_columns(_state, {left, right}) when left <= right, do: nil

  defp angles_to_columns(state, {left, right}) do
    first =
      (state.center_x - 0.5 - :math.tan(left) * state.focal_x)
      |> Float.ceil()
      |> trunc()
      |> max(0)

    last =
      (state.center_x - 0.5 - :math.tan(right) * state.focal_x)
      |> Float.floor()
      |> trunc()
      |> min(state.width - 1)

    if first > last, do: nil, else: {first, last}
  end

  defp normal(angle) do
    turn = 2 * :math.pi()
    value = angle - turn * Float.floor(angle / turn)
    if value >= turn, do: 0.0, else: value
  end

  defp signed(angle) do
    value = normal(angle)
    if value > :math.pi(), do: value - 2 * :math.pi(), else: value
  end

  defp clip_seg(state, seg, sector_index, first, last) do
    line = elem(state.map.lines, seg.line)
    front = elem(state.sectors, sector_index)
    back_sector = back_of(state, line, seg.side)
    back = back_sector && elem(state.sectors, back_sector)

    cond do
      back == nil or closed?(front, back) ->
        state
        |> store_fragments(seg, front, back, uncovered(state.solid, first, last))
        |> then(&%{&1 | solid: covered(&1.solid, first, last)})

      open_and_same?(front, back, seg, state) ->
        state

      true ->
        store_fragments(state, seg, front, back, uncovered(state.solid, first, last))
    end
  end

  defp back_of(state, line, side) do
    case if(side == 0, do: line.back, else: line.front) do
      nil -> nil
      side_index -> elem(state.sides, side_index).sector
    end
  end

  defp closed?(front, back), do: back.ceiling <= front.floor or back.floor >= front.ceiling

  defp open_and_same?(front, back, seg, state) do
    side = side_of(state, seg)

    back.ceiling_picture == front.ceiling_picture and back.floor_picture == front.floor_picture and
      back.light == front.light and back.ceiling == front.ceiling and back.floor == front.floor and
      side.middle == nil
  end

  @doc false
  def side_of(state, seg) do
    line = elem(state.map.lines, seg.line)
    elem(state.sides, if(seg.side == 0, do: line.front, else: line.back))
  end

  defp store_fragments(state, seg, front, back, fragments) do
    Enum.reduce(fragments, state, fn {first, last}, acc ->
      Walls.store(acc, seg, front, back, first, last)
    end)
  end

  defp uncovered(solid, first, last) do
    {fragments, from} =
      Enum.reduce(solid, {[], first}, fn {low, high}, {acc, from} ->
        cond do
          from > last -> {acc, from}
          high < from -> {acc, from}
          low > from -> {[{from, min(low - 1, last)} | acc], max(from, high + 1)}
          true -> {acc, max(from, high + 1)}
        end
      end)

    fragments = if from <= last, do: [{from, last} | fragments], else: fragments
    Enum.reverse(fragments)
  end

  defp covered(solid, first, last) do
    {before, rest} = Enum.split_while(solid, fn {_low, high} -> high < first - 1 end)
    {touching, after_range} = Enum.split_while(rest, fn {low, _high} -> low <= last + 1 end)
    lows = [first | Enum.map(touching, &elem(&1, 0))]
    highs = [last | Enum.map(touching, &elem(&1, 1))]
    before ++ [{Enum.min(lows), Enum.max(highs)}] ++ after_range
  end

  @doc false
  def check_plane(state, nil, _first, _last), do: {state, nil}

  def check_plane(state, key, first, last) do
    case Map.get(state.latest, key) do
      nil ->
        new_plane(state, key, first, last)

      id ->
        plane = Map.fetch!(state.planes, id)
        low = max(first, plane.x1)
        high = min(last, plane.x2)

        if low <= high and Enum.any?(low..high, &Map.has_key?(plane.columns, &1)),
          do: new_plane(state, key, first, last),
          else:
            {%{
               state
               | planes:
                   Map.put(state.planes, id, %{
                     plane
                     | x1: min(plane.x1, first),
                       x2: max(plane.x2, last)
                   })
             }, id}
    end
  end

  defp new_plane(state, key, first, last) do
    id = map_size(state.planes)
    plane = %{key: key, x1: first, x2: last, columns: %{}}

    {%{state | planes: Map.put(state.planes, id, plane), latest: Map.put(state.latest, key, id)},
     id}
  end

  @doc false
  def mark_plane(state, nil, _x, _top, _bottom), do: state
  def mark_plane(state, _id, _x, top, bottom) when top > bottom, do: state

  def mark_plane(state, id, x, top, bottom) do
    %{
      state
      | planes:
          Map.update!(state.planes, id, &%{&1 | columns: Map.put(&1.columns, x, {top, bottom})})
    }
  end

  defp draw_planes(frame, state) do
    state.planes
    |> Map.values()
    |> Enum.reject(&(map_size(&1.columns) == 0))
    |> Enum.reduce(frame, fn plane, acc ->
      xs = plane.x1..plane.x2
      tops = Enum.map(xs, &(plane.columns |> Map.get(&1, {state.height, -1}) |> elem(0)))
      bottoms = Enum.map(xs, &(plane.columns |> Map.get(&1, {state.height, -1}) |> elem(1)))
      Frame.plane(acc, state.pictures, plane_spec(state, plane), tops, bottoms)
    end)
  end

  defp plane_spec(state, %{key: :sky} = plane) do
    Map.merge(view_spec(state, plane), %{
      sky: true,
      picture: state.sky.picture,
      height: 0.0,
      fixed: state.fixed || 0,
      sky_columns: state.sky.columns,
      sky_mid: state.sky.mid,
      sky_step: state.sky.step
    })
  end

  defp plane_spec(state, %{key: {height, picture, light}} = plane) do
    Map.merge(view_spec(state, plane), %{
      picture: picture,
      height: height - state.vz,
      start: Light.start(light + state.extra, state.light),
      fade: Keyword.get(state.light, :fade, 1280.0),
      fixed: state.fixed || -1
    })
  end

  defp view_spec(state, plane) do
    %{
      x1: plane.x1,
      x2: plane.x2,
      x: state.vx,
      y: state.vy,
      angle: state.angle,
      center_x: state.center_x,
      center_y: state.center_y,
      focal_x: state.focal_x,
      focal_y: state.focal_y
    }
  end

  defp box_visible?(state, {top, bottom, left, right} = box) do
    case corners(band(state.vy, top, bottom, :y) * 4 + band(state.vx, left, right, :x), box) do
      :inside -> true
      nil -> true
      {from, to} -> box_columns_open?(state, from, to)
    end
  end

  defp band(value, low, _high, :x) when value <= low, do: 0
  defp band(value, _low, high, :x) when value < high, do: 1
  defp band(_value, _low, _high, :x), do: 2
  defp band(value, top, _bottom, :y) when value >= top, do: 0
  defp band(value, _top, bottom, :y) when value > bottom, do: 1
  defp band(_value, _top, _bottom, :y), do: 2

  defp corners(5, _box), do: :inside
  defp corners(position, _box) when position in [3, 7], do: nil

  defp corners(position, {top, bottom, left, right}) do
    coords = {top, bottom, left, right}

    [a, b, c, d] =
      elem(
        {[3, 0, 2, 1], [3, 0, 2, 0], [3, 1, 2, 0], [0], [2, 0, 2, 1], [0, 0, 0, 0], [3, 1, 3, 0],
         [0], [2, 0, 3, 1], [2, 1, 3, 1], [2, 1, 3, 0]},
        position
      )

    {{elem(coords, a), elem(coords, b)}, {elem(coords, c), elem(coords, d)}}
  end

  defp box_columns_open?(state, from, to) do
    case columns_of(state, from, to) do
      nil -> sitting_on?(state, from, to)
      {first, last} -> uncovered(state.solid, first, last) != []
    end
  end

  defp sitting_on?(state, {x1, y1}, {x2, y2}) do
    a1 = :math.atan2(y1 - state.vy, x1 - state.vx)
    a2 = :math.atan2(y2 - state.vy, x2 - state.vx)
    normal(a1 - a2) >= :math.pi()
  end
end
