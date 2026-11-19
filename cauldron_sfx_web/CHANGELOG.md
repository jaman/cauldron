# Changelog

## [0.4.0]

### Added

- Licensed under AGPL-3.0-only, with a commercial license for a game or service that does
  not publish its source: see `COMMERCIAL.md`.

- `Cauldron.SFX.Web.EditorLive`: the sound-effect editor in a browser, over the same
  `Cauldron.SFX.Editor` state the terminal front end drives.
- `mix cauldron.sfx.web` and `Cauldron.SFX.Web.Serve.serve/1` start it.
- Sound is rendered server-side to a WAV and pushed to the page, so a play is the game's
  own voice.
