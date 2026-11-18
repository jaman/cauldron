# Sound and music

A game does not play sound. It emits events, declares what each event sounds like, and a
client plays it. Music works the same way: a game declares its pieces and says which
section and which layers belong to each screen, and the client cues them.

`Cauldron.Audio` mixes and plays; `Cauldron.Audio.Music` is the part that knows about
sections and layers; `Cauldron.Audio.Voice` makes a sound.

## What a client module provides

| Callback | Gives |
| --- | --- |
| `sounds/0` | A function from an event name to the voice it makes, or `nil` |
| `music/0` | The pieces, `[{name, spec}]` |
| `cue/2` | The piece, section and layer levels for a screen, or `nil` |
| `listener/1` | Where the listener is, for placed events, or `nil` |
| `audio/0` | `:voices`, `:earshot`, `:master` and `:rate` for the audio instance |
| `recordings/0` | A function from an event name to a recording, for recorded music |
| `sink/1` | Where this player's sound goes, from the client's props |

`use Cauldron.Client.Game` gives the first three a silent default: a function that
answers `nil` for every event, no pieces, no cue. A game without sound writes nothing; a
game with sound writes all three.

## Events and voices

An event is any term the table knows: `:brick`, `:tag`, `{:explosion, {x, y}}`. A sound is
one voice, a run of `{delay_ms, voice}` pairs for several at once, or `nil` for silence.

```elixir
defmodule Tag.Sound do
  alias Cauldron.Audio.Voice

  def voice(event) do
    case event do
      :tag -> Voice.new(shape: :square, freq: 660.0, gain: 0.6)
      :miss -> Voice.new(shape: :noise, gain: 0.3)

      {:step, {_x, _y}} ->
        [
          {0, Voice.new(shape: :noise, gain: 0.2)},
          {60, Voice.new(shape: :sine, freq: 180.0, gain: 0.4)}
        ]

      _unknown -> nil
    end
  end
end
```

`Cauldron.Audio.Voice.new/1` takes a shape (`:sine`, `:square`, `:saw`, `:triangle`,
`:noise`), a frequency, a sweep, a gain, a pan, an envelope, filters, waveshaping and
more. A voice is rendered to 16-bit PCM at the stage's rate once, then played. The same
seed renders the same noise.

A placed event is `{name, {x, y}}`. With a listener set, it is scaled by its distance —
full within one tile, silent at `:earshot` tiles — and panned by its side. Without a
listener, placed and unplaced events play at full level, centred. `listener/1` is read
from each view, so a listener moves as the player does.

## The audio instance

The client starts one `Cauldron.Audio` per player, with the game's `sounds/0` as its
table, the game's `audio/0` options and the player's sink. Each frame's events are
played through it. A game can be played without a front end too:

```elixir
{:ok, audio} =
  Cauldron.Audio.start_link(
    name: nil,
    sounds: &Tag.Sound.voice/1,
    sink: Cauldron.Audio.Sink.process(self())
  )

Cauldron.Audio.listener(audio, {0.0, 0.0})
Cauldron.Audio.play(audio, [:tag, {:step, {3.0, 1.0}}])
```

`Cauldron.Audio.Sink` names where sound goes: `speaker/0` for this machine,
`silent/0` for nowhere, `process/2` for messages to a process, `pulse/1` for a
PulseAudio or PipeWire server. When nothing can play, the stage stays silent and the
sound calls are no-ops returning `:ok`. `Cauldron.Audio.on?/1` says which it is.

The stage sounds at most `:voices` sounds at once and lets the oldest go past that. The
effects and music levels are separate and set with `Cauldron.Audio.levels/3`;
`Cauldron.Audio.mute/2` silences both and restores them. A sound that should keep
sounding under a key — an alarm, an engine — is a keyed event.
`Cauldron.Audio.keyed/4`, `Cauldron.Audio.moved/2` and `Cauldron.Audio.stopped/2`
replace, place and release the sound under that key.

## Music

A piece is a tempo, its layer names, and for each section what every layer plays:

