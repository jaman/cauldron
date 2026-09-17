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
  """

  alias Cauldron2D.Body

  @type particle :: %{art: term(), pos: Body.point(), vel: Body.point(), ttl: number()}
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
  The particles as `{art, {x, y}}` movers, oldest first, each position shifted by `offset`.

  The offset is what turns a particle's centre into the top-left corner a sprite is drawn
  from; `{-0.5, -0.5}` centres a one-tile sprite.
  """
  @spec movers(t(), Body.point()) :: [{term(), Body.point()}]
  def movers(%__MODULE__{items: items}, {ox, oy} \\ {0.0, 0.0}) do
    for %{art: art, pos: {x, y}} <- items, do: {art, {x + ox, y + oy}}
  end

  @doc "How many particles are alive."
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{items: items}), do: length(items)
end
