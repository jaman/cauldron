defmodule Beast.Moves do
  @moduledoc """
  The beast's blows, as frame data: each has a wind-up, an active window in which it
  strikes, and a recovery, in seconds; the damage it does, how far it reaches in front
  of the beast, and how hard it throws what it hits back.

    * `:jab`, then `:cross`, then `:kick` — the combo, each pressed during the last one's
      recovery or up to 0.2 s before it
    * `:low`, then `:sweep` — the crouching combo, attacking while ducking: a low jab and
      a leg swept along the ground, struck from the crouch
    * `:heavy` — the charged blow, let go after holding the attack
    * `:air` — a flying kick, attacking off the ground
  """

  @moves %{
    jab: %{
      windup: 0.06,
      active: 0.08,
      recover: 0.16,
      damage: 1,
      reach: 1.2,
      knock: 4.0,
      next: :cross
    },
    cross: %{
      windup: 0.06,
      active: 0.08,
      recover: 0.18,
      damage: 1,
      reach: 1.3,
      knock: 5.0,
      next: :kick
    },
    kick: %{
      windup: 0.1,
      active: 0.1,
      recover: 0.26,
      damage: 2,
      reach: 1.6,
      knock: 10.0,
      next: nil
    },
    low: %{
      windup: 0.06,
      active: 0.08,
      recover: 0.16,
      damage: 1,
      reach: 1.2,
      knock: 3.0,
      next: :sweep
    },
    sweep: %{
      windup: 0.1,
      active: 0.12,
      recover: 0.28,
      damage: 2,
      reach: 1.7,
      knock: 8.0,
      next: nil
    },
    heavy: %{
      windup: 0.14,
      active: 0.12,
      recover: 0.32,
      damage: 4,
      reach: 1.8,
      knock: 15.0,
      next: nil
    },
    air: %{
      windup: 0.04,
      active: 0.22,
      recover: 0.08,
      damage: 2,
      reach: 1.3,
      knock: 8.0,
      next: nil
    }
  }

  @type move :: :jab | :cross | :kick | :low | :sweep | :heavy | :air
  @type data :: %{
          windup: number(),
          active: number(),
          recover: number(),
          damage: pos_integer(),
          reach: number(),
          knock: number(),
          next: move() | nil
        }

  @doc "The frame data of `move`."
  @spec data(move()) :: data()
  def data(move), do: Map.fetch!(@moves, move)

  @doc "Which part of `move` the beast is in, `t` seconds in (`Cauldron.Moves.part/2`)."
  @spec part(move(), number()) :: Cauldron.Moves.part()
  def part(move, t), do: Cauldron.Moves.part(data(move), t)
end
