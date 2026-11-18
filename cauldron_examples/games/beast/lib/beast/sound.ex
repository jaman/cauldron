defmodule Beast.Sound do
  @moduledoc """
  What the journey's events sound like, and its music.

  `voice/1` is the `sounds/0` table: blows landing and killing, armour ringing, wounds
  and falls, arrows loosed and spells cast, a boss waking, left open to blows and falling,
  fruit eaten, the key, a standing stone, a new region, and the menu.

  `pieces/0` is one piece, `"journey"`, of whole songs made with ACE-Step and kept in
  `priv/audio` as MP3 (decoded in C by `Cauldron.Audio.Decoder`), each played through and started again: `title`, the game's theme, behind
  the title and the summary; `plain`, `caverns`, `tree` and `castle`, each region's own
  song on that theme; `boss` while a boss is fought. A song missing from `priv/audio`
  leaves its section silent.
  """

  alias Cauldron.Audio.{Decoder, Envelope, Voice}

  @kept {__MODULE__, :pieces}
  @songs [:title, :plain, :caverns, :tree, :castle, :boss]

  @doc "The sound of an event, or `nil` for one that makes none."
  @spec voice(term()) :: Cauldron.Audio.sound()
  def voice(:thud),
    do: [{0, noise(0.35, 0.12, 0.45)}, {0, tone(:sine, 90.0, 0.15, 0.35, sweep: 0.5)}]

  def voice(:kill), do: [{0, noise(0.3, 0.3, 0.5)}, {20, tone(:saw, 140.0, 0.3, 0.2, sweep: 0.4)}]
  def voice(:clang), do: tone(:triangle, 1600.0, 0.1, 0.14, sweep: 0.8)

  def voice(:felled),
    do: [{0, noise(0.15, 1.6, 0.7)}, {200, tone(:saw, 55.0, 1.4, 0.35, sweep: 0.5)}]

  def voice(:wounded),
    do: [{0, noise(0.6, 0.15, 0.4)}, {0, tone(:square, 200.0, 0.25, 0.2, sweep: 0.6)}]

  def voice({:fallen, _id}), do: tone(:saw, 180.0, 1.2, 0.35, sweep: 0.3)
  def voice({:fall, _id}), do: tone(:sine, 600.0, 0.8, 0.3, sweep: 0.2)
  def voice(:loose), do: noise(0.7, 0.1, 0.18)
  def voice(:cast), do: tone(:sine, 440.0, 0.4, 0.18, sweep: 2.0)

  def voice({:awaken, _kind}),
    do: [{0, noise(0.08, 2.0, 0.6)}, {0, tone(:saw, 45.0, 1.8, 0.4, sweep: 1.5)}]

  def voice({:beaten, _kind}), do: chime([392.0, 523.3, 659.3, 784.0], 0.3)
  def voice({:opening, _at}), do: chime([880.0, 1174.7], 0.2)
  def voice(:eat), do: chime([659.3, 880.0], 0.22)
  def voice(:key), do: chime([784.0, 1046.5, 1318.5], 0.24)
  def voice(:stone), do: chime([330.0, 494.0], 0.2)
  def voice({:region, _n}), do: chime([262.0, 392.0, 523.3], 0.24)
  def voice({:revive, _id}), do: chime([262.0, 330.0], 0.18)
  def voice(:won), do: chime([523.3, 659.3, 784.0, 1046.5, 1318.5], 0.3)
  def voice(:menu_move), do: tone(:square, 700.0, 0.03, 0.08)
  def voice(:menu_choose), do: chime([440.0, 880.0], 0.18)
  def voice(:menu_back), do: tone(:square, 350.0, 0.05, 0.1)
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

  defp chime(freqs, gain),
    do:
      freqs
      |> Enum.with_index()
      |> Enum.map(fn {f, i} -> {i * 80, tone(:sine, f, 0.25, gain)} end)

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

  @doc """
  The cue for the title and summary (`:title`), region `id` (`:plain`, `:caverns`,
  `:tree`, `:castle`) or a boss fight (`:boss`); `nil` when its song is missing.
  """
  @spec cue(atom()) :: Cauldron.Audio.Music.cue() | nil
  def cue(section) when section in @songs do
    case pieces() do
      [{"journey", %{sections: %{^section => _song}}}] ->
        %{piece: "journey", section: section, layers: %{track: 1.0}}

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
        {"journey",
         %{
           bpm: 80,
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

  defp recording(name) do
    with {:ok, mp3} <- File.read(Path.join([:code.priv_dir(:beast), "audio", "#{name}.mp3"])),
         {:ok, pcm, rate, channels} <- Decoder.decode(mp3),
         do: {:ok, %{pcm: pcm, rate: rate, channels: channels}}
  end
end
