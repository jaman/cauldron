# CauldronSFXWeb

The sound-effect editor in a browser, built with LiveView. It is `Cauldron.SFX.Editor` —
the same state, keys and `view/1` the terminal front end uses — drawn as a list and a row
of buttons, with the keyboard doing the same as the buttons.

```console
$ mix cauldron.sfx.web priv/sfx/sfx.json
SFX editor: http://localhost:4040
```

With no file it opens the starter bank.

## First five minutes

1. Start it on your game's bank, or with no file to open the starter one:
   `mix cauldron.sfx.web priv/sfx/sfx.json`.
2. Pick an event from the list. `boom` is layered — a noise and a tone 10 ms apart — and
   `fire` has three variants, so it does not sound the same twice.
3. Press **play**. What you hear is the game's own `Cauldron.Audio.Voice`.
4. Shape it. `shape` cycles the waveform, `pitch ]` `[` moves it a semitone, `decay`
   makes it shorter or longer, `attack` and `release` change how it starts and ends,
   `sweep` bends it, `cutoff` darkens it, `pan` places it, and `space` puts it in a room.
   `variant +` adds another take; `variant -` drops one.
5. Name yours: type into **new event name**, press **add event**. It starts as the
   **preset** — `preset` cycles laser, zap, coin, jump, explosion, whoosh, hit, bell, clang —
   so it sounds like something before you touch it. The name has to be the event your game
   plays: `Cauldron.Audio.play([:laser])` needs an event called `laser`.
6. Press **write**, then in the game:

   ```elixir
   bank = Cauldron.SFX.read!("priv/sfx/sfx.json")
   Cauldron.Audio.start(sounds: Cauldron.SFX.sounds(bank))
   ```

   and `Cauldron.Audio.play([:laser])` sounds it.

An event the game needs to *vary* — `{:bomb, by}` — cannot be a bank event: a bank names
sounds, and a compound event is the game's own table's business. Keep those in the game's
`sounds/0` and let the bank carry the plain names.

## What it does

Click an event to select it, or use ↑ ↓. `←` `→` move between its variants; `p` plays it;
`s` cycles a tone's shape; `+` `-` change the event's gain; `>` `<` its pan; `]` `[` the
variant's pitch; `a` adds a variant, `d` removes one; `w` writes the bank.

A play renders the sound to a WAV on the server and pushes it down the socket, where the
page plays it. The voice is the same `Cauldron.Audio.Voice` the game plays, so what you
hear is what the game hears — a layered event included, each part at its own offset.

## Running it

`mix cauldron.sfx.web` starts it on its own. From code:

```elixir
{:ok, _} = Cauldron.SFX.Web.Serve.serve(port: 4040, bank: "priv/sfx/sfx.json")
```

The endpoint, router and LiveView are ordinary Phoenix pieces, so a host application can
also start the endpoint and route to `Cauldron.SFX.Web.EditorLive` itself.

## The rest of the editor

The model, the bank and the terminal front end are in `cauldron_core`, `cauldron_sfx` and
`cauldron_sfx_web`'s siblings; this package only draws and plays.
