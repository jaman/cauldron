defmodule Cauldron2D.Particles.Emitter do
  @moduledoc """
  Makes particles (`Cauldron2D.Particles`): a steady stream at a rate — smoke from a
  chimney, sparks from a torch — or a burst at once — debris from a blast. Each particle
  leaves at an angle within the spread, at a speed and for a time drawn from their
  ranges, from the game's generator (`Cauldron.Rng`), so a replay makes the same ones.

      sparks = %Cauldron2D.Particles.Emitter{
        at: {torch.x, torch.y},
        rate: 30.0,
        angle: -:math.pi() / 2,
        spread: 0.8,
        speed: {2.0, 4.0},
        ttl: {0.3, 0.6},
        arts: [:spark_bright, :spark, :spark_dim]
      }

      {made, sparks, rng} = Emitter.emit(sparks, dt, rng)
      particles = Cauldron2D.Particles.spawn(particles, made)

  Fields: `:at` (where they start, tiles), `:rate` (a second), `:angle` (the middle of
  the spread, radians, `0` along `+x`, `y` growing downward), `:spread` (radians across;
  `2π` all round), `:speed` and `:ttl` (`{least, most}`, or one number), `:art`, or
  `:arts` and `:tints` to change over each particle's life.
  """

  defstruct at: {0.0, 0.0},
            rate: 10.0,
            angle: 0.0,
            spread: 2 * :math.pi(),
            speed: {1.0, 2.0},
            ttl: {0.5, 1.0},
            art: nil,
            arts: nil,
            tints: nil,
            owed: 0.0

  @type range :: number() | {number(), number()}
  @type t :: %__MODULE__{
          at: {number(), number()},
          rate: number(),
          angle: number(),
          spread: number(),
          speed: range(),
          ttl: range(),
          art: term(),
          arts: [term()] | nil,
          tints: [atom()] | nil,
          owed: number()
        }

  @doc "The particles `dt` seconds of the stream make, the emitter (keeping what is owed between steps) and the generator."
  @spec emit(t(), number(), Cauldron.Rng.t()) ::
          {[Cauldron2D.Particles.particle()], t(), Cauldron.Rng.t()}
  def emit(emitter, dt, rng) do
    owed = emitter.owed + emitter.rate * dt
    count = trunc(owed)
    {made, rng} = burst(emitter, count, rng)
    {made, %{emitter | owed: owed - count}, rng}
  end

  @doc "`count` particles at once, and the generator."
  @spec burst(t(), non_neg_integer(), Cauldron.Rng.t()) ::
          {[Cauldron2D.Particles.particle()], Cauldron.Rng.t()}
  def burst(_emitter, 0, rng), do: {[], rng}

  def burst(emitter, count, rng) do
    Enum.map_reduce(1..count, rng, fn _n, rng -> particle(emitter, rng) end)
  end

  defp particle(emitter, rng) do
    {turn, rng} = draw({-0.5, 0.5}, rng)
    {speed, rng} = draw(emitter.speed, rng)
    {ttl, rng} = draw(emitter.ttl, rng)
    angle = emitter.angle + turn * emitter.spread

    particle =
      %{
        art: emitter.art || List.first(emitter.arts || []),
        pos: emitter.at,
        vel: {:math.cos(angle) * speed, :math.sin(angle) * speed},
        ttl: ttl,
        life: ttl
      }
      |> with_list(:arts, emitter.arts)
      |> with_list(:tints, emitter.tints)

    {particle, rng}
  end

  defp with_list(particle, _key, nil), do: particle
  defp with_list(particle, key, list), do: Map.put(particle, key, list)

  defp draw({least, most}, rng) do
    {n, rng} = Cauldron.Rng.between(rng, 0, 1000)
    {least + (most - least) * n / 1000, rng}
  end

  defp draw(value, rng), do: {value / 1, rng}
end