```elixir
defmodule Tag.Sound do
  def music do
    [
      {"tag", %{
        bpm: 112,
        beats_per_bar: 4,
        layers: [:drums, :bass],
        sections: %{
          calm: %{drums: ~s|s("hh*4")|, bass: ~s|note("c2 c2 g2 c2").s("sawtooth")|},
          chase: %{drums: ~s|s("bd*4")|, bass: ~s|note("c2 c2 eb2 g2").s("sawtooth")|}
        }
      }}
    ]
  end
end
```

What a layer plays is either a Strudel chain, performed live on the listener's stage, or
something rendered once. A rendered layer is a `Cauldron.Audio.Score`, a zero-arity
function returning PCM, `{:pcm, binary}` at the stage's rate, or
`{:pcm, binary, rate, channels}`. A rendered piece is kept in the game's music directory
under `piece/section/layer`, with a fingerprint of what was written. A changed layer is
rendered again; an unchanged one is read back. A section cued while it renders takes
effect when it is ready, at the next bar boundary, with a cross-fade.

A piece of long recordings sets `render: :on_cue`, so a section is rendered when first
cued. A piece that is already rendered — a song bundle loaded with
`Cauldron.Audio.Music.from_song/3` — sets `render: :ready`, and nothing is rendered or
kept. A piece's `:fingerprint` keys its renders: change it when the music's meaning
changes without its text changing.

## Cueing by screen

`cue/2` is given a view and the screen, and returns a cue:
`%{piece: name, section: atom, layers: %{layer => level}}`, or `nil` for silence. The
client turns that answer into a `Cauldron.Audio.Music.cue/2` call on the player's audio
instance.

```elixir
defmodule Tag.Sound do
  def cue(view, :play) do
    %{piece: "tag", section: view.section, layers: %{drums: 1.0, bass: 0.8}}
  end

  def cue(_view, :title), do: %{piece: "tag", section: :calm, layers: %{drums: 0.6, bass: 0.7}}
  def cue(_view, :summary), do: %{piece: "tag", section: :calm, layers: %{drums: 0.0, bass: 0.6}}
  def cue(_view, _screen), do: nil
end
```

The screens are `:title`, `:lobby`, `:settings`, `:play`, `:summary` and `:guide`. On
`:summary` the view is the last one the world showed. The layer levels are the mix: a
layer at `0.0` is there but unheard, which is how a section fades its drums out without
naming another section.

The client declares every piece in `music/0` once, then cues the current screen's cue as
the screen changes and as views arrive.

A client whose music is static — an audio instance started with `static_music: true`, as
a server with many players may set — asks `cue(view, {:static, screen})` first. That is
the one section it will loop for the whole stay, so a game may answer with a loop rather
than the layered piece. The client falls back to `cue(view, screen)` when that is `nil`.

## How the client gets it

A game's client module gives the sound callbacks the way it gives every other:

```elixir
defmodule Tag.Client do
  use Cauldron.Client.Game

  # title/0, view/0, actions/0, keymaps/0, worlds/1 and scene/2 fill the rest of the
  # contract; these are the callbacks sound and music come from.

  def sounds, do: &Tag.Sound.voice/1
  def music, do: Tag.Sound.music()
  def cue(view, screen), do: Tag.Sound.cue(view, screen)
  def listener(view), do: {view.me.x, 0.0}
  def audio, do: [voices: 16, earshot: 24.0]
end
```

`:earshot` is in tiles. `:voices` caps how many sounds are mixed at once. `:rate` is the
stage's sample rate; a game whose music is recorded at another rate sets it to the
recording's rate. `:master` `:sfx` makes the effects level scale the music too.

A game's rendered music lives under `Cauldron.Client.Game.music_dir/1`, which is
`Cauldron.Paths.cache(home, "music")`; the home is the game's `home/0`, or its client
module's first name underscored. `Cauldron.Audio.cache_dir/0` is the shared fallback.
Deleting that directory costs a render, never a game.

## Where to go next

| You want to | Read |
| --- | --- |
| Know why nothing is audible | [Troubleshooting](troubleshooting.html) |
| Let a menu make a sound | [Input and menus](input-and-menus.html) |
| Keep the game's files in one place | [Saving and scores](saving-and-scores.html) |
| Find a word | [Glossary](glossary.html) |
