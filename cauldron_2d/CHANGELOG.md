# Changelog

## Unreleased

### Added

* `Cauldron2D.World`'s `:follow`: a world on this machine or another that runs a host
  world's game on its own copy of the state. The host sends it, after each tick, the
  joins, leaves and input it applied and the steps it ran, with a checksum every 60
  steps (`Cauldron2D.World.Lockstep`); the follower's players' joins, leaves and input
  go to the host. Only those cross between machines, never views. A follower that falls
  out of step takes the host's state again, and stops when the host does.
* `Cauldron2D.Game`'s optional `export/1`, `restore/1` and `checksum/1`: what a follower
  starts from, how its machine fills it in, and what host and follower compare.
* `Cauldron2D.World.start/1`, a world not linked to the caller.

### Removed

* `Cauldron2D.Client.Game.received/3`.

## [0.2.5]

### Added

* `Cauldron2D.Client.Game.received/3`
, optional: a game's view of each frame's view and
  events, keeping what it learns between frames, for a world that sends a client part of
  what it shows as operations.

## [0.2.4]

### Fixed

* `Cauldron2D.Ledger.Lock` finds the holder with `tasklist` on Windows and `ps` on Unix,
  where it ran `kill`, which Windows lacks, so a lock left by a crash stopped the ledger
  from starting there. A lock whose process id now belongs to a program other than an
  Erlang VM counts as free.
* `Cauldron2D.Distribution.join/3` names the joining node at this machine's address on
  the host's network (`address_toward/1`, new), not the first private address, which on
  Windows could be a VPN's.
* `Cauldron2D.Distribution` starts `epmd` on Windows when none answers, through a
  short-lived `erl -sname` whose launcher starts it detached, so it outlives the game and
  its console; it waits for `epmd` to answer before starting the node. Starting it while
  one runs changes nothing.

## [0.2.3]

### Fixed

* On Windows the NIFs are built into `priv/native/<system architecture>`, where they are loaded from, instead of `priv/`.

## [0.2.0]

### Breaking changes

* `Cauldron2D.Grid.Coarse` routes through regions of open tiles instead of whole
  blocks: a path is tile centres ending at the goal point, placed continuously across
  a wrapping grid's edges, and covers the next `:ahead` regions (default 3) of a longer
  way. `find/4` takes options (`:ahead`) where it took a search limit, `:block` defaults
  to 8, and `passable?/2`, `block_of/2` and `centre/2` are gone. `waypoint/4` takes the
  body's radius (default 0.0) and looks at the first 16 points.
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
* `arena/3` in `Cauldron2D.Client.Game` is now `Cauldron2D.Client.Game.world/3`.
* The screen a world is played on is `:play`, not `:arena`: `cue(view, :play)` and
  `cue(view, {:static, :play})`, and `:play` in the `screen()` type.
* `outcome/1`'s `:next` is `:next_world` or `:same_world` (was `:next_arena` or
  `:same_arena`).
* `arenas/0` in `Cauldron2D.Stats` is now `Cauldron2D.Stats.worlds/0`, and its `arena()` type
  is `world()`.
* `Cauldron2D.Ledger.board/4` narrows to one world with `world:` (was `arena:`); an
  `arena:` option is ignored.
* `Cauldron2D.Ledger.record/4` stores the world's name on a row as `:label` (was
  `:arena`), so a `forget/2` predicate reads `row.label`. Rows recorded before still
  match `board/4`'s `world:`.
* `Cauldron2D.Ledger.Recorder` takes `:label` for the name results are kept under;
  `:arena` is still read when `:label` is absent.

### Added

* `Cauldron2D.Grid.Coarse.reachable?/3` and `spots/1`, and
  `Cauldron2D.Grid.Coarse.Space`, which measures positions across joined edges.
