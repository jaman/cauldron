defmodule Cistern.Sound do
  @moduledoc """
  What the game's events sound like, and the tune the field plays.

  `voice/1` is the `Cauldron2D.Client.Game.sounds/0` table: a `TuningFork.Voice` for a
  catch, a splash, a player going out. `pieces/0` is one `Cauldron2D.Audio.Music` piece,
  `"rain"`, with a `calm` section and a `busy` one for when the drops come thick.
  """

  import TuningFork.Part

  alias TuningFork.{Envelope, Voice}

  @doc "The sound of an event, or `nil` for one that makes none."
  @spec voice(term()) :: Cauldron2D.Audio.sound()
  def voice({:catch, :drop_gold}), do: chime([880.0, 1318.5, 1760.0])
  def voice({:catch, _kind}), do: chime([659.3, 987.8])

  def voice(:splash),
    do: Voice.new(shape: :noise, cutoff: 0.3, envelope: Envelope.hit(0.25), gain: 0.35)

  def voice({:out, _id}),
    do: Voice.new(shape: :saw, freq: 220.0, sweep: 0.5, envelope: Envelope.hit(0.8), gain: 0.4)

  def voice(_event), do: nil

  defp chime(freqs) do
    freqs
    |> Enum.with_index()
    |> Enum.map(fn {freq, index} ->
      {index * 60, Voice.new(shape: :sine, freq: freq, envelope: Envelope.hit(0.18), gain: 0.3)}
    end)
  end

  @doc "The field's music, as `Cauldron2D.Client.Game.music/0` gives it."
  @spec pieces() :: [{String.t(), Cauldron2D.Audio.Music.spec()}]
  def pieces do
    [
      {"rain",
       %{
         bpm: 96,
         beats_per_bar: 4,
         layers: [:bass, :bells],
         sections: %{
           calm: %{bass: bass(96), bells: bells(96, 0.35)},
           busy: %{bass: bass(96), bells: bells(96, 0.8)}
         },
         fingerprint: "1"
       }}
    ]
  end

  @doc "The cue for a field with `drops` in the air."
  @spec cue(non_neg_integer()) :: Cauldron2D.Audio.Music.cue()
  def cue(drops),
    do: %{
      piece: "rain",
      section: if(drops > 3, do: :busy, else: :calm),
      layers: %{bass: 1.0, bells: 1.0}
    }

  defp bass(bpm) do
    part(
      bpm: bpm,
      synth:
        Voice.new(
          shape: :triangle,
          envelope: Envelope.new(attack: 0.02, decay: 0.6, sustain: 0.2, release: 0.3),
          gain: 0.3
        )
    )
    |> repeat(4, fn line ->
      line |> play(:a2, 1.5) |> play(:e3, 0.5) |> play(:c3, 1.0) |> play(:g2, 1.0)
    end)
    |> then(&TuningFork.Score.from_parts([&1], beats: 16))
  end

  defp bells(bpm, gain) do
    part(
      bpm: bpm,
      synth:
        Voice.new(
          shape: :sine,
          envelope: Envelope.new(attack: 0.005, decay: 0.7, sustain: 0.0, release: 0.2),
          gain: 0.12 * gain
        )
    )
    |> repeat(4, fn line ->
      line
      |> rest(0.5)
      |> play(:e5, 0.5)
      |> play(:a5, 1.0)
      |> rest(0.5)
      |> play(:c6, 0.5)
      |> play(:b5, 1.0)
    end)
    |> then(&TuningFork.Score.from_parts([&1], beats: 16))
  end
end
