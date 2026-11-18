defmodule Greenware.Sound do
  @moduledoc """
  The game's sounds: dry clay, a wire, water, a kiln, a plate, a page. The final score
  and foley arrive with the asset pass; these are the placeholder voices the game is
  played with.
  """

  alias Cauldron.Audio.{Envelope, Voice}

  def voice(:ui_move), do: tone(:triangle, 380.0, 0.035, 0.06)
  def voice(:ui_choose), do: chime([523.3, 659.3], 0.12)
  def voice(:ui_back), do: tone(:triangle, 220.0, 0.06, 0.06)
  def voice(:ui_refuse), do: tone(:square, 150.0, 0.09, 0.05)
  def voice(:page), do: noise(0.5, 0.16, 0.08)
  def voice(:clay), do: noise(0.18, 0.12, 0.09)
  def voice(:wire), do: tone(:triangle, 1200.0, 0.05, 0.045, sweep: 0.7)
  def voice(:water), do: tone(:sine, 420.0, 0.2, 0.06, sweep: 1.8)
  def voice(:heat), do: noise(0.08, 0.3, 0.06)
  def voice(:test), do: tone(:sine, 660.0, 0.12, 0.07)
  def voice(:fail), do: [{0, tone(:square, 180.0, 0.2, 0.08, sweep: 0.7)}]
  def voice(:mend), do: chime([523.3, 659.3, 784.0, 1046.5], 0.16)

  defp tone(shape, freq, seconds, gain, opts \\ []) do
    Voice.new(
      Keyword.merge([shape: shape, freq: freq, envelope: Envelope.hit(seconds), gain: gain], opts)
    )
  end

  defp noise(cutoff, seconds, gain) do
    Voice.new(shape: :noise, cutoff: cutoff, envelope: Envelope.hit(seconds), gain: gain)
  end

  defp chime(freqs, gain) do
    freqs
    |> Enum.with_index()
    |> Enum.map(fn {freq, index} -> {index * 55, tone(:sine, freq, 0.22, gain)} end)
  end

  @kept {__MODULE__, :pieces}

  @doc "The music: the title theme and the epilogue, read once."
  def pieces do
    case :persistent_term.get(@kept, nil) do
      nil ->
        pieces =
          case {recording("title"), recording("ending")} do
            {{:ok, title}, {:ok, ending}} ->
              [
                {"greenware",
                 %{
                   bpm: 92,
                   beats_per_bar: 5,
                   layers: [:track],
                   sections: %{
                     title: %{track: {:pcm, title.pcm, title.rate, title.channels}},
                     ending: %{track: {:pcm, ending.pcm, ending.rate, ending.channels}}
                   },
                   render: :on_cue,
                   fingerprint: "#{byte_size(title.pcm)}x#{byte_size(ending.pcm)}x#{title.rate}"
                 }}
              ]

            _ ->
              []
          end

        :persistent_term.put(@kept, pieces)
        pieces

      pieces ->
        pieces
    end
  end

  def cue(_view, :summary), do: song(:ending)
  def cue(_view, :ending), do: song(:ending)
  def cue(_view, :title), do: song(:title)
  def cue(_view, :play), do: song(:title)
  def cue(_view, _screen), do: nil

  defp song(section) do
    case pieces() do
      [{"greenware", %{sections: sections}}] ->
        if Map.has_key?(sections, section),
          do: %{piece: "greenware", section: section, layers: %{track: 1.0}}

      _ ->
        nil
    end
  end

  defp recording(name) do
    case :code.priv_dir(:greenware) do
      dir when is_list(dir) ->
        Cauldron.Audio.Recording.read(Path.join([dir, "audio", name <> ".wav"]))

      _ ->
        {:error, :enoent}
    end
  end
end
