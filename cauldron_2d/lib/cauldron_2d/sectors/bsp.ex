defmodule Cauldron2D.Sectors.Bsp do
  @moduledoc """
  A binary space partition of a sector map: the order to draw it in from any point, front
  to back, and the convex piece any point is in.

      {segs, subsectors, nodes} = Cauldron2D.Sectors.Bsp.build(map)
      Cauldron2D.Sectors.Bsp.locate(map, {x, y})

  The level is cut by lines into convex **subsectors**, each a run of **segs** — pieces of
  the map's lines — in one sector. A **node** is a cutting line `{x, y, dx, dy}` with a
  child on each side and the bounding box of each child; the last node is the root.

    * a seg is `%{from: {x, y}, to: {x, y}, line: index, side: 0 | 1, offset: distance}`,
      where `side` is the side of its line it shows and `offset` how far along that side
      it starts
    * a subsector is `%{first: index, count: n, sector: index}`, its segs being
      `first..first + count - 1`
    * a node is `%{x:, y:, dx:, dy:, boxes: {front_box, back_box}, children: {front, back}}`,
      a box `{top, bottom, left, right}` and a child `{:node, index}` or `{:leaf, index}`;
      the front is the right of the cutting line, as `Cauldron2D.Sectors.Map.point_side/2`
      reckons it

  `build/2` builds one from a map's lines. A level that carries its own BSP is read into
  the same shapes and used as it is.
  """

  alias Cauldron2D.Sectors.Map, as: SectorMap

  @epsilon 1.0e-6

  @type box :: {float(), float(), float(), float()}
  @type child :: {:node, non_neg_integer()} | {:leaf, non_neg_integer()}

  @doc "The root of the map's BSP."
  @spec root(SectorMap.t()) :: child()
  def root(%SectorMap{nodes: nodes}) when tuple_size(nodes) == 0, do: {:leaf, 0}
  def root(%SectorMap{nodes: nodes}), do: {:node, tuple_size(nodes) - 1}

  @doc "The subsector `point` is in."
  @spec locate(SectorMap.t(), SectorMap.point()) :: non_neg_integer()
  def locate(%SectorMap{} = map, point), do: descend(map.nodes, root(map), point)

  defp descend(_nodes, {:leaf, index}, _point), do: index

  defp descend(nodes, {:node, index}, point) do
    node = elem(nodes, index)
    side = SectorMap.point_side(point, {node.x, node.y, node.dx, node.dy})
    descend(nodes, elem(node.children, side), point)
  end

  @doc """
  Visit the subsectors front to back as seen from `point`.

  `leaf` is called `leaf.(subsector_index, acc)` and returns the new `acc`. Before going
  into the far side of a node, `far?.(box, acc)` is asked whether anything in that box can
  still be seen; returning `false` skips it.
  """
  @spec walk(SectorMap.t(), SectorMap.point(), acc, (non_neg_integer(), acc -> acc), (box(),
                                                                                      acc ->
                                                                                        boolean())) ::
          acc
        when acc: term()
  def walk(%SectorMap{} = map, point, acc, leaf, far?),
    do: visit(map.nodes, root(map), point, acc, leaf, far?)

  defp visit(_nodes, {:leaf, index}, _point, acc, leaf, _far?), do: leaf.(index, acc)

  defp visit(nodes, {:node, index}, point, acc, leaf, far?) do
    node = elem(nodes, index)
    side = SectorMap.point_side(point, {node.x, node.y, node.dx, node.dy})
    other = 1 - side
    acc = visit(nodes, elem(node.children, side), point, acc, leaf, far?)

    if far?.(elem(node.boxes, other), acc),
      do: visit(nodes, elem(node.children, other), point, acc, leaf, far?),
      else: acc
  end

  @doc """
  A BSP for `map` built from its lines: `{segs, subsectors, nodes}` as tuples.

  Cutting lines are chosen among the segs' own lines, weighing how many segs a cut would
  split against how unevenly it divides them. Options: `:split_cost`, the weight of one
  split against one seg of imbalance, default `8`; `:candidates`, how many cutting lines are
  tried at each step, default `48`.
  """
  @spec build(SectorMap.t(), keyword()) :: {tuple(), tuple(), tuple()}
  def build(%SectorMap{} = map, opts \\ []) do
    settings = %{
      split_cost: Keyword.get(opts, :split_cost, 8),
      candidates: Keyword.get(opts, :candidates, 48)
    }

    segs = initial_segs(map)
    state = %{segs: [], subsectors: [], nodes: [], map: map}
    {_child, state} = partition(segs, state, settings)

    {state.segs |> Enum.reverse() |> List.to_tuple(),
     state.subsectors |> Enum.reverse() |> List.to_tuple(),
     state.nodes |> Enum.reverse() |> List.to_tuple()}
  end

  defp initial_segs(map) do
    for index <- 0..(tuple_size(map.lines) - 1)//1,
        line = elem(map.lines, index),
        {from, to} = SectorMap.ends(map, index),
        {side, present?, start, finish} <- [{0, true, from, to}, {1, line.back != nil, to, from}],
        present?,
        do: %{from: start, to: finish, line: index, side: side, offset: 0.0}
  end

  defp partition(segs, state, settings) do
    case choose(segs, settings) do
      nil ->
        leaf(segs, state)

      cut ->
        {front, back} = divide(segs, cut)
        {back_child, state} = partition(back, state, settings)
        {front_child, state} = partition(front, state, settings)
        {x, y, dx, dy} = cut

        node = %{
          x: x,
          y: y,
          dx: dx,
          dy: dy,
          boxes: {bounds(front), bounds(back)},
          children: {front_child, back_child}
        }

        {{:node, length(state.nodes)}, %{state | nodes: [node | state.nodes]}}
    end
  end

  defp leaf(segs, state) do
    first = length(state.segs)
    sector = SectorMap.side_sector(state.map, hd(segs).line, hd(segs).side)
    subsector = %{first: first, count: length(segs), sector: sector}

    {{:leaf, length(state.subsectors)},
     %{state | segs: Enum.reverse(segs) ++ state.segs, subsectors: [subsector | state.subsectors]}}
  end

  defp choose(segs, settings) do
    if convex?(segs) do
      nil
    else
      segs
      |> sample(settings.candidates)
      |> Enum.map(&cut_of/1)
      |> Enum.uniq()
      |> Enum.map(&{&1, cost(segs, &1, settings)})
      |> Enum.reject(fn {_cut, cost} -> cost == :none end)
      |> Enum.min_by(fn {_cut, cost} -> cost end, fn -> nil end)
      |> then(fn
        nil -> nil
        {cut, _cost} -> cut
      end)
    end
  end

  defp sample(segs, count) do
    total = length(segs)

    if total <= count,
      do: segs,
      else: segs |> Enum.take_every(max(1, div(total, count))) |> Enum.take(count)
  end

  defp cut_of(%{from: {x, y}, to: {tx, ty}}), do: {x, y, tx - x, ty - y}

  defp cost(segs, cut, settings) do
    {front, back, splits} =
      Enum.reduce(segs, {0, 0, 0}, fn seg, {front, back, splits} ->
        case classify(seg, cut) do
          :front -> {front + 1, back, splits}
          :back -> {front, back + 1, splits}
          :split -> {front + 1, back + 1, splits + 1}
        end
      end)

    if front == 0 or back == 0,
      do: :none,
      else: splits * settings.split_cost + abs(front - back)
  end

  defp convex?(segs) do
    Enum.all?(segs, fn seg ->
      cut = cut_of(seg)
      Enum.all?(segs, &(classify(&1, cut) == :front))
    end)
  end

  defp classify(%{from: from, to: to}, cut) do
    case {where(from, cut), where(to, cut)} do
      {:on, :on} -> if same_direction?(from, to, cut), do: :front, else: :back
      {side, :on} -> side
      {:on, side} -> side
      {side, side} -> side
      _crossing -> :split
    end
  end

  defp where({px, py}, {x, y, dx, dy}) do
    length = :math.sqrt(dx * dx + dy * dy)
    value = ((py - y) * dx - dy * (px - x)) / max(length, @epsilon)

    cond do
      value < -@epsilon * 1000 -> :front
      value > @epsilon * 1000 -> :back
      true -> :on
    end
  end

  defp same_direction?({fx, fy}, {tx, ty}, {_x, _y, dx, dy}),
    do: (tx - fx) * dx + (ty - fy) * dy > 0

  defp divide(segs, cut) do
    Enum.reduce(segs, {[], []}, fn seg, {front, back} ->
      case classify(seg, cut) do
        :front -> {[seg | front], back}
        :back -> {front, [seg | back]}
        :split -> split(seg, cut, front, back)
      end
    end)
    |> then(fn {front, back} -> {Enum.reverse(front), Enum.reverse(back)} end)
  end

  defp split(%{from: {fx, fy} = from, to: {tx, ty}} = seg, {x, y, dx, dy} = cut, front, back) do
    s1 = (fy - y) * dx - dy * (fx - x)
    s2 = (ty - y) * dx - dy * (tx - x)
    t = s1 / (s1 - s2)
    middle = {fx + (tx - fx) * t, fy + (ty - fy) * t}
    first = %{seg | to: middle}
    second = %{seg | from: middle, offset: seg.offset + distance(from, middle)}

    if where(from, cut) == :front,
      do: {[first | front], [second | back]},
      else: {[second | front], [first | back]}
  end

  defp distance({ax, ay}, {bx, by}), do: :math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay))

  defp bounds(segs) do
    points = Enum.flat_map(segs, &[&1.from, &1.to])
    {xs, ys} = Enum.unzip(points)
    {Enum.max(ys), Enum.min(ys), Enum.min(xs), Enum.max(xs)}
  end
end
