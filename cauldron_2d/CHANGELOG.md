# Changelog

## [Unreleased]

### Breaking changes

* `Cauldron2D.Arenas`, `Arenas.Table`, `Arenas.OnDemand` and `Arenas.Sweeper` are now
  `Cauldron2D.Worlds`, `Worlds.Table`, `Worlds.OnDemand` and `Worlds.Sweeper`, with the
  same functions. Rename the module in every call.
* The registry and supervisor the worlds run under are `Cauldron2D.Worlds.Registry` and
  `Cauldron2D.Worlds.Supervisor`. A world's own supervisor is registered under
  `Worlds.via({:supervisor, id})`, not `{:arena, id}`.
* `Cauldron2D.Worlds.start/1` returns `{:error, :unknown_world}` for an unregistered id
  (was `:unknown_arena`).
* `Cauldron2D.Client.Game` callback `arenas/1` is now `worlds/1`, and the `arena()` type
  is `world()`. Rename the callback; the entries keep the same keys.
* `Cauldron2D.Client.Game.arena/3` is now `Cauldron2D.Client.Game.world/3`.
* The screen a world is played on is `:play`, not `:arena`: `cue(view, :play)` and
  `cue(view, {:static, :play})`, and `:play` in the `screen()` type.
* `outcome/1`'s `:next` is `:next_world` or `:same_world` (was `:next_arena` or
  `:same_arena`).
* `Cauldron2D.Stats.arenas/0` is now `Cauldron2D.Stats.worlds/0`, and its `arena()` type
  is `world()`.
* `Cauldron2D.Ledger.board/4` narrows to one world with `world:` (was `arena:`); an
  `arena:` option is ignored.
* `Cauldron2D.Ledger.record/4` stores the world's name on a row as `:label` (was
  `:arena`), so a `forget/2` predicate reads `row.label`. Rows recorded before still
  match `board/4`'s `world:`.
* `Cauldron2D.Ledger.Recorder` takes `:label` for the name results are kept under;
  `:arena` is still read when `:label` is absent.
### Added

* Five projections of the same world, each taking the atlas, a `:focus` or `:position`
  and the scene's `:cell`:
  * `Cauldron2D.Projection.Oblique` — a square grid seen from above and in front,
    standing arts as a front face with their top above it; `:facings` of `1` or `4`.
  * `Cauldron2D.Projection.Iso` — floors as diamonds, standing arts as blocks with a top
    and two shaded sides, movers upright; `:facing`, `:facings` (4 to 32 stamped, any
    other count or `:free` sampled), `:tilt` and `:shrink`.
  * `Cauldron2D.Projection.Mode7` — the ground plane in perspective to a horizon,
    turning freely, movers as billboards.
  * `Cauldron2D.Projection.FirstPerson` — raycast from `:position` along `:heading` with
    `:pitch` and `:eye`: walls from standing arts, textured floors, movers as billboards,
    fog to the atlas's void colour.
  * Iso, Oblique and Mode7 answer `project/3`, `unproject/3` and `tile_at/3`, all taking
    the atlas first; Iso and Oblique also `cells/2` and `ground_map/2`, and Iso `up/1`.
* `Cauldron2D.Projection.Glyphs.compose/3`: an isometric or oblique view drawn as the
  atlas's two-character glyphs.
* `Cauldron2D.Projection.Canvas` (RGBA rows, stamps, `quad/5`) and
  `Cauldron2D.Projection.Ground` (the perspective ground sampler, in C with an Elixir
  fallback; `available?/0`).
* `Cauldron2D.Projection.Volume`: a coloured region of space that tints what is seen
  through it, drawn by every projection and by `Cauldron2D.Surface`. A volume has `:at`,
  `:shape`, `:colour`, `:strength`, a falloff of `:depth`, `:flat` or `:shell`, and
  `:follows` to move with a subject (`anchored/2`).
  `Cauldron2D.Projection.Volume.Shapes` gives a sphere, a cylinder, a cone, a beam and a
  set of whole tiles; `Cauldron2D.Projection.Volume.Shape` is the behaviour for a shape of
  your own. `Volume.Native` paints the built-in shapes in C.
