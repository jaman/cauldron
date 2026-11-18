# CauldronSFXKino

The sound-effect editor in a Livebook cell. It is `Cauldron.SFX.Editor` — the same state,
keys and `view/1` the terminal and browser editors use — drawn in a cell, with sound
rendered in the notebook's process and played by the browser.

```elixir
Cauldron.SFX.Kino.Editor.new()
Cauldron.SFX.Kino.Editor.new("priv/sfx/sfx.json")
Cauldron.SFX.Kino.Editor.new(bank, out: "priv/sfx/sfx.json")
```

The notebook in [`notebooks/sfx.livemd`](notebooks/sfx.livemd) is a walkthrough: open it in
Livebook and run the cells.

## What it does

Click an event to select it; **play** sounds it — the game's own `Cauldron.Audio.Voice` —
and the buttons shape it: shape, pitch, decay, sweep, cutoff, gain, pan. **variant +**
adds a take, **delete event** removes one, and a name typed under the list makes a new
event with **add event**. **write** saves the bank.

A play is rendered to a WAV with `Cauldron.SFX.Audio.wav/1` and sent to the cell, which
plays it as an `Audio` element. Nothing is rendered ahead of time.

## License

[AGPL-3.0-only](LICENSE). You may use, study, change and share it under the AGPL at
no cost.

A game or service whose source you do not publish needs a
[commercial license](COMMERCIAL.md).
