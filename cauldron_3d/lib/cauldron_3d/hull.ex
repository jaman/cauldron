defmodule Cauldron3D.Hull do
  @moduledoc """
  A collision hull: a BSP tree of planes whose leaves are only contents, swept by a point.

  A box moves through a world by tracing a point through a hull whose walls are pushed
  out by the box's size; a world keeps one hull per box size it allows. A thing's own
  box is a hull too (`box/2`).

      trace = Cauldron3D.Hull.trace(hull, from, to)
      trace.fraction

  `clipnodes` is a tuple of `{plane, front, back}`, the plane an index into `planes`
  (`{normal, distance}`); a child at or above zero is another clipnode, below zero a
  contents value (see `Cauldron3D.Bsp`). `head` is the clipnode to start from, and
  `mins` and `maxs` the box the hull was pushed out by.
  """

  alias Cauldron3D.{Bsp, Vec}

  defmodule Trace do
    @moduledoc """
    What a traced move ran into.

      * `fraction` — how much of the move was made, 1.0 when nothing was hit
      * `end_pos` — where it stopped
      * `normal`, `distance` — the plane hit, facing back along the move
      * `all_solid` — the whole move was inside solid
      * `start_solid` — it started inside solid
      * `in_open`, `in_water` — whether it passed through empty or liquid space
      * `hit` — what was hit, for the caller to fill in; `nil` from a hull
    """

    @type t :: %__MODULE__{
            fraction: float(),
            end_pos: Cauldron3D.Vec.t(),
            normal: Cauldron3D.Vec.t(),
            distance: float(),
            all_solid: boolean(),
            start_solid: boolean(),
            in_open: boolean(),
            in_water: boolean(),
            hit: term()
          }

    defstruct fraction: 1.0,
              end_pos: {0.0, 0.0, 0.0},
              normal: {0.0, 0.0, 0.0},
              distance: 0.0,
              all_solid: true,
              start_solid: false,
              in_open: false,
              in_water: false,
              hit: nil
  end

  @type t :: %__MODULE__{
          clipnodes: tuple(),
          planes: tuple(),
          head: integer(),
          mins: Vec.t(),
          maxs: Vec.t()
        }

  defstruct clipnodes: {}, planes: {}, head: 0, mins: {0.0, 0.0, 0.0}, maxs: {0.0, 0.0, 0.0}

  @epsilon 0.03125

  @doc "The hull starting at clipnode `head` instead."
  @spec at(t(), integer()) :: t()
  def at(%__MODULE__{} = hull, head), do: %{hull | head: head}

  @doc """
  A hull that is solid inside the box `mins`..`maxs` and empty outside, for tracing past
  a thing.
  """
  @spec box(Vec.t(), Vec.t()) :: t()
  def box({x0, y0, z0}, {x1, y1, z1}) do
    planes = {
      {{1.0, 0.0, 0.0}, x1 / 1},
      {{1.0, 0.0, 0.0}, x0 / 1},
      {{0.0, 1.0, 0.0}, y1 / 1},
      {{0.0, 1.0, 0.0}, y0 / 1},
      {{0.0, 0.0, 1.0}, z1 / 1},
      {{0.0, 0.0, 1.0}, z0 / 1}
    }

    clipnodes =
      for index <- 0..5 do
        next = if index == 5, do: Bsp.solid(), else: index + 1
        if rem(index, 2) == 0, do: {index, Bsp.empty(), next}, else: {index, next, Bsp.empty()}
      end
      |> List.to_tuple()

    %__MODULE__{
      clipnodes: clipnodes,
      planes: planes,
      head: 0,
      mins: {x0, y0, z0},
      maxs: {x1, y1, z1}
    }
  end

  @doc "The contents at `point`."
  @spec contents(t(), Vec.t()) :: integer()
  def contents(%__MODULE__{} = hull, point), do: contents_from(hull, hull.head, point)

  @doc """
  A point moved in a straight line from `from` to `to` through the hull, stopped by the
  first solid it meets.
  """
  @spec trace(t(), Vec.t(), Vec.t()) :: Trace.t()
  def trace(%__MODULE__{} = hull, from, to) do
    {_going, trace} = check(hull, hull.head, 0.0, 1.0, from, to, %Trace{end_pos: to})
    trace
  end

  defp contents_from(_hull, node, _point) when node < 0, do: node

  defp contents_from(hull, node, point) do
    {plane, front, back} = elem(hull.clipnodes, node)
    {normal, distance} = elem(hull.planes, plane)

    if Vec.dot(point, normal) - distance >= 0,
      do: contents_from(hull, front, point),
      else: contents_from(hull, back, point)
  end

  defp check(_hull, node, _from_f, _to_f, _from, _to, trace) when node < 0 do
    solid = Bsp.solid()
    empty = Bsp.empty()

    trace =
      case node do
        ^solid -> %{trace | start_solid: true}
        ^empty -> %{trace | all_solid: false, in_open: true}
        _liquid -> %{trace | all_solid: false, in_water: true}
      end

    {true, trace}
  end

  defp check(hull, node, from_f, to_f, from, to, trace) do
    {plane, front, back} = elem(hull.clipnodes, node)
    {normal, distance} = elem(hull.planes, plane)
    t1 = Vec.dot(from, normal) - distance
    t2 = Vec.dot(to, normal) - distance

    cond do
      t1 >= 0 and t2 >= 0 ->
        check(hull, front, from_f, to_f, from, to, trace)

      t1 < 0 and t2 < 0 ->
        check(hull, back, from_f, to_f, from, to, trace)

      true ->
        straddle(
          hull,
          {front, back},
          {normal, distance},
          {t1, t2},
          {from_f, to_f, from, to},
          trace
        )
    end
  end

  defp straddle(hull, {front, back}, plane, {t1, t2}, {from_f, to_f, from, to}, trace) do
    fraction = if t1 < 0, do: (t1 + @epsilon) / (t1 - t2), else: (t1 - @epsilon) / (t1 - t2)
    fraction = fraction |> max(0.0) |> min(1.0)
    mid_f = from_f + (to_f - from_f) * fraction
    mid = Vec.lerp(from, to, fraction)
    {near, far, side} = if t1 < 0, do: {back, front, :back}, else: {front, back, :front}

    case check(hull, near, from_f, mid_f, from, mid, trace) do
      {false, trace} ->
        {false, trace}

      {true, trace} ->
        cond do
          contents_from(hull, far, mid) != Bsp.solid() ->
            check(hull, far, mid_f, to_f, mid, to, trace)

          trace.all_solid ->
            {false, trace}

          true ->
            {false, impact(hull, plane, side, {from_f, to_f, from, to}, fraction, trace)}
        end
    end
  end

  defp impact(hull, {normal, distance}, side, move, fraction, trace) do
    {normal, distance} =
      if side == :front, do: {normal, distance}, else: {Vec.scale(normal, -1.0), -distance}

    trace = %{trace | normal: normal, distance: distance}
    back_off(hull, move, fraction, trace)
  end

  defp back_off(hull, {from_f, to_f, from, to} = move, fraction, trace) do
    mid_f = from_f + (to_f - from_f) * fraction
    mid = Vec.lerp(from, to, fraction)

    cond do
      contents_from(hull, hull.head, mid) != Bsp.solid() ->
        %{trace | fraction: mid_f, end_pos: mid}

      fraction - 0.1 < 0 ->
        %{trace | fraction: mid_f, end_pos: mid}

      true ->
        back_off(hull, move, fraction - 0.1, trace)
    end
  end
end
