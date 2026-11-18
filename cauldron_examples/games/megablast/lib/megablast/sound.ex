defmodule Megablast.Sound do
  @moduledoc """
  What the lane's events sound like, and its music.

  `voice/1` is the `sounds/0` table: the guns, kills and blasts, armour ringing, hits and
  lost ships, credits gathered, bombs, a boss's warning, the shop's clicks, and the menu.

  `pieces/0` is one piece, `"lane"`, of whole songs made with ACE-Step and kept in
  `priv/audio`, each played through and started again: `title`, the game's theme, behind
  the title and the summary; `stage_1` to `stage_5`, each its own song on that theme, while
  flying the stage; `boss` while a guardian or boss is fought; `shop` at the trader. A
  song missing from `priv/audio` leaves its section silent.
  """

  alias Cauldron.Audio.{Envelope, Recording, Voice}

  @kept {__MODULE__, :pieces}
  @songs [:title, :stage_1, :stage_2, :stage_3, :stage_4, :stage_5, :boss, :shop]

  @doc "The sound of an event, or `nil` for one that makes none."
  @spec voice(term()) :: Cauldron.Audio.sound()
  def voice(:fire), do: tone(:square, 1320.0, 0.03, 0.05, sweep: 0.6)

  def voice(:boom),
    do: [{0, noise(0.5, 0.18, 0.35)}, {10, tone(:square, 160.0, 0.15, 0.12, sweep: 0.5)}]

  def voice(:blast),
    do: [{0, noise(0.25, 0.6, 0.55)}, {20, tone(:saw, 90.0, 0.5, 0.2, sweep: 0.4)}]

  def voice(:beaten),
    do: [
      {0, noise(0.15, 1.8, 0.7)},
      {100, noise(0.3, 1.2, 0.5)},
      {300, tone(:saw, 60.0, 1.4, 0.3, sweep: 0.5)}
    ]

  def voice(:clang), do: tone(:triangle, 2200.0, 0.06, 0.12, sweep: 0.8)

  def voice(:hurt),
    do: [{0, noise(0.6, 0.15, 0.4)}, {0, tone(:square, 220.0, 0.25, 0.2, sweep: 0.5)}]

  def voice(:lost), do: [{0, noise(0.2, 1.0, 0.6)}, {40, tone(:saw, 300.0, 0.9, 0.3, sweep: 0.2)}]
  def voice(:pickup), do: tone(:sine, 1760.0, 0.08, 0.14, sweep: 1.3)
  def voice({:bomb, _by}), do: [{0, noise(0.1, 1.4, 0.8)}, {0, tone(:sine, 55.0, 1.2, 0.5)}]

  def voice({:warning, _name}),
    do: for(n <- 0..3, do: {n * 420, tone(:square, 440.0, 0.32, 0.18, sweep: 0.7)})

  def voice({:clear, _stage}), do: chime([523.3, 659.3, 784.0, 1046.5], 0.25)
  def voice({:stage, _number}), do: chime([392.0, 523.3, 784.0], 0.2)
  def voice(:won), do: chime([523.3, 659.3, 784.0, 1046.5, 1318.5, 1568.0], 0.28)
  def voice({:tick, _id}), do: tone(:square, 880.0, 0.03, 0.08)
  def voice({:bought, _id}), do: chime([784.0, 1174.7], 0.22)
  def voice({:refused, _id}), do: tone(:square, 140.0, 0.18, 0.16)

  def voice({:launch, _id}),
    do: [{0, noise(0.4, 0.6, 0.3)}, {0, tone(:saw, 110.0, 0.6, 0.18, sweep: 3.0)}]

  def voice({:out, _id}), do: tone(:saw, 220.0, 1.2, 0.35, sweep: 0.3)
  def voice(:menu_move), do: tone(:square, 980.0, 0.03, 0.08)
  def voice(:menu_choose), do: chime([660.0, 1320.0], 0.18)
  def voice(:menu_back), do: tone(:square, 490.0, 0.05, 0.1)
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
    |> Enum.map(fn {freq, index} -> {index * 70, tone(:sine, freq, 0.2, gain)} end)
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

  @doc """
  The cue for the title and summary (`:title`), a guardian or boss fight (`:boss`), the
  shop (`:shop`), or flying stage `number`; `nil` when its song is missing.
  """
  @spec cue(:title | :boss | :shop | pos_integer()) :: Cauldron.Audio.Music.cue() | nil
  def cue(number) when is_integer(number), do: song(:"stage_#{number}")
  def cue(section) when section in [:title, :boss, :shop], do: song(section)

  defp song(section) do
    case pieces() do
      [{"lane", %{sections: %{^section => _song}}}] ->
        %{piece: "lane", section: section, layers: %{track: 1.0}}

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
        {"lane",
         %{
           bpm: 125,
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
    do: Recording.read(Path.join([:code.priv_dir(:megablast), "audio", "#{name}.wav"]))
end