* A host is named `<name>@cauldron.host`, a name tied to none of its addresses, and
  `Cauldron2D.Distribution.join/3` points that name at the address given in its own
  host table, so a host is joined through any of its addresses (its home network's, a
  VPN's, `127.0.0.1` from the same machine).
* `Cauldron2D.Distribution.addresses/0`: every address of the machine's interfaces,
  private networks first and physical interfaces before virtual ones (a VPN's, a virtual
  machine's bridge). `address/0` is its first, so a host names itself on its home
  network rather than on whichever interface the system lists first.

* A player can ask for fewer frames than the world ticks: `Cauldron2D.World.join/4`'s
  `:frames` takes a number a second, and `Cauldron2D.World.frames/3`
  (`Cauldron2D.Player.frames/3`) changes it. The world builds a view only for a frame it
  sends, and each frame carries the events of every step since the last.

* `Cauldron2D.Distribution.join/3` says why a join failed: `:bad_address`,
  `:unreachable` (nothing answers at the address), `:not_hosting` (no such node there) or
  `:refused` (the node refused the code), where it said `:unreachable` for all.
* `Cauldron2D.Client.Game`: an `ask` of `{:menu, arg}` and the optional `open_menu/2`
  callback, so a world can ask a client to open a particular menu of the game's.
* `Cauldron2D.Audio.keyed/4` takes `music: true`: the sound's recording from the new
  `:recordings` option, played in its own channels as a looping stage music layer from
  its start, at the music level; `moved/2` sets its gain and `stopped/2` drops it.
* `Cauldron2D.Client.Game`'s optional `recordings/0`, passed to the audio by
  `audio_options/1`.
* `Cauldron2D.Audio`'s `:master` option, `:sfx` for the effects level to scale the music
  too; a game sets it through `Cauldron2D.Client.Game`'s `audio/0`.
* `Cauldron2D.Audio.muted/1`: the event that silences everything until another lets it
  sound again.

* `Cauldron2D.Loop.wait/2`: the milliseconds until the next step falls due.
* `Cauldron2D.DrawList.extent/2`: the rectangle an item's picture can cover.

* `{:gamemaker, mode}` drawing: a blend with GameMaker's factors applied to the alpha
  channel as well as the colours, as GameMaker draws onto a surface.

* `Cauldron2D.Blend` and `Cauldron2D.DrawList` draw with `mode: :subtract`, GameMaker's
  `bm_subtract`: each canvas channel times one less the picture's colour times its
  alpha.

* `Cauldron2D.Distribution`: play across machines over BEAM distribution. `host/2`
  names the VM `<name>@<address>` with a fresh join code as its cookie and calls on the
  local network; `join/3` connects to a host with its code; `stop/1`, `address/0`,
  `code/0`.
* `Cauldron2D.Worlds.world_name/2`: the name of a world on a connected node, started
  there on first use.

* Additive drawing: a draw item's or placement's `mode: :add` adds the picture's colour
  times its alpha to what is beneath (`Cauldron2D.Blend.draw/6`, `Cauldron2D.DrawList`).
* `Cauldron2D.Audio.keyed/4` takes `loop: true`: a voice playing a recording goes round
  it — its own loop, or the whole of it — until `stopped/2` lets it go.
* `Cauldron2D.Client.Game`'s optional `ask/1`: what the world asks of a player's client,
  `{number, :menu}` to open the game's menu or `{number, :quit}` to end the client,
  each number acted on once.
* `Cauldron2D.Audio.Music`: a piece with `render: :on_cue` renders a section only when it
  is cued and keeps only the playing section in memory, for pieces of whole recorded
  tracks.
* `Cauldron2D.Fit`: a frame of a fixed shape fitted into a picture of another, with
  bars, and the point of the frame under a picture fraction.
* `Cauldron2D.World.join/4` and `Cauldron2D.Player.join/4` take `frames: false` for a
  player that sends input and is sent no frames.
* `Cauldron2D.Client.Game` optional callback `local_seats/1`: further players on the
  same machine, a keymap each.

* `Cauldron2D.Blend.draw/6` draws a picture onto an RGBA canvas at a pixel position,
  with an origin, a scale per axis (negative mirrors), an angle, a blend colour and an
  alpha, in C where the library loaded and in Elixir where it did not.
* `Cauldron2D.Render.render/3`: a frame drawn once from a list of operations, each drawn
  by its shape (`{:sprite, picture, placement}`, `{:raster, picture, {x, y}}`), in
  bands of rows across the schedulers, in C where the library loaded. `:format` is
  `:rgba` or `:rgb`; `:background` is a colour or a picture the frame's size.
* `Cauldron2D.DrawList`: a frame as a list of pictures placed in world pixels, drawn
  greatest depth first through a view and a zoom into a raster for a `:picture` scene,
  leaving out items that cannot reach the frame.
* Collision by pixels: `Cauldron2D.Mask` (solid pixels, one bit each, from bits or from a
  raster's alpha), `Cauldron2D.Shape` (a rectangle or a mask placed with an origin, a
  scale and an angle), and `Cauldron2D.Overlap` testing shapes against each other, a
  point, a rectangle, a circle or a line.
* `Cauldron2D.Turn.cos_sin/1`, exact for whole quarter turns.
* Keyed sound events: `Cauldron2D.Audio.keyed/4` sounds a name under a key, replacing
  what sounds there; `moved/2` moves it and `stopped/2` lets it go. A keyed sound is
  placed again when the listener moves and when the effects level changes, and one past
  earshot keeps sounding at no level. They go to `Cauldron2D.Audio.play/2` with other
  events, as `Cauldron2D.Audio.Keyed` structs. A keyed sound given `{:level, gain, pan}`
  instead of a position plays at the game's own level, scaled by the effects level, and
  only `moved/2` changes it.
* `Cauldron2D.Client.Game` optional callback `audio/0`: `:voices` and `:earshot` for the
  game's sound, read with `Cauldron2D.Client.Game.audio_options/1`.
* A game's own menu, through optional `Cauldron2D.Client.Game` callbacks: `options/0` (the game's player options and defaults), `open_menu/1` and `menu_event/3` (the menu's state and its keys, mouse and controller buttons; it changes settings, plays sounds, sends the world numbered requests, or leaves), and `input_options/1` (`Cauldron2D.Input` options from the player's options). `Cauldron2D.Input.spec_of/1` turns a press into the key spec it binds.
* `Cauldron2D.Input` binds the wheel and the pointer's movement like tapped keys:
  `{:mouse, :wheel_up | :wheel_down}` and `{:mouse, :move_left | :move_right | :move_up |
  :move_down}`, each holding its actions for `:gesture_ms`. `Input.binds?/2` says whether
  a key spec is bound, and `Input.Pad.binds_axis?/2` whether a padmap binds a stick axis.
* Sector maps: `Cauldron2D.Sectors.Map` (rooms of any shape with their own floor and
  ceiling heights, joined by lines), `Sectors.Bsp` (front-to-back order and point
  location, read from a level or built from its lines), and `Sectors.View`, which draws one
  from inside it — walls with upper, lower and see-through middle pictures, perspective
  floors and ceilings, sky, and sprites clipped against the walls in front of them.
* `Cauldron2D.Sectors.Frame`: an indexed-colour picture drawn a column, a plane or a line
  at a time, in C with an Elixir fallback that draws the same
  picture; `Sectors.Pictures` holds the textures and light tables it draws from.
* `Cauldron2D.Sectors.Light`: light tables built from a palette, and which table a surface
  is drawn through at a light level and distance.
* Movement and sight through sector maps: `Sectors.Blockmap` (lines and bodies filed by
  block), `Sectors.Trace` (what a straight line crosses, nearest first), `Sectors.Move`
  (fitting, stepping up, drop-offs, sliding along walls), `Sectors.Sight`,
  `Sectors.Noise` (how far a sound carries through open doors) and `Sectors.Automap`.
* `Sectors.Overlay`, a picture drawn flat over the view, for a held weapon or a status bar.
* `Cauldron2D.States` (state tables: a picture, a duration, an action and the next state),
  `Cauldron2D.Thinkers` (things that change by themselves each tick, in a fixed order) and
  `Cauldron2D.Steer` (choosing one of eight directions toward a target round obstacles).
* `Cauldron2D.Client.Game` scenes take a `:picture`, a raster the game draws itself.

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

* The compiled native code is built into and loaded from
  `priv/native/<system architecture>` (`Cauldron2D.Native`) instead of `priv/`, so builds
  for macOS and Linux in one checkout no longer overwrite each other.

* `Cauldron2D.Surface.compose/4` draws its grid, movers and labels, and
  `Cauldron2D.Parallax.compose/3` its layers, through `Cauldron2D.Render.render/3`;
  the pictures are the same.
* `available?/0` of `Blend`, `Projection.Ground`, `Projection.Volume.Native` and
  `Sectors.Frame` reports whether the C library loaded.
* Effects reach the stage through `TuningFork.Stage.play_pcm/3`: a process standing in
  for the stage in a test receives `{:play_pcm, pcm, opts}`, `opts` empty for an
  unkeyed sound.
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

### Fixed

* `Cauldron2D.Distribution.join/3` accepts a host's code through any of the host's
  addresses, not only the one in its name.
* `Cauldron2D.World.join/4` refuses an id another process already plays as, with
  `{:error, :taken}`, where it gave that id to the newcomer and left the first process
  without its player.

* `Cauldron2D.World` times its next tick once the last has run, for when the next step
  falls due, so its mailbox never holds more than one tick. A world whose steps take
  longer than their time no longer queues ticks ahead of input; input waits at most one
  tick, and steps past `Cauldron2D.Loop`'s `:max_steps` are dropped.

* `Cauldron2D.Input` without key releases: a tapped key lets go after its tap window
  on a clock that reads below zero, as the BEAM's monotonic clock does. A tapped key
  stayed held for good.
* `Cauldron2D.Blend` and `Cauldron2D.Render` never write or read outside a picture: a
  placement with a huge or non-finite position, origin, scale or angle draws nothing
  beyond the frame's edges, negative and zero sizes are refused, and sizes are checked
  without overflowing.
* `:alpha` is held to `0.0`–`1.0` and each `:blend` channel to `0`–`255`, the same in C
  and in Elixir.
* `Cauldron2D.Render.render/3` raises `ArgumentError` for a picture or background of
  the wrong size and for a colour that is not four values in `0..255`.
* `Cauldron2D.DrawList` keeps a picture whose origin lies outside it when the picture
  lands in the frame.
* `Cauldron2D.Surface.compose/4` keeps the colour of the grid's see-through pixels.
* `-ffp-contract=off` is kept when `CFLAGS` is set in the environment, so C and Elixir
  draw the same pixels.
