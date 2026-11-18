# Changelog

## [Unreleased]

- `Cauldron.Palette`: the colour names a hud uses, as RGB, for any drawer.
- First release: the parts of `cauldron_2d` 0.3 with no way of drawing, under `Cauldron.*` — games and worlds, play across machines, input, menus, the client modules every front end shares, sound, saving and the game-state helpers.
- `Cauldron.Client.View`: how a kind of game is drawn and looked at, named by a game's new required `c:Cauldron.Client.Game.view/0`. `Cauldron.Client.Stage`, `Party` and `Controls` turn the look, step the zoom and draw scenes through it.
- `Cauldron.Client.Hud.colour/2` takes the front end's lookup for named colours.
- `Cauldron.World.Pending`: a press that begins and ends between two of a world's steps counts for one step.
- Sound modules for games, so a game needs no other package: `Cauldron.Audio.Voice`, `Envelope`, `Filter`, `Curve` and `Sample` make sounds; `Cauldron.Audio.Score` and `Part` write music; `Cauldron.Audio.Decoder` decodes MP3, Ogg Vorbis, FLAC and WAV; `Cauldron.Audio.Sink` names where sound goes (`speaker/0`, `silent/0`, `process/2`, `pulse/1`); `Cauldron.Audio.cache_dir/0`. Depends on `tuning_fork_speaker`, so sound plays through the speaker without a dependency of the game's own.
- Configuration is `config :cauldron_core, sweeper: ..., beacon_port: ...`.
