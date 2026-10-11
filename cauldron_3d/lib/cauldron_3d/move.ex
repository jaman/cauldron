defmodule Cauldron3D.Move do
  @moduledoc """
  Moving a box through a world: sliding along what it hits, and stepping up ledges.

  Every function takes `trace`, `fn from, to -> Cauldron3D.Hull.Trace.t() end`, which
  says how far the box gets along a straight line; the caller decides what it collides
  with.

      Cauldron3D.Move.slide(trace, origin, velocity, 1 / 72)
      #=> %{origin: ..., velocity: ..., blocked: [:floor], hits: [trace, ...]}
  """

  alias Cauldron3D.Hull.Trace
  alias Cauldron3D.Vec

  @type tracer :: (Vec.t(), Vec.t() -> Trace.t())
  @type result :: %{
          origin: Vec.t(),
          velocity: Vec.t(),
          blocked: [:floor | :wall],
          hits: [Trace.t()]
        }

  @doc """
  `velocity` with the part going into a plane of `normal` taken out, `overbounce` times
  over (1.0 slides along it, more than 1.0 bounces off). Components smaller than 0.1 come
  out as zero.
  """
  @spec clip(Vec.t(), Vec.t(), number()) :: Vec.t()
  def clip(velocity, normal, overbounce \\ 1.0) do
    backoff = Vec.dot(velocity, normal) * overbounce
    {x, y, z} = Vec.madd(velocity, normal, -backoff)
    {settle(x), settle(y), settle(z)}
  end

  @doc """
  Move for `seconds` at `velocity`, sliding along up to four surfaces. A hit plane whose
  normal points up more than `:floor` (default 0.7) blocks as a floor; an upright one as
  a wall. The velocity is stopped when it would turn back on itself or is pinned in a
  corner.
  """
  @spec slide(tracer(), Vec.t(), Vec.t(), number(), keyword()) :: result()
  def slide(trace, origin, velocity, seconds, opts \\ []) do
    floor = Keyword.get(opts, :floor, 0.7)

    state = %{
      origin: origin,
      velocity: velocity,
      original: velocity,
      primal: velocity,
      planes: [],
      left: seconds / 1,
      blocked: [],
      hits: []
    }

    state
    |> bump(trace, floor, 4)
    |> Map.take([:origin, :velocity, :blocked, :hits])
    |> Map.update!(:blocked, &Enum.uniq/1)
    |> Map.update!(:hits, &Enum.reverse/1)
  end

  @doc """
  As `slide/5`, but a box stopped by a wall tries again from up to `step` higher and
  settles back down, keeping whichever went further along the ground. Takes `slide/5`'s
  options.
  """
  @spec step(tracer(), Vec.t(), Vec.t(), number(), number(), keyword()) :: result()
  def step(trace, origin, velocity, seconds, step, opts \\ []) do
    flat = slide(trace, origin, velocity, seconds, opts)

    if :wall in flat.blocked,
      do: better(flat, climb(trace, origin, velocity, seconds, step, opts), origin, opts),
      else: flat
  end

  defp climb(trace, origin, velocity, seconds, step, opts) do
    lifted = trace.(origin, Vec.add(origin, {0.0, 0.0, step / 1}))
    rise = elem(lifted.end_pos, 2) - elem(origin, 2)
    climbed = slide(trace, lifted.end_pos, velocity, seconds, opts)
    landed = trace.(climbed.origin, Vec.add(climbed.origin, {0.0, 0.0, -rise}))
    {%{climbed | origin: landed.end_pos}, landed}
  end

  defp better(flat, {climbed, landed}, origin, opts) do
    floor = Keyword.get(opts, :floor, 0.7)

    if horizontal(climbed.origin, origin) > horizontal(flat.origin, origin) and
         elem(landed.normal, 2) > floor,
       do: climbed,
       else: flat
  end

  defp horizontal({x, y, _}, {ox, oy, _}), do: (x - ox) * (x - ox) + (y - oy) * (y - oy)

  defp bump(state, _trace, _floor, 0), do: state

  defp bump(%{velocity: {x, y, z}} = state, _trace, _floor, _left)
       when x == 0 and y == 0 and z == 0,
       do: state

  defp bump(state, trace, floor, left) do
    to = Vec.madd(state.origin, state.velocity, state.left)
    hit = trace.(state.origin, to)

    cond do
      hit.all_solid ->
        %{state | velocity: Vec.zero(), blocked: [:floor, :wall | state.blocked]}

      hit.fraction == 1.0 ->
        %{state | origin: hit.end_pos}

      true ->
        state
        |> advance(hit)
        |> record(hit, floor)
        |> deflect()
        |> continue(trace, floor, left)
    end
  end

  defp advance(state, %Trace{fraction: fraction} = hit) when fraction > 0,
    do: %{state | origin: hit.end_pos, original: state.velocity, planes: []}

  defp advance(state, _hit), do: state

  defp record(state, hit, floor) do
    {_, _, nz} = hit.normal

    blocked =
      cond do
        nz > floor -> [:floor | state.blocked]
        nz == 0.0 -> [:wall | state.blocked]
        true -> state.blocked
      end

    %{
      state
      | blocked: blocked,
        hits: [hit | state.hits],
        left: state.left - state.left * hit.fraction,
        planes: state.planes ++ [hit.normal]
    }
  end

  defp deflect(%{planes: planes} = state) when length(planes) > 5,
    do: %{state | velocity: Vec.zero()}

  defp deflect(state) do
    case Enum.find_value(state.planes, &parallel(state, &1)) do
      nil -> crease(state)
      velocity -> %{state | velocity: velocity}
    end
  end

  defp parallel(state, plane) do
    clipped = clip(state.original, plane)
    if Enum.all?(state.planes, &(&1 == plane or Vec.dot(clipped, &1) >= 0)), do: clipped
  end

  defp crease(%{planes: [a, b]} = state) do
    direction = Vec.cross(a, b)
    %{state | velocity: Vec.scale(direction, Vec.dot(direction, state.velocity))}
  end

  defp crease(state), do: %{state | velocity: Vec.zero()}

  defp continue(state, trace, floor, left) do
    if Vec.dot(state.velocity, state.primal) <= 0,
      do: %{state | velocity: Vec.zero()},
      else: bump(state, trace, floor, left - 1)
  end

  defp settle(component) when component > -0.1 and component < 0.1, do: 0.0
  defp settle(component), do: component
end
