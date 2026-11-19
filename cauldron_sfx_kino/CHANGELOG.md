# Changelog

## [0.4.0]

### Added

- Licensed under AGPL-3.0-only, with a commercial license for a game or service that does
  not publish its source: see `COMMERCIAL.md`.

- `Cauldron.SFX.Kino.Editor`: the sound-effect editor as a Livebook cell, over the same
  `Cauldron.SFX.Editor` state the terminal and browser front ends drive.
- `notebooks/sfx.livemd`: a walkthrough of the editor and the bank it edits.
- Depends on `cauldron_core` 0.4, where the bank, the editor's state and the WAV renderer
  (`Cauldron.SFX.Audio`) live.
