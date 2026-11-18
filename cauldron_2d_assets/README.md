# Cauldron2D.Assets

A game's art made by image models running on your own machines through
NxDiffusion Studio: asked for in words, chosen
between, and finished as pixel art for a `Cauldron2D.Atlas`.

## How it goes

1. Write `assets.exs` beside the game's `mix.exs` (`Cauldron2D.Assets.Manifest`
   describes it): the Studio project, the model, a style every prompt shares, the flat
   background the model is asked to draw on, the palette, and each asset's prompt, how
   many candidates to make and the most its finished picture may be.
2. `mix cauldron.assets` asks the Studio for every asset that is new or changed, waits
   for the pictures, finishes each candidate (`Linocut.Pixelate`: the background keyed
   out from the picture's edge, the model's pixel grid found and sampled, the colours
   held to the palette, outlined, trimmed and fitted), and writes a sheet of them to
   `priv/art/.candidates/<name>.png`.
3. Look at the sheet and `mix cauldron.assets.pick NAME INDEX`. The chosen picture is
   written to `priv/art/<name>.png`, where `Cauldron2D.Atlas.load/3` reads it.

An asset asked for one candidate has it chosen at once.

`assets.lock.exs` records, for each asset, the digest of its spec, the candidates' ids
in the Studio's library and the choice. Keep it in the repository: building again
finishes the same pictures without asking the model, and only a changed prompt, model,
size, count or seed asks again. `mix cauldron.assets --again NAME` asks for new
candidates for an asset whose spec has not changed.

## What an asset can be

Each entry in `assets.exs` is one of these (`Cauldron2D.Assets.Manifest` has every
option):

* **A picture** — `prompt:`, with `count:`, `size:`, `seed:`, `fit:` (the most the
  finished picture may be), and the manifest's style, background and palette, each of
  which an asset may set for itself.
* **An edit of another asset** — `from: :other` and an instruction as the prompt
  (`"the same goblin raising its club"`): the chosen picture of `:other` changed, its
  background kept.
* **An animation from video** — `from: :other` with `video: [frames:, keep:, from:, to:]`:
  the chosen picture set moving by a video model, and `keep` frames between those shares
  of the clip finished together as one strip.
* **An animation of a rigged character** — `rig:` (a rig made in the Studio) with
  `motion:` — the movement in words, its length, the angle it is seen from, a seamless
  loop, the frames kept and arm swing for a walk or run — rendered on a transparent
  background and finished as one strip.

Every picture is finished as `finish:` asks (`Linocut.Pixelate`'s options: the palette,
dithering, outline, size).

## Commands

* `mix cauldron.assets` — build every asset that is new or changed
* `mix cauldron.assets --only NAME` — only these assets (repeat the flag; a quoted
  `'hero_*'` takes every asset whose name starts `hero_`)
* `mix cauldron.assets --again NAME` — new candidates for an asset whose spec has not
  changed
* `mix cauldron.assets.pick NAME INDEX` — choose a candidate
* `--manifest PATH` and `--out DIR` on both — another manifest than `assets.exs`, and
  another folder than `priv/art`

## The Studio

`Cauldron2D.Assets.Studio` calls the Studio's MCP server over HTTP: `NX_STUDIO_URL`,
else `config :cauldron_2d_assets, studio: url`, else `http://localhost:4102/mcp`. A
program on the Studio's machine needs no token; from elsewhere, set `NX_STUDIO_TOKEN`
(or `config :cauldron_2d_assets, studio_token: token`) to the Studio's agent token.

## A dependency for development

The art is made while a game is written, and the game ships its `priv/art`. Add the
package for development only:

```elixir
{:cauldron_2d_assets, "~> 0.1", only: :dev, runtime: false}
```

## License

[AGPL-3.0-only](LICENSE). You may use, study, change and share it under the AGPL at
no cost.

A game or service whose source you do not publish needs a
[commercial license](COMMERCIAL.md).
