defmodule Cistern.Sound do
  @moduledoc """
  What the game's events sound like, and the tune the square plays.

  `voice/1` is the `Cauldron.Client.Game.sounds/0` table: a `Cauldron.Audio.Voice` for a
  drop let go, a catch, a jar breaking, a jar mended, a new storm's thunder, a keeper
  going out. `pieces/0` is one `Cauldron.Audio.Music` piece, `"rain"`, with a `calm`
  section for the first storms and a `busy` one after.
  """

  import Cauldron.Audio.Part

  alias Cauldron.Audio.{Envelope, Score, Voice}

  @doc "The sound of an event, or `nil` for one that makes none."
  @spec voice(term()) :: Cauldron.Audio.sound()
  def voice(:drop),
    do:
      Voice.new(shape: :sine, freq: 1760.0, sweep: 0.5, envelope: Envelope.hit(0.05), gain: 0.06)

  def voice(:catch), do: chime([659.3, 987.8])
  def voice(:mend), do: chime([523.3, 659.3, 784.0, 1046.5])

  def voice(:miss),
    do: [
      {0, Voice.new(shape: :noise, cutoff: 0.5, envelope: Envelope.hit(0.18), gain: 0.4)},
      {20,
       Voice.new(shape: :square, freq: 180.0, sweep: 0.4, envelope: Envelope.hit(0.3), gain: 0.18)}
    ]

  def voice({:storm, _level}),
    do: Voice.new(shape: :noise, cutoff: 0.08, envelope: Envelope.hit(1.6), gain: 0.5)

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

  @doc "The square's music, as `Cauldron.Client.Game.music/0` gives it."
  @spec pieces() :: [{String.t(), Cauldron.Audio.Music.spec()}]
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
         fingerprint: "2"
       }}
    ]
  end

  @doc "The cue for storm `level`."
  @spec cue(pos_integer()) :: Cauldron.Audio.Music.cue()
  def cue(level),
    do: %{
      piece: "rain",
      section: if(level > 2, do: :busy, else: :calm),
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
    |> then(&Score.from_parts([&1], beats: 16))
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
    |> then(&Score.from_parts([&1], beats: 16))
  end
end
