defmodule Cauldron2D.Sectors.Automap do
  @moduledoc """
  A map of the level drawn from above, out of the lines the player has seen: as lines for
  `Cauldron2D.Sectors.Frame.lines/2`.

      lines = Cauldron2D.Sectors.Automap.lines(map, sectors, seen, view, colours)
      frame |> Frame.fill(0) |> Frame.lines(lines ++ Cauldron2D.Sectors.Automap.arrow(view, 209))

  `seen` is the set of line indexes seen so far — the union of
  `Cauldron2D.Sectors.View.render/5`'s `seen` over the game. A line flagged `:mapped` is
  shown whether seen or not, one flagged `:hidden` never. With `all: true` every unseen
  line is drawn too, in the `:unseen` colour.

  `view` is `%{x:, y:, angle:, scale:, center: {cx, cy}, rotate: false}`: the world point at
  the frame's `center`, `scale` pixels to a world unit, and with `rotate: true` the map
  turned so `angle` points up the screen.

  `colours` maps each kind of line to a colour index: `:wall` (nothing behind it, or a
  `:secret` line), `:floor_step`, `:ceiling_step`, `:plain` (an opening with no step,
  left out where there is no colour for it) and `:unseen`.
  """

  alias Cauldron2D.Sectors.Map, as: SectorMap

  @type view :: %{
          required(:x) => number(),
          required(:y) => number(),
          required(:angle) => number(),
          required(:scale) => number(),
          required(:center) => {number(), number()},
          optional(:rotate) => boolean()
        }

  @doc "The map's lines as frame lines. See the moduledoc."
  @spec lines(SectorMap.t(), tuple(), MapSet.t(), view(), map(), keyword()) ::
          [{integer(), integer(), integer(), integer(), byte()}]
  def lines(%SectorMap{} = map, sectors, seen, view, colours, opts \\ []) do
    all? = Keyword.get(opts, :all, false)

    for index <- 0..(tuple_size(map.lines) - 1)//1,
        line = elem(map.lines, index),
        not MapSet.member?(line.flags, :hidden),
        colour = colour(map, sectors, index, line, visible?(seen, index, line), all?, colours),
        colour != nil do
      {from, to} = SectorMap.ends(map, index)
      {x0, y0} = screen(view, from)
      {x1, y1} = screen(view, to)
      {x0, y0, x1, y1, colour}
    end
  end

  defp visible?(seen, index, line),
    do: MapSet.member?(seen, index) or MapSet.member?(line.flags, :mapped)

  defp colour(_map, _sectors, _index, _line, false, true, colours), do: Map.get(colours, :unseen)
  defp colour(_map, _sectors, _index, _line, false, false, _colours), do: nil

  defp colour(map, sectors, index, line, true, _all?, colours) do
    if line.back == nil or MapSet.member?(line.flags, :secret),
      do: Map.get(colours, :wall),
      else: step_colour(map, sectors, index, colours)
  end

  defp step_colour(map, sectors, index, colours) do
    front = elem(sectors, SectorMap.side_sector(map, index, 0))
    back = elem(sectors, SectorMap.side_sector(map, index, 1))

    cond do
      front.floor != back.floor -> Map.get(colours, :floor_step)
      front.ceiling != back.ceiling -> Map.get(colours, :ceiling_step)
      true -> Map.get(colours, :plain)
    end
  end

  @doc "Where world `point` falls on the frame for `view`."
  @spec screen(view(), {number(), number()}) :: {integer(), integer()}
  def screen(view, {px, py}) do
    {dx, dy} = {px - view.x, py - view.y}
    {cx, cy} = view.center

    {rx, ry} =
      if Map.get(view, :rotate, false) do
        turn = :math.pi() / 2 - view.angle
        {dx * :math.cos(turn) - dy * :math.sin(turn), dx * :math.sin(turn) + dy * :math.cos(turn)}
      else
        {dx, dy}
      end

    {round(cx + rx * view.scale), round(cy - ry * view.scale)}
  end

  @doc "An arrow at the view's point, pointing along its angle, `size` world units long."
  @spec arrow(view(), byte(), number()) :: [{integer(), integer(), integer(), integer(), byte()}]
  def arrow(view, colour, size \\ 16.0) do
    {cos, sin} = {:math.cos(view.angle), :math.sin(view.angle)}
    tip = {view.x + cos * size, view.y + sin * size}
    tail = {view.x - cos * size, view.y - sin * size}

    left =
      {tip |> elem(0) |> Kernel.-(cos * size * 0.5) |> Kernel.-(sin * size * 0.5),
       elem(tip, 1) - sin * size * 0.5 + cos * size * 0.5}

    right =
      {elem(tip, 0) - cos * size * 0.5 + sin * size * 0.5,
       elem(tip, 1) - sin * size * 0.5 - cos * size * 0.5}

    for {a, b} <- [{tail, tip}, {tip, left}, {tip, right}] do
      {x0, y0} = screen(view, a)
      {x1, y1} = screen(view, b)
      {x0, y0, x1, y1, colour}
    end
  end
end
