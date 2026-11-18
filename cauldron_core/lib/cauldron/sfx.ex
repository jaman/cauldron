defmodule Cauldron.SFX do
  @moduledoc """
  A game's sound effects as data: each event, and the sounds it makes.

  A bank is plain JSON — `sfx.json` — so it can be read, diffed, edited and kept in a game's
  `priv/` without this library. A game hands it to `Cauldron.Audio` as its sounds:

      bank = Cauldron.SFX.read!("priv/sfx/sfx.json")
      Cauldron.Audio.start(sounds: Cauldron.SFX.sounds(bank))

      Cauldron.Audio.play([:fire])

  An event may have several variants, and one is picked each time it plays, so a repeated
  event does not sound repeated. A variant is a recipe — a tone, a noise, or layers of them
  — turned into a `Cauldron.Audio.Voice` when it plays.

  ## The file

      {
        "format": 1,
        "rate": 44100,
        "channels": 2,
        "events": {
          "fire": {
            "gain": 1.0,
            "pan": 0.0,
            "priority": 1,
            "variants": [
              {"kind": "tone", "shape": "square", "freq": 1320.0, "decay": 0.05,
               "sweep": 0.6, "gain": 0.8, "cutoff": 0.6, "pan": 0.0}
            ]
          },
          "boom": {
            "gain": 1.0,
            "pan": 0.0,
            "priority": 2,
            "variants": [
              {"kind": "layers", "parts": [
                {"at_ms": 0, "recipe": {"kind": "noise", "decay": 0.5, "gain": 0.5,
                                        "cutoff": 0.7, "pan": 0.0}},
                {"at_ms": 10, "recipe": {"kind": "tone", "shape": "saw", "freq": 80.0,
                                         "decay": 0.4, "sweep": 0.5, "gain": 0.6,
                                         "cutoff": null, "pan": 0.0}}
              ]}
            ]
          }
        }
      }

  A tone's `shape` is `sine`, `square`, `saw` or `triangle`; `decay` is how long it falls
  away, in seconds; `sweep` is the pitch it reaches by the end, as a multiple of `freq`.
  `cutoff` and `highpass` are one-pole filters. `fm`, `fmh` and `fmattack` add frequency
  modulation — metal, bells, zaps — and `detune` is cents between two copies of the voice,
  which widens it. `attack`, `sustain`, `hold` and `release` are the rest of the envelope:
  a release needs a sustain level, and a recipe that asks for one and leaves the sustain at
  zero gets a small one.

  A noise has no `freq`, `shape`, `sweep` or `fm`. Layers are played `at_ms` after the event,
  each from its own recipe. A sample plays a recording instead of a tone: `sound` names one
  of `TuningFork.Kit`'s (`"bd"`, `"sd"`, `"hh"`, …), `file` is a path.

  An event's `space` is how much of a cheap room it is given: the sound again a little later,
  quieter and on the other side, three times. It is early reflections, not a reverb.

  `rate` and `channels` are what a bake would render at; playback uses the stage's own.
  """

  alias Cauldron.Audio.{Envelope, Voice}
  alias TuningFork.{Kit, Sample}

  @format 1
  @rate 44_100
  @channels 2
  @shapes ~w(sine square saw triangle)

  @typedoc "A tone, a noise, or layers of recipes."
  @type recipe :: %{required(String.t()) => term()}

  @type event :: %{
          gain: float(),
          pan: float(),
          space: float(),
          priority: integer(),
          variants: [recipe()]
        }

  @type t :: %__MODULE__{
          format: pos_integer(),
          rate: pos_integer(),
          channels: 1 | 2,
          events: %{String.t() => event()}
        }

  defstruct format: @format, rate: @rate, channels: @channels, events: %{}

  @doc """
  A bank, with anything unset left at its default.

      Cauldron.SFX.new(events: %{"click" => %{variants: [%{kind: "tone", freq: 880.0}]}})
  """
  @spec new(keyword() | map()) :: t()
  def new(opts \\ []) do
    opts |> Map.new() |> Map.new(fn {key, value} -> {to_string(key), value} end) |> from_map()
  end

  @doc """
  A bank to start from: a shot, an explosion, a pickup, a hurt, a jump and a click.

  Each has a few variants, and the explosion and hurt are layered, so an editor opened on it
  has something to play with.
  """
  @spec starter() :: t()
  def starter do
    new(
      events: %{
        "fire" =>
          starter_event([
            tone(:square, 1320.0, 0.05, 0.8, sweep: 0.6),
            tone(:square, 1180.0, 0.05, 0.8, sweep: 0.55),
            tone(:square, 1480.0, 0.04, 0.75, sweep: 0.65)
          ]),
        "boom" =>
          starter_event(
            [
              layers([
                {0, noise(0.5, 0.5, cutoff: 0.7)},
                {10, tone(:saw, 80.0, 0.4, 0.6, sweep: 0.5)}
              ])
            ],
            priority: 2
          ),
        "pickup" =>
          starter_event([
            tone(:sine, 1760.0, 0.07, 0.6, sweep: 1.2),
            tone(:sine, 1980.0, 0.07, 0.6, sweep: 1.15)
          ]),
        "hurt" =>
          starter_event(
            [
              layers([
                {0, noise(0.15, 0.4)},
                {0, tone(:square, 220.0, 0.25, 0.5, sweep: 0.5)}
              ])
            ],
            priority: 2
          ),
        "jump" =>
          starter_event([
            tone(:square, 330.0, 0.12, 0.5, sweep: 2.0),
            tone(:square, 300.0, 0.12, 0.5, sweep: 2.2)
          ]),
        "click" => starter_event([tone(:sine, 880.0, 0.03, 0.45)])
      }
    )
  end

  @doc "The event names of the bank, in order."
  @spec events(t()) :: [String.t()]
  def events(%__MODULE__{events: events}), do: events |> Map.keys() |> Enum.sort()

  @doc "The event called `name`, or `nil`."
  @spec event(t(), term()) :: event() | nil
  def event(%__MODULE__{events: events}, name), do: Map.get(events, to_string(name))

  @doc "Replace or add the event called `name`."
  @spec put_event(t(), String.t(), event() | map()) :: t()
  def put_event(%__MODULE__{} = bank, name, event) do
    %{bank | events: Map.put(bank.events, to_string(name), normalise_event(event))}
  end

  @doc "Change the event called `name` with `fun`, or the bank unchanged when there is none."
  @spec update_event(t(), String.t(), (event() -> event())) :: t()
  def update_event(%__MODULE__{} = bank, name, fun) do
    case Map.fetch(bank.events, to_string(name)) do
      {:ok, event} ->
        %{bank | events: Map.put(bank.events, to_string(name), normalise_event(fun.(event)))}

      :error ->
        bank
    end
  end

  @doc "Remove the event called `name`."
  @spec remove_event(t(), String.t()) :: t()
  def remove_event(%__MODULE__{} = bank, name) do
    %{bank | events: Map.delete(bank.events, to_string(name))}
  end

  @doc "The shapes a tone can have."
  @spec shapes() :: [String.t()]
  def shapes, do: @shapes

  @doc """
  What the event called `name` sounds like right now, as `Cauldron.Audio` takes it: a
  `Cauldron.Audio.Voice`, a list of `{delay_ms, voice}` for a layered one, or `nil` when
  there is no such event or it has no variants.

  ## Options

    * `:variant` — which variant to play, counted from zero. Default: one at random
  """
  @spec voice(t(), term(), keyword()) :: Cauldron.Audio.sound()
  def voice(%__MODULE__{} = bank, name, opts \\ []) do
    with %{variants: variants} = event <- event(bank, name),
         %{} = recipe <- pick(variants, opts),
         sound when not is_nil(sound) <- to_voice(recipe) do
      sound |> level(event.gain, event.pan) |> space(event.space)
    else
      _none -> nil
    end
  end

  @doc """
  The bank as the `:sounds` function `Cauldron.Audio.start/1` takes.

      Cauldron.Audio.start(sounds: Cauldron.SFX.sounds(bank))
  """
  @spec sounds(t()) :: (term() -> Cauldron.Audio.sound())
  def sounds(%__MODULE__{} = bank), do: fn name -> voice(bank, name) end

  @doc "The recipe of variant `index` of the event called `name`, or `nil`."
  @spec variant(t(), term(), non_neg_integer()) :: recipe() | nil
  def variant(%__MODULE__{} = bank, name, index) do
    with %{variants: variants} <- event(bank, name), do: Enum.at(variants, index)
  end

  @doc "A bank from the JSON file at `path` — a directory holding `sfx.json`, or the file itself."
  @spec read(Path.t()) :: {:ok, t()} | {:error, term()}
  def read(path) do
    file = manifest(path)

    with {:ok, body} <- File.read(file) do
      case JSON.decode(body) do
        {:ok, map} when is_map(map) -> {:ok, map |> from_map() |> resolve(Path.dirname(file))}
        {:ok, _not_a_map} -> {:error, :not_a_bank}
        {:error, reason} -> {:error, {:invalid_json, reason}}
      end
    end
  end

  defp resolve(bank, dir) do
    events =
      Map.new(bank.events, fn {name, event} ->
        {name, %{event | variants: Enum.map(event.variants, &variant(&1, dir))}}
      end)

    %{bank | events: events}
  end

  # A sample's `file` is written beside the bank, so a bank directory can move.
  defp variant(%{"kind" => "sample", "file" => file} = recipe, dir) when is_binary(file) do
    if Path.type(file) == :absolute,
      do: recipe,
      else: %{recipe | "file" => Path.expand(file, dir)}
  end

  defp variant(other, _dir), do: other

  @doc "As `read/1`, raising on anything unreadable."
  @spec read!(Path.t()) :: t()
  def read!(path) do
    case read(path) do
      {:ok, bank} -> bank
      {:error, reason} -> raise ArgumentError, "cannot read #{manifest(path)}: #{inspect(reason)}"
    end
  end

  @doc """
  Write the bank at `path` — a directory (where `sfx.json` goes) or a `.json` file.

  One field a line, so the file reads and diffs.
  """
  @spec write(t(), Path.t()) :: :ok | {:error, term()}
  def write(%__MODULE__{} = bank, path) do
    file = manifest(path)
    temporary = file <> ".tmp"

    with :ok <- File.mkdir_p(Path.dirname(file)),
         :ok <- File.write(temporary, pretty(to_map(bank)) <> "\n") do
      File.rename(temporary, file)
    end
  end

  @doc "Where the manifest of the bank at `path` is."
  @spec manifest(Path.t()) :: Path.t()
  def manifest(path) do
    if String.ends_with?(path, ".json"), do: path, else: Path.join(path, "sfx.json")
  end

  @doc "The bank as string-keyed maps of JSON-safe values."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = bank) do
    %{
      "format" => bank.format,
      "rate" => bank.rate,
      "channels" => bank.channels,
      "events" => Map.new(bank.events, fn {name, event} -> {name, event_to_map(event)} end)
    }
  end

  @doc """
  A bank from plain maps — string keys, as JSON gives them, or atom keys.

  Missing fields fall back to their defaults, a recipe of a kind this module does not know is
  dropped, and nothing raises.
  """
  @spec from_map(map()) :: t()
  def from_map(attrs) when is_map(attrs) do
    attrs = stringify(attrs)

    events =
      case attrs["events"] do
        map when is_map(map) ->
          Map.new(map, fn {name, event} -> {to_string(name), normalise_event(event)} end)

        _none ->
          %{}
      end

    %__MODULE__{
      format: integer(attrs["format"], @format),
      rate: integer(attrs["rate"], @rate),
      channels: channels(attrs["channels"]),
      events: events
    }
  end

  def from_map(_anything_else), do: %__MODULE__{}

  # -- events and recipes ---------------------------------------------------

  defp normalise_event(event) when is_map(event) do
    event = stringify(event)

    %{
      gain: number(event["gain"], 1.0) |> max(0.0),
      pan: event |> number("pan", 0.0) |> clamp(),
      space: event |> number("space", 0.0) |> max(0.0) |> min(1.0),
      priority: integer(event["priority"], 1),
      variants:
        event
        |> Map.get("variants")
        |> List.wrap()
        |> Enum.flat_map(fn variant -> List.wrap(recipe(variant)) end)
    }
  end

  defp normalise_event(_anything_else),
    do: %{gain: 1.0, pan: 0.0, space: 0.0, priority: 1, variants: []}

  defp event_to_map(event) do
    %{
      "gain" => event.gain,
      "pan" => event.pan,
      "space" => event.space,
      "priority" => event.priority,
      "variants" => event.variants
    }
  end

  defp recipe(map) when is_map(map) do
    map = stringify(map)

    case map["kind"] do
      "layers" -> layers_recipe(map)
      "sample" -> sample_recipe(map)
      "noise" -> noise_recipe(map)
      _tone -> tone_recipe(map)
    end
  end

  defp recipe(_anything_else), do: nil

  defp layers_recipe(map) do
    parts =
      map
      |> Map.get("parts")
      |> List.wrap()
      |> Enum.flat_map(&layer_part/1)

    if parts == [], do: nil, else: %{"kind" => "layers", "parts" => parts}
  end

  defp layer_part(part) when is_map(part) do
    part = stringify(part)

    case recipe(part["recipe"]) do
      nil -> []
      recipe -> [%{"at_ms" => integer(part["at_ms"], 0), "recipe" => recipe}]
    end
  end

  defp layer_part(_anything_else), do: []

  defp noise_recipe(map) do
    %{
      "kind" => "noise",
      "decay" => map |> number("decay", 0.2) |> max(0.001),
      "attack" => map |> number("attack", 0.002) |> max(0.0),
      "sustain" => map |> number("sustain", 0.0) |> max(0.0) |> min(1.0),
      "hold" => map |> number("hold", 0.0) |> max(0.0),
      "release" => map |> number("release", 0.0) |> max(0.0),
      "gain" => map |> number("gain", 0.5) |> max(0.0),
      "cutoff" => cutoff(map["cutoff"], 0.8),
      "highpass" => cutoff(map["highpass"], nil),
      "pan" => map |> number("pan", 0.0) |> clamp()
    }
  end

  defp sample_recipe(map) do
    sound = text(map["sound"])
    file = text(map["file"])

    if sound == nil and file == nil do
      nil
    else
      %{
        "kind" => "sample",
        "sound" => sound,
        "file" => file,
        "gain" => map |> number("gain", 0.8) |> max(0.0),
        "pan" => map |> number("pan", 0.0) |> clamp()
      }
    end
  end

  defp tone_recipe(map) do
    %{
      "kind" => "tone",
      "shape" => shape(map["shape"]),
      "freq" => map |> number("freq", 440.0) |> max(1.0),
      "decay" => map |> number("decay", 0.08) |> max(0.001),
      "attack" => map |> number("attack", 0.002) |> max(0.0),
      "sustain" => map |> number("sustain", 0.0) |> max(0.0) |> min(1.0),
      "hold" => map |> number("hold", 0.0) |> max(0.0),
      "release" => map |> number("release", 0.0) |> max(0.0),
      "sweep" => map |> number("sweep", 1.0) |> max(0.0),
      "gain" => map |> number("gain", 0.6) |> max(0.0),
      "cutoff" => cutoff(map["cutoff"], nil),
      "highpass" => cutoff(map["highpass"], nil),
      "fm" => map |> number("fm", 0.0) |> max(0.0),
      "fmh" => map |> number("fmh", 1.0) |> max(0.0),
      "fmattack" => map |> number("fmattack", 0.0) |> max(0.0),
      "detune" => map |> number("detune", 0.0) |> max(0.0),
      "pan" => map |> number("pan", 0.0) |> clamp()
    }
  end

  defp to_voice(%{"kind" => "tone"} = recipe) do
    voice =
      Voice.new(
        shape: shape_atom(recipe["shape"]),
        freq: recipe["freq"],
        sweep: recipe["sweep"],
        gain: recipe["gain"],
        cutoff: recipe["cutoff"],
        highpass: recipe["highpass"],
        fm: none_if_zero(recipe["fm"]),
        fmh: recipe["fmh"],
        fmattack: none_if_zero(recipe["fmattack"]),
        pan: recipe["pan"],
        envelope: envelope(recipe)
      )

    case recipe["detune"] do
      cents when is_number(cents) and cents <= 0.0 ->
        voice

      cents ->
        shift = :math.pow(2, cents / 2400)
        low = %{voice | freq: voice.freq / shift, gain: voice.gain * 0.75}
        high = %{low | freq: voice.freq * shift, pan: -voice.pan}
        [{0, low}, {0, high}]
    end
  end

  defp to_voice(%{"kind" => "noise"} = recipe) do
    Voice.new(
      shape: :noise,
      gain: recipe["gain"],
      cutoff: recipe["cutoff"],
      highpass: recipe["highpass"],
      pan: recipe["pan"],
      envelope: envelope(recipe)
    )
  end

  defp to_voice(%{"kind" => "sample"} = recipe) do
    cond do
      is_binary(recipe["file"]) ->
        Voice.new(
          sample: Sample.load!(recipe["file"]),
          gain: recipe["gain"],
          pan: recipe["pan"]
        )

      is_binary(recipe["sound"]) ->
        Kit.voice(recipe["sound"], 0.5, gain: recipe["gain"], pan: recipe["pan"])

      true ->
        nil
    end
  end

  defp to_voice(%{"kind" => "layers", "parts" => parts}) do
    Enum.map(parts, fn part -> {part["at_ms"], to_voice(part["recipe"])} end)
  end

  # A release only sounds when something is left to release, so a recipe that asks for a
  # tail and leaves the sustain at zero gets a small one. Without it the knob would do
  # nothing on a percussive sound, which is exactly where it is wanted.
  defp envelope(recipe) do
    sustain =
      if recipe["release"] > 0.0 and recipe["sustain"] == 0.0,
        do: 0.35,
        else: recipe["sustain"]

    Envelope.new(
      attack: recipe["attack"],
      decay: recipe["decay"],
      sustain: sustain,
      hold: recipe["hold"],
      release: recipe["release"]
    )
  end

  defp none_if_zero(value) when is_number(value) and value == 0.0, do: nil
  defp none_if_zero(value), do: value

  # A room, cheaply: the sound again a little later, quieter and on the other side.
  defp space(sound, amount) when is_number(amount) and amount <= 0.0, do: sound

  defp space(sound, amount) do
    parts = parts(sound)

    echoes =
      for {at, level, place} <- [{60, 0.35, -0.6}, {110, 0.22, 0.5}, {170, 0.14, -0.3}],
          {offset, voice} <- parts do
        {at + offset,
         %{
           voice
           | gain: voice.gain * amount * level,
             pan: clamp(voice.pan + place * amount)
         }}
      end

    parts ++ echoes
  end

  defp parts(%{} = voice), do: [{0, voice}]
  defp parts(parts) when is_list(parts), do: parts

  # The event's own level and place, over everything the variant set.
  defp level(voices, gain, pan) when is_list(voices) do
    Enum.map(voices, fn {at, voice} -> {at, level(voice, gain, pan)} end)
  end

  defp level(voice, gain, pan) do
    %{voice | gain: max(voice.gain * gain, 0.0), pan: (voice.pan + pan) |> clamp()}
  end

  defp pick([], _opts), do: nil

  defp pick(variants, opts) do
    case Keyword.get(opts, :variant) do
      nil -> Enum.random(variants)
      index when is_integer(index) -> Enum.at(variants, index)
    end
  end

  # -- the starter's own vocabulary ----------------------------------------

  defp starter_event(variants, opts \\ []) do
    %{
      gain: Keyword.get(opts, :gain, 1.0),
      pan: Keyword.get(opts, :pan, 0.0),
      priority: Keyword.get(opts, :priority, 1),
      variants: variants
    }
  end

  defp tone(shape, freq, decay, gain, opts \\ []) do
    %{
      kind: "tone",
      shape: to_string(shape),
      freq: freq,
      decay: decay,
      gain: gain,
      sweep: Keyword.get(opts, :sweep, 1.0),
      cutoff: Keyword.get(opts, :cutoff)
    }
  end

  defp noise(decay, gain, opts \\ []) do
    %{kind: "noise", decay: decay, gain: gain, cutoff: Keyword.get(opts, :cutoff)}
  end

  defp layers(parts) do
    %{kind: "layers", parts: Enum.map(parts, fn {at, recipe} -> %{at_ms: at, recipe: recipe} end)}
  end

  # -- reading values ------------------------------------------------------

  defp shape(value) when is_binary(value) do
    if value in @shapes, do: value, else: "sine"
  end

  defp shape(value) when is_atom(value) and not is_nil(value), do: shape(Atom.to_string(value))
  defp shape(_anything_else), do: "sine"

  defp shape_atom(name), do: String.to_atom(name)

  defp cutoff(nil, default), do: default
  defp cutoff(value, _default) when is_number(value), do: value |> max(0.0) |> min(1.0)
  defp cutoff(_anything_else, default), do: default

  defp clamp(value), do: value |> max(-1.0) |> min(1.0)

  defp text(value) when is_binary(value) and value != "", do: value
  defp text(_anything_else), do: nil

  defp channels(value) when value in [1, 2], do: value
  defp channels(_anything_else), do: @channels

  defp integer(value, _default) when is_integer(value), do: value
  defp integer(value, _default) when is_float(value), do: trunc(value)
  defp integer(_value, default), do: default

  defp number(value, _default) when is_number(value), do: value * 1.0
  defp number(_value, default), do: default * 1.0

  defp number(map, key, default), do: number(Map.get(map, key), default)

  defp stringify(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  # -- writing a manifest --------------------------------------------------

  defp pretty(value, level \\ 0)

  defp pretty(value, _level)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value),
       do: JSON.encode!(value)

  defp pretty(value, level) when is_map(value) do
    case value |> Map.to_list() |> Enum.sort() do
      [] ->
        "{}"

      pairs ->
        lines =
          Enum.map_join(pairs, ",\n", fn {key, field} ->
            pad(level + 1) <> JSON.encode!(to_string(key)) <> ": " <> pretty(field, level + 1)
          end)

        "{\n" <> lines <> "\n" <> pad(level) <> "}"
    end
  end

  defp pretty(value, level) when is_list(value) do
    case value do
      [] ->
        "[]"

      items ->
        "[\n" <>
          Enum.map_join(items, ",\n", &(pad(level + 1) <> pretty(&1, level + 1))) <>
          "\n" <> pad(level) <> "]"
    end
  end

  defp pretty(value, _level), do: JSON.encode!(value)

  defp pad(level), do: String.duplicate("  ", level)
end
