defmodule Cauldron.SFX.Audio do
  @moduledoc """
  A sound as a WAV, for a front end that plays it somewhere other than a
  `TuningFork.Stage` — a browser, a notebook.

      Cauldron.SFX.Audio.wav(Cauldron.SFX.voice(bank, "fire"))

  A layered sound is rendered part by part, each placed at its own offset and mixed, then
  put in the middle of the stereo field.
  """

  alias Cauldron.Audio.Rendered
  alias TuningFork.{Mixer, Wav}

  @rate 44_100

  @doc "The sound as a 44.1 kHz stereo WAV."
  @spec wav(Cauldron.Audio.sound()) :: binary()
  def wav(sound) do
    sound
    |> parts()
    |> Enum.map(fn {at, voice} -> {at, Rendered.fetch(voice, @rate)} end)
    |> mix()
    |> Mixer.centre()
    |> Wav.encode(rate: @rate, channels: 2)
  end

  defp parts(%{} = voice), do: [{0, voice}]
  defp parts(parts) when is_list(parts), do: parts

  defp mix([]), do: Mixer.silence(1, 1)

  defp mix(parts) do
    frames =
      parts
      |> Enum.map(fn {at, pcm} -> div(at * @rate, 1000) + div(byte_size(pcm), 2) end)
      |> Enum.max(fn -> 1 end)

    Enum.reduce(parts, Mixer.silence(frames, 1), fn {at, pcm}, base ->
      {mixed, _over} = Mixer.mix_at(base, pcm, div(at * @rate, 1000), 1)
      mixed
    end)
  end
end
