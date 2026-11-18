defmodule Cauldron.Audio.Envelope do
  @moduledoc """
  How a voice's level rises and falls over time.

  An attack-decay-sustain-release shape in seconds, sampled by time.

      Cauldron.Audio.Envelope.new(attack: 0.01, decay: 0.2, sustain: 0.4, release: 0.3)
  """

  @type t() :: TuningFork.Envelope.t()

  @doc """
  How long the envelope sounds, in seconds: attack, decay, hold and release together, or
  attack and decay alone when `sustain` is 0.0, since nothing is left to hold or release.
  A `gated/2` envelope lasts until its gate and then its release, or attack and decay alone
  when it has no sustain and has died away before the gate.

      iex> Cauldron.Audio.Envelope.duration(Cauldron.Audio.Envelope.new(attack: 0.1, decay: 0.2, sustain: 0.5, hold: 1.0, release: 0.3))
      1.6
      iex> Cauldron.Audio.Envelope.duration(Cauldron.Audio.Envelope.new(attack: 0.1, decay: 0.4, sustain: 0.0, hold: 1.0, release: 0.3))
      0.5
  """
  @spec duration(t()) :: float()
  def duration(env), do: TuningFork.Envelope.duration(env)

  @doc """
  The envelope played as a key held for `seconds` and then let go: attack, decay and
  sustain run at their own speeds for as long as the key is held, and the release starts
  from whatever level has been reached when it is let go — part-way through the attack or
  decay for a short note. A note with no sustain that has died away before it is let go
  ends there. Any hold is dropped.

      iex> Cauldron.Audio.Envelope.new(attack: 0.1, decay: 0.2, sustain: 0.5, release: 0.3) |> Cauldron.Audio.Envelope.gated(2.0) |> Cauldron.Audio.Envelope.duration()
      2.3
      iex> Cauldron.Audio.Envelope.new(attack: 0.1, decay: 0.2, sustain: 0.5, release: 0.3) |> Cauldron.Audio.Envelope.gated(2.0) |> Cauldron.Audio.Envelope.level(1.5)
      0.5
      iex> Cauldron.Audio.Envelope.new(attack: 0.1, decay: 1.0, sustain: 0.0, release: 0.3) |> Cauldron.Audio.Envelope.gated(4.0) |> Cauldron.Audio.Envelope.duration()
      1.1
  """
  @spec gated(t(), number()) :: t()
  def gated(env, seconds), do: TuningFork.Envelope.gated(env, seconds)

  @doc """
  A percussive envelope: a 2 ms attack, `decay` seconds of fall, and no sustain or release.
  """
  @spec hit(float()) :: t()
  def hit(decay), do: TuningFork.Envelope.hit(decay)

  @doc """
  The level at `t` seconds, from 0.0 to 1.0.

  0.0 before the envelope starts and after it ends.
  """
  @spec level(t(), float()) :: float()
  def level(env, t), do: TuningFork.Envelope.level(env, t)

  @doc """
  An envelope, with anything unset left at its default.

  ## Options

    * `:attack` — seconds from silence to full level, default 0.005
    * `:decay` — seconds from full level down to `:sustain`, default 0.05
    * `:sustain` — the level held after the decay, 0.0 to 1.0, default 0.0
    * `:hold` — seconds spent at `:sustain`, default 0.0
    * `:release` — seconds from `:sustain` back to silence, default 0.02
    * `:curve` — the exponent the decay falls by, default 2.0; 1.0 is a straight line
    * `:gate` — seconds after which the note is let go, default `nil`. See `gated/2`
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []), do: TuningFork.Envelope.new(opts)

  @doc """
  The envelope with its decay set so the whole of it lasts `seconds`: the decay is `seconds`
  less the attack and, when there is a sustain level to release from, the release; any hold
  is dropped. The decay is never under 10 ms.

      iex> Cauldron.Audio.Envelope.spanning(Cauldron.Audio.Envelope.new(attack: 0.1, sustain: 0.5, release: 0.2), 1.0).decay
      0.7
      iex> Cauldron.Audio.Envelope.spanning(Cauldron.Audio.Envelope.new(attack: 0.1, sustain: 0.0, release: 0.2), 1.0).decay
      0.9
      iex> Cauldron.Audio.Envelope.spanning(Cauldron.Audio.Envelope.new(attack: 0.1, sustain: 1.0, hold: 2.0, release: 0.2), 1.0) |> Cauldron.Audio.Envelope.duration()
      1.0
  """
  @spec spanning(t(), number()) :: t()
  def spanning(env, seconds), do: TuningFork.Envelope.spanning(env, seconds)
end
