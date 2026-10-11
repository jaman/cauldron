defmodule Cauldron2D.GameMaker.Particles do
  @moduledoc """
  Particles, as GameMaker's `part_particles_create` makes them: pictures that code
  sets loose, which move, animate and fade by themselves and are gone when their life
  runs out. They are drawn with the room, at their depth, and cleared when a room is
  entered.

      world = Cauldron2D.GameMaker.Particles.create(world, %{
        sprite: flame, position: {x, y}, velocity: {0.0, -0.4}, life: 14, frame_speed: 0.5
      })

  A particle is a map:

    * `:sprite` — a sprite index; `:frame` the frame it starts on (default `0`) and
      `:frame_speed` frames a step (default `0`), wrapping. Or, in its place,
      `:picture` — any picture key of the draw list, such as `:pixel`, drawn from its
      top-left corner
    * `:position` (required) `{x, y}`; `:velocity` `{x, y}` pixels a step (default
      still); `:gravity` `{x, y}` added to the velocity every step (default none)
    * `:life` (required) — the steps it lasts
    * `:alpha` `{from, to}`, faded across its life (default `{1.0, 1.0}`); `:blend`
      `{r, g, b}`; `:scale` `{x, y}`; `:depth` (default `0`)
  """

  alias Cauldron2D.GameMaker.World

  @type particle :: %{
          required(:position) => {number(), number()},
          required(:life) => pos_integer(),
          optional(atom()) => term()
        }

  @doc "The world with `particle` set loose."
  @spec create(World.t(), particle()) :: World.t()
  def create(
        %World{particles: particles} = world,
        %{position: _, life: life} = particle
      )
      when life > 0 and (is_map_key(particle, :sprite) or is_map_key(particle, :picture)) do
    defaults = %{
      frame: 0,
      frame_speed: 0,
      velocity: {0.0, 0.0},
      gravity: {0.0, 0.0},
      alpha: {1.0, 1.0},
      depth: 0,
      age: 0
    }

    %{world | particles: [Map.merge(defaults, particle) | particles]}
  end

  @doc "The world with every particle one step on, and those whose life is over gone."
  @spec step(World.t()) :: World.t()
  def step(%World{particles: particles} = world) do
    moved =
      for particle <- particles, particle.age + 1 < particle.life, do: advance(particle)

    %{world | particles: moved}
  end

  @doc """
  The particles for which `pick` is true, taken out of the world: `{taken, world}`. A
  particle keeps any keys of its own it was created with, so `pick` can tell kinds
  apart.
  """
  @spec take(World.t(), (particle() -> boolean())) :: {[particle()], World.t()}
  def take(%World{particles: particles} = world, pick) do
    {taken, kept} = Enum.split_with(particles, pick)
    {taken, %{world | particles: kept}}
  end

  @doc "The particles as draw list items, each naming `{:sprite, sprite, frame}` or its own picture."
  @spec items(World.t()) :: [map()]
  def items(%World{particles: particles} = world) do
    for particle <- particles, item = item(world, particle), item != nil do
      {from, to} = particle.alpha

      item
      |> Map.merge(%{
        position: particle.position,
        alpha: from + (to - from) * particle.age / particle.life,
        depth: particle.depth
      })
      |> Map.merge(Map.take(particle, [:blend, :scale]))
    end
  end

  defp item(_world, %{picture: picture}), do: %{picture: picture, origin: {0, 0}}

  defp item(world, %{sprite: index, frame: frame}) do
    case World.sprite(world, index) do
      nil ->
        nil

      sprite ->
        frames = length(sprite.frames)
        %{picture: {:sprite, index, Integer.mod(floor(frame), frames)}, origin: sprite.origin}
    end
  end

  defp advance(%{position: {x, y}, velocity: {vx, vy}, gravity: {gx, gy}} = particle) do
    %{
      particle
      | position: {x + vx, y + vy},
        velocity: {vx + gx, vy + gy},
        frame: particle.frame + particle.frame_speed,
        age: particle.age + 1
    }
  end
end
