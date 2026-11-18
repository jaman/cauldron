defmodule Cauldron3D.Formats.Gltf.Mixer do
  @moduledoc """
  What a figure is playing: a mix of clips, how far through it is, and a fade from what
  it played before.

      clips = %{idle: idle, walk: walk, run: run, jump: jump}
      mixer = Cauldron3D.Formats.Gltf.Mixer.new()
      mixer = Cauldron3D.Formats.Gltf.Mixer.play(mixer, [walk: 0.3, run: 0.7], loop: true, fade: 0.25)
      mixer = Cauldron3D.Formats.Gltf.Mixer.advance(mixer, clips, 1 / 60, 1.1)
      sample = Cauldron3D.Formats.Gltf.Mixer.sample(mixer, clips)

  A mix is a list of `{name, weight}`, the names being keys of the clips map given to
  `advance/4` and `sample/2`. `play/3` with the names and `:loop` already playing only
  changes the weights; with others it starts the new mix and fades to it over `:fade`
  seconds (default 0.2) while the old one keeps moving.

  A looping mix is kept as a share of its stride, so clips of different lengths stay in
  step: each is read at the same share of its own length, and the stride lasts the
  weighted mean of their lengths. A mix that does not loop is kept in seconds and stops
  at the end of its longest clip; `done?/2` says when.

  `advance/4`'s `rate` scales how fast the mix plays, for matching feet to ground speed.
  """

  alias Cauldron3D.Formats.Gltf.Clip

  @type mix :: [{term(), number()}]
  @type playing :: %{mix: mix(), loop: boolean(), at: float()}
  @type t :: %__MODULE__{now: playing() | nil, before: playing() | nil, fade: float(), faded: float()}

  defstruct now: nil, before: nil, fade: 0.0, faded: 0.0

  @doc "A mixer playing nothing."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Plays `mix`. Options: `:loop` (default `false`), `:fade` seconds (default 0.2), `:at` where to start."
  @spec play(t(), mix(), keyword()) :: t()
  def play(%__MODULE__{now: now} = mixer, mix, opts \\ []) do
    loop = Keyword.get(opts, :loop, false)

    if same?(now, mix, loop) do
      %{mixer | now: %{now | mix: mix}}
    else
      start = Keyword.get(opts, :at, carried(now, loop))
      %{mixer | now: %{mix: mix, loop: loop, at: start / 1}, before: now, fade: Keyword.get(opts, :fade, 0.2) / 1, faded: 0.0}
    end
  end

  @doc "The mixer `seconds` later, playing `rate` times as fast."
  @spec advance(t(), %{term() => map()}, number(), number()) :: t()
  def advance(%__MODULE__{} = mixer, clips, seconds, rate \\ 1.0) do
    faded = mixer.faded + seconds
    before = if faded >= mixer.fade, do: nil, else: moved(mixer.before, clips, seconds * rate)
    %{mixer | now: moved(mixer.now, clips, seconds * rate), before: before, faded: faded}
  end

  @doc "What the mixer sets now (`Cauldron3D.Formats.Gltf.Clip`'s sample)."
  @spec sample(t(), %{term() => map()}) :: Clip.sample()
  def sample(%__MODULE__{now: nil}, _clips), do: Clip.empty()
  def sample(%__MODULE__{now: now, before: nil}, clips), do: read(now, clips)

  def sample(%__MODULE__{now: now, before: before, fade: fade, faded: faded}, clips) do
    share = if fade > 0.0, do: min(faded / fade, 1.0), else: 1.0
    Clip.blend(read(before, clips), read(now, clips), share * share * (3.0 - 2.0 * share))
  end

  @doc "Whether a mix that does not loop has reached its end. A looping mix never has."
  @spec done?(t(), %{term() => map()}) :: boolean()
  def done?(%__MODULE__{now: %{loop: false, at: at} = now}, clips), do: at >= longest(now, clips)
  def done?(%__MODULE__{}, _clips), do: false

  @doc "How far through its mix the mixer is: a share of the stride for a loop, seconds otherwise."
  @spec at(t()) :: float()
  def at(%__MODULE__{now: nil}), do: 0.0
  def at(%__MODULE__{now: %{at: at}}), do: at

  defp same?(nil, _mix, _loop), do: false
  defp same?(%{mix: playing, loop: loop}, mix, loop), do: Keyword.keys(playing) == Keyword.keys(mix)
  defp same?(_now, _mix, _loop), do: false

  defp carried(%{loop: true, at: at}, true), do: at
  defp carried(_now, _loop), do: 0.0

  defp moved(nil, _clips, _seconds), do: nil

  defp moved(%{loop: true, at: at} = playing, clips, seconds) do
    stride = stride(playing, clips)
    share = if stride > 0.0, do: at + seconds / stride, else: at
    %{playing | at: share - Float.floor(share)}
  end

  defp moved(%{at: at} = playing, clips, seconds),
    do: %{playing | at: min(at + seconds, longest(playing, clips))}

  defp stride(%{mix: mix}, clips) do
    {length, weight} =
      Enum.reduce(mix, {0.0, 0.0}, fn {name, weight}, {length, total} ->
        {length + Map.fetch!(clips, name).duration * weight, total + weight}
      end)

    if weight > 0.0, do: length / weight, else: 0.0
  end

  defp longest(%{mix: mix}, clips),
    do: mix |> Enum.map(fn {name, _weight} -> Map.fetch!(clips, name).duration end) |> Enum.max(fn -> 0.0 end)

  defp read(%{mix: mix, loop: loop, at: at}, clips) do
    {sample, _weight} =
      Enum.reduce(mix, {Clip.empty(), 0.0}, fn
        {_name, weight}, mixed when weight <= 0 ->
          mixed

        {name, weight}, {sample, total} ->
          clip = Map.fetch!(clips, name)
          time = if loop, do: at * clip.duration, else: at
          {Clip.blend(sample, Clip.sample(clip, time), weight / (total + weight)), total + weight}
      end)

    sample
  end
end
