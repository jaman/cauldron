defmodule CisternComplete.Sound do
  @moduledoc """
  What the game's events sound like, and its music.

  `voice/1` is the `sounds/0` table: rain let go, a catch, a pour's glug, a spill, a jar
  cracking, hail bouncing, the hum of a flickering column and its thunder, a sulk's burst,
  a mended jar, a new storm, a keeper out, and the menu's own clicks.

  `pieces/0` is one piece, `"storm"`, of three whole songs made with ACE-Step and kept
  in `priv/audio`, each played through and started again: `title`, the game's theme,
  behind the title and the summary; `calm`, a ballad on that theme, for the first two
  storms; `busy`, a tarantella on it, after. A song missing from `priv/audio` leaves its
  section silent.
  """

  alias Cauldron.Audio.{Envelope, Recording, Voice}

  @kept {__MODULE__, :pieces}
  @songs [:title, :calm, :busy]

  @doc "The sound of an event, or `nil` for one that makes none."
  @spec voice(term()) :: Cauldron.Audio.sound()
  def voice(:rain), do: tone(:sine, 1760.0, 0.04, 0.05, sweep: 0.5)
  def voice(:hail), do: tone(:triangle, 2400.0, 0.03, 0.05)
  def voice(:catch), do: chime([659.3, 987.8], 0.24)

  def voice(:pouring),
    do: [{0, noise(0.35, 0.25, 0.45)}, {90, tone(:sine, 220.0, 0.25, 0.25, sweep: 0.7)}]

  def voice(:pour), do: chime([523.3, 659.3, 784.0], 0.3)

  def voice(:spill),
    do: [{0, noise(0.5, 0.2, 0.3)}, {30, tone(:square, 300.0, 0.25, 0.14, sweep: 0.5)}]

  def voice(:miss),
    do: [{0, noise(0.5, 0.18, 0.4)}, {20, tone(:square, 180.0, 0.3, 0.18, sweep: 0.4)}]

  def voice(:crack),
    do: [{0, noise(0.9, 0.12, 0.5)}, {10, tone(:square, 140.0, 0.25, 0.2, sweep: 0.3)}]

  def voice(:bounce), do: tone(:triangle, 1900.0, 0.06, 0.12, sweep: 1.4)
  def voice(:flicker), do: tone(:saw, 110.0, 0.9, 0.08)
  def voice(:thunder), do: noise(0.06, 1.8, 0.7)
  def voice(:burst), do: [{0, noise(0.2, 0.5, 0.35)} | chime([392.0, 330.0], 0.1)]
  def voice(:mend), do: chime([523.3, 659.3, 784.0, 1046.5], 0.28)
  def voice({:storm, _level}), do: noise(0.08, 1.6, 0.5)
  def voice({:out, _id}), do: tone(:saw, 220.0, 0.8, 0.4, sweep: 0.5)
  def voice({:gust, _from}), do: noise(0.3, 0.9, 0.3)
  def voice(:menu_move), do: tone(:square, 880.0, 0.04, 0.08)
  def voice(:menu_choose), do: chime([660.0, 990.0], 0.18)
  def voice(:menu_back), do: tone(:square, 440.0, 0.06, 0.1)
  def voice(_event), do: nil

  defp tone(shape, freq, seconds, gain, opts \\ []),
    do:
      Voice.new(
        Keyword.merge(
          [shape: shape, freq: freq, envelope: Envelope.hit(seconds), gain: gain],
          opts
        )
      )

  defp noise(cutoff, seconds, gain),
    do: Voice.new(shape: :noise, cutoff: cutoff, envelope: Envelope.hit(seconds), gain: gain)

  defp chime(freqs, gain) do
    freqs
    |> Enum.with_index()
    |> Enum.map(fn {freq, index} -> {index * 60, tone(:sine, freq, 0.18, gain)} end)
  end

  @doc "The music, as `Cauldron.Client.Game.music/0` gives it; read once and kept."
  @spec pieces() :: [{String.t(), Cauldron.Audio.Music.spec()}]
  def pieces do
    case :persistent_term.get(@kept, nil) do
      nil ->
        pieces = read()
        :persistent_term.put(@kept, pieces)
        pieces

      pieces ->
        pieces
    end
  end

  @doc "The cue for the title and summary (`:title`) or for storm `level`; `nil` when its song is missing."
  @spec cue(:title | pos_integer()) :: Cauldron.Audio.Music.cue() | nil
  def cue(:title), do: song(:title)
  def cue(level) when level > 2, do: song(:busy)
  def cue(_level), do: song(:calm)

  defp song(section) do
    case pieces() do
      [{"storm", %{sections: %{^section => _song}}}] ->
        %{piece: "storm", section: section, layers: %{track: 1.0}}

      _missing ->
        nil
    end
  end

  defp read do
    sections =
      for name <- @songs,
          {:ok, song} <- [recording(name)],
          into: %{},
          do: {name, %{track: {:pcm, song.pcm, song.rate, song.channels}}}

    if sections == %{},
      do: [],
      else: [
        {"storm",
         %{
           bpm: 120,
           beats_per_bar: 4,
           layers: [:track],
           sections: sections,
           render: :on_cue,
           fingerprint:
             Enum.map_join(sections, "-", fn {name, %{track: {:pcm, pcm, rate, channels}}} ->
               "#{name}#{byte_size(pcm)}x#{rate}x#{channels}"
             end)
         }}
      ]
  end

  defp recording(name),
    do: Recording.read(Path.join([:code.priv_dir(:cistern_complete), "audio", "#{name}.wav"]))
end
