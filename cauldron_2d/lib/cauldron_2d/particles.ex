defmodule Cauldron2D.Particles do
  @moduledoc """
  Short-lived sprites — sparks, debris, smoke — with a cap on how many exist at once.

      particles =
        Cauldron2D.Particles.new(300)
        |> Cauldron2D.Particles.spawn([%{art: :spark, pos: {x, y}, vel: {vx, vy}, ttl: 0.4}])
        |> Cauldron2D.Particles.step(dt, fields: gravity, drag: 0.5)

      Cauldron2D.Particles.movers(particles, {-0.5, -0.5})

  A particle is `%{art: art, pos: {x, y}, vel: {vx, vy}, ttl: seconds}`. When spawning
  would exceed the cap, the oldest particles go first.

  A particle may change as it lives: with `:life` (the seconds it was given) and `:arts`,
  a list of arts, it shows the art for how much of its life is gone — a spark fading, a
  puff of smoke growing; with `:tints`, a list of tint names (`Cauldron2D.Atlas.tint/3`),
  it is shaded by them the same way. `Cauldron2D.Particles.Emitter` makes particles at a
  rate or in bursts, with these filled in.
  """

  alias Cauldron2D.Body

  @type particle :: %{
          required(:art) => term(),
          required(:pos) => Body.point(),
          required(:vel) => Body.point(),
          required(:ttl) => number(),
          optional(:life) => number(),
          optional(:arts) => [term()],
          optional(:tints) => [atom()]
        }
  @type t :: %__MODULE__{cap: pos_integer(), items: [particle()]}

  defstruct cap: 200, items: []

  @doc "An empty set holding at most `cap` particles."
  @spec new(pos_integer()) :: t()
  def new(cap) when is_integer(cap) and cap > 0, do: %__MODULE__{cap: cap}

  @doc "Add `particles`, dropping the oldest when the cap is exceeded."
  @spec spawn(t(), [particle()]) :: t()
  def spawn(%__MODULE__{} = particles, new_items) do
    items = particles.items ++ new_items
    %{particles | items: Enum.take(items, -particles.cap)}
  end

  @doc """
  Move every particle for `dt` seconds and drop those whose time is up.

  ## Options

    * `:fields` — gravity fields as `Cauldron2D.Body.gravitate/3` takes. Default `[]`
    * `:drag` — a coefficient as `Cauldron2D.Body.drag/3` takes. Default `0`
  """
  @spec step(t(), number(), keyword()) :: t()
  def step(%__MODULE__{} = particles, dt, opts \\ []) do
    fields = Keyword.get(opts, :fields, [])
    drag = Keyword.get(opts, :drag, 0)

    items =
      particles.items
      |> Enum.map(&advance(&1, dt, fields, drag))
      |> Enum.filter(&(&1.ttl > 0))

    %{particles | items: items}
  end

  defp advance(particle, dt, fields, drag) do
    body =
      %Body{pos: particle.pos, vel: particle.vel}
      |> Body.gravitate(fields, dt)
      |> Body.drag(drag, dt)
      |> Body.integrate(dt)

    %{particle | pos: body.pos, vel: body.vel, ttl: particle.ttl - dt}
  end

  @doc """
  The particles as movers, oldest first, each position shifted by `offset`: `{art, {x, y}}`,
  or `{art, {x, y}, nil, %{tint: tint}}` for a particle with `:tints`, the art and tint
  those of its age when it has `:arts` and `:tints`.

  The offset is what turns a particle's centre into the top-left corner a sprite is drawn
  from; `{-0.5, -0.5}` centres a one-tile sprite.
  """
  @spec movers(t(), Body.point()) :: [tuple()]
  def movers(%__MODULE__{items: items}, {ox, oy} \\ {0.0, 0.0}) do
    for %{pos: {x, y}} = particle <- items, do: mover(particle, {x + ox, y + oy})
  end

  @doc "How much of a particle's life is gone, `0.0..1.0`; `0.0` for one without `:life`."
  @spec spent(particle()) :: float()
  def spent(%{life: life, ttl: ttl}) when life > 0, do: min(1.0, max(0.0, 1.0 - ttl / life))
  def spent(_particle), do: 0.0

  @doc "How many particles are alive."
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{items: items}), do: length(items)

  defp mover(%{tints: [_ | _] = tints} = particle, at),
    do: {art(particle), at, nil, %{tint: of_life(tints, particle)}}

  defp mover(particle, at), do: {art(particle), at}

  defp art(%{arts: [_ | _] = arts} = particle), do: of_life(arts, particle)
  defp art(%{art: art}), do: art

  defp of_life(list, particle),
    do: Enum.at(list, min(length(list) - 1, trunc(spent(particle) * length(list))))
end