* `Cauldron2D.Parallax`: background layers each moved by their own share of the camera's
  motion (`factor`, `drift`, `origin`, `void`, `front: true` to draw over the world).
  `layer/1`, `strip/2` and `legend/2` for authored tiles, `scatter/1` for art placed by
  hashing the tile coordinate, `panorama/1` for one repeated picture, `bands/1` for a
  factor per range of rows, `compose/3`, `view/2`, `forget/1`. `Parallax.Preview.frames/3`
  runs a camera across a set of layers.
* `Cauldron2D.Blend.over/2`: source-over compositing of two RGBA binaries, in C with an
  Elixir fallback (`available?/0`).
* `Cauldron2D.Input.Pad`: a padmap from action to controller buttons and axes in the Xbox
  layout. `new/2`, `handle/2` for `Gamepad.Wire` events, `held/1`, `strength/1`,
  `default_map/1`; `{:stick, side}` or `{:stick, side, push: [...]}` bound to `:aim`
  makes that stick aim (`aim/1`, `aim_stick/1`, `push/1`).
* `Cauldron2D.Input.merge/3` takes how hard each outside action is held;
  `Cauldron2D.Input.state/1` carries `:strength` when any action is partly held.
* `Cauldron2D.Game.input()` type: the input a game's `handle_input/3` receives, which
  may carry `:strength` and, from a client looking through an eye, `:heading`.
* `Cauldron2D.Route`: a click on the ground turned into a walk. `to/4` finds the tile
  centres to pass through with `Cauldron2D.Grid.Path`; `advance/3`, `heading/2`,
  `arrived?/1`, `goal/1`.
* `Cauldron2D.Client.Game` optional callbacks: `start/0` (`:lobby`,
  `{:lobby, title: false}`, `{:play, id}`, `{:play, id, title: true}`, or a function of
  the client's state), `look/0` (the view a client opens in: projection, projections to
  cycle, facing, facings, tilt, heading, pitch, zoom, density, and keys of the game's
  own), `scene/2` (the scene given the look), `padmap/1` and `client_pad/0`.
  `client_keys/0` may bind a list of keys, and `{:look, key}` adds a key that flips a
  look key of the game's own.
* A scene may carry `:heading`, `:volumes` and `:layers`; movers may be
  `{art, {x, y}, heading}`.
* `Cauldron2D.Atlas.put/4` options `:height` (storeys), `:faces` (`:top`, `:side`,
  `:north`, `:east`, `:south`, `:west`), `:poses` (`:front`, `:back`, `:side`), `:stand`
  and `:eye`; `Atlas.face/3`, `pose/4`, `standing/2`, `eye_height/2` and `tallest/1`.
* The atlas manifest (`atlas.txt`) takes four more columns after the derivation: height,
  faces, poses and stand. An art the manifest alone names is built from its faces or its
  front pose.
* `Cauldron2D.Surface.compose/4` options `:volumes`, `:void` (`:opaque` or
  `:transparent`) and `:under` (a raster drawn beneath); `Surface.stack/2`,
  `Surface.sprite_rgba/4`; `tile_binary/5` takes the void mode. A mover may be
  `{art, {x, y}, tint}` or `{art, {x, y}, tint, pose, flip}`.
* `Cauldron2D.Renderer.resolved/1`: the mode from `CAULDRON_MODE` and configuration,
  before any terminal is asked.

### Changed

* An art may be any size. A cell's base must still be one tile; a larger overlay stands
  on its cell, bottom edge on the cell's bottom and centred across it, and a mover is
  drawn at its own size. All frames of one art must be the same size.
* `Cauldron2D.Atlas.load/3` reads a multi-frame `.pic` frame by frame; a `.png` that is
  not one tile or a strip of tiles loads as one art of its own size instead of
  `{:error, {:art, file, :size}}`.
* `lobby?/0` is read as `start/0`: `false` means `{:play, :first, title: true}`.
* `Cauldron2D.Surface` blends tiles through `Cauldron2D.Blend`.
* The package builds C NIFs for the ground plane, volumes and blending through
  `elixir_make` (`c_src/`, `Makefile`, and `Makefile.win` for `nmake` and `cl` on Windows;
  `elixir_make` is a new dependency). Without a C
  compiler the build still succeeds and the Elixir code does the same work.
