defmodule Cauldron2D.Body do
  @moduledoc """
  A point mass with a heading: position, velocity, and one of `headings` directions.

  Positions and velocities are in tiles and tiles per second. Heading `0` points right,
  and headings increase counter-clockwise on screen, so a quarter of them points up.

      body =
        Cauldron2D.Body.new(pos: {4.0, 4.0}, headings: 64)
        |> Cauldron2D.Body.turn(16)
        |> Cauldron2D.Body.thrust(20.0, dt)
        |> Cauldron2D.Body.gravitate(fields, dt)
        |> Cauldron2D.Body.drag(0.1, dt)
        |> Cauldron2D.Body.integrate(dt)

  ## Gravity fields

  `gravitate/3` takes a list of maps:

    * `%{pos: {x, y}, strength: s, kind: :attract | :repel}` — pulls toward or pushes
      from `pos`, falling off with the square of the distance and capped within one tile
    * `%{pos: {x, y}, strength: s, kind: :clockwise | :anticlockwise}` — pushes across
      the line to `pos`, same falloff
    * `%{strength: s, kind: {:uniform, {dx, dy}}}` — a constant pull in a direction
    * `%{strength: s, kind: {:toward, {x, y}}}` — a constant pull toward a point from
      anywhere, away from it when `s` is negative
  """

  @type point :: {float(), float()}
  @type field :: %{
          optional(:pos) => point(),
          required(:strength) => number(),
          required(:kind) =>
            :attract
            | :repel
            | :clockwise
            | :anticlockwise
            | {:uniform, point()}
            | {:toward, point()}
        }
  @type t :: %__MODULE__{
          pos: point(),
          vel: point(),
          heading: non_neg_integer(),
          headings: pos_integer(),
          mass: float(),
          radius: float()
        }

  defstruct pos: {0.0, 0.0}, vel: {0.0, 0.0}, heading: 0, headings: 64, mass: 1.0, radius: 0.5

  @doc """
  A body at rest.

  ## Options

    * `:pos` — `{x, y}` in tiles. Default `{0.0, 0.0}`
    * `:vel` — `{vx, vy}` in tiles per second. Default `{0.0, 0.0}`
    * `:heading` — index into the headings. Default `0`
    * `:headings` — how many directions the body can face. Default `64`
    * `:mass` — used by callers that trade momentum. Default `1.0`
    * `:radius` — in tiles, for collision. Default `0.5`
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []), do: struct!(__MODULE__, floats(opts))

  defp floats(opts) do
    Enum.map(opts, fn
      {:pos, {x, y}} -> {:pos, {x / 1, y / 1}}
      {:vel, {x, y}} -> {:vel, {x / 1, y / 1}}
      {:mass, m} -> {:mass, m / 1}
      {:radius, r} -> {:radius, r / 1}
      other -> other
    end)
  end

  @doc "Turn by `steps` headings; negative turns clockwise. Wraps around the circle."
  @spec turn(t(), integer()) :: t()
  def turn(%__MODULE__{} = body, steps) do
    %{body | heading: Integer.mod(body.heading + steps, body.headings)}
  end

  @doc "The heading as radians, counter-clockwise from right."
  @spec angle(t()) :: float()
  def angle(%__MODULE__{heading: heading, headings: headings}) do
    2 * :math.pi() * heading / headings
  end

  @doc "The unit vector the body faces, in screen coordinates (y grows downward)."
  @spec direction(t()) :: point()
  def direction(%__MODULE__{} = body) do
    theta = angle(body)
    {:math.cos(theta), -:math.sin(theta)}
  end

  @doc "Accelerate along the heading by `accel` tiles per second squared for `dt` seconds."
  @spec thrust(t(), number(), number()) :: t()
  def thrust(%__MODULE__{vel: {vx, vy}} = body, accel, dt) do
    {dx, dy} = direction(body)
    %{body | vel: {vx + dx * accel * dt, vy + dy * accel * dt}}
  end

  @doc "Add `{ax, ay}` tiles per second squared for `dt` seconds."
  @spec accelerate(t(), point(), number()) :: t()
  def accelerate(%__MODULE__{vel: {vx, vy}} = body, {ax, ay}, dt) do
    %{body | vel: {vx + ax * dt, vy + ay * dt}}
  end

  @doc """
  Slow the body by `coefficient` of its velocity per second, for `dt` seconds.

  The velocity is scaled by `exp(-coefficient * dt)`, so it approaches zero without ever
  reversing.
  """
  @spec drag(t(), number(), number()) :: t()
  def drag(%__MODULE__{vel: {vx, vy}} = body, coefficient, dt) do
    factor = :math.exp(-coefficient * dt)
    %{body | vel: {vx * factor, vy * factor}}
  end

  @doc "Move by the velocity for `dt` seconds."
  @spec integrate(t(), number()) :: t()
  def integrate(%__MODULE__{pos: {x, y}, vel: {vx, vy}} = body, dt) do
    %{body | pos: {x + vx * dt, y + vy * dt}}
  end

  @doc "The velocity's length in tiles per second."
  @spec speed(t()) :: float()
  def speed(%__MODULE__{vel: {vx, vy}}), do: :math.sqrt(vx * vx + vy * vy)

  @doc "Scale the velocity down to `limit` if it is faster; slower bodies are untouched."
  @spec cap_speed(t(), number()) :: t()
  def cap_speed(%__MODULE__{vel: {vx, vy}} = body, limit) do
    current = speed(body)

    if current > limit do
      %{body | vel: {vx * limit / current, vy * limit / current}}
    else
      body
    end
  end

  @doc "Apply every field in `fields` for `dt` seconds."
  @spec gravitate(t(), [field()], number()) :: t()
  def gravitate(%__MODULE__{} = body, fields, dt) do
    Enum.reduce(fields, body, fn field, acc -> accelerate(acc, pull(acc, field), dt) end)
  end

  defp pull(_body, %{kind: {:uniform, {dx, dy}}, strength: strength}) do
    {dx * strength, dy * strength}
  end

  defp pull(%__MODULE__{pos: {x, y}}, %{kind: {:toward, {fx, fy}}, strength: strength}) do
    {dx, dy} = {fx - x, fy - y}
    distance = :math.sqrt(dx * dx + dy * dy)
    if distance == 0.0, do: {0.0, 0.0}, else: {dx / distance * strength, dy / distance * strength}
  end

  defp pull(%__MODULE__{pos: {x, y}}, %{pos: {fx, fy}, strength: strength, kind: kind}) do
    {dx, dy} = {fx - x, fy - y}
    distance_sq = dx * dx + dy * dy

    if distance_sq == 0.0 do
      {0.0, 0.0}
    else
      distance = :math.sqrt(distance_sq)
      magnitude = strength / max(distance_sq, 1.0)
      {ux, uy} = {dx / distance, dy / distance}
      oriented(kind, {ux, uy}, magnitude)
    end
  end

  defp oriented(:attract, {ux, uy}, m), do: {ux * m, uy * m}
  defp oriented(:repel, {ux, uy}, m), do: {-ux * m, -uy * m}
  defp oriented(:clockwise, {ux, uy}, m), do: {uy * m, -ux * m}
  defp oriented(:anticlockwise, {ux, uy}, m), do: {-uy * m, ux * m}

  @doc "Bring a body that has left a `{width, height}` world back in on the opposite side."
  @spec wrap(t(), {number(), number()}) :: t()
  def wrap(%__MODULE__{pos: {x, y}} = body, {width, height}) do
    %{body | pos: {wrap_axis(x, width), wrap_axis(y, height)}}
  end

  defp wrap_axis(value, extent) when value < 0, do: value + extent
  defp wrap_axis(value, extent) when value >= extent, do: value - extent
  defp wrap_axis(value, _extent), do: value
end
