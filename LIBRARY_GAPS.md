# Library gaps

Where Cauldron stands on 2026-10-21 against three questions: what it offers that its
documentation does not tell a game author; what a good 2D game library provides that
Cauldron does not; and what every game is made to take on versus what it can choose.
The last part covers configuration, which is spread across environment variables with
no common rule.

Paths are relative to this directory. `examples/` are the seven example games.

## 1. Documentation

Every package has a README and every public module a `@moduledoc`. The gaps are in what
the READMEs name, a handful of statements that are wrong, and "how do I…" answers that
exist only inside long moduledocs.

### Wrong or out of date

| Statement | Where | What is true |
|---|---|---|
| QOI texture pages are not read (`{:error, {:unsupported_encoding, :qoi}}`) | `cauldron_2d_gamemaker/README.md:123-125` | `Texture.decode/1` decodes `:qoi` and `:bz2_qoi` (`cauldron_2d_gamemaker/lib/cauldron_2d/game_maker/texture.ex:41-44`) |
| GameMaker 2022 and later layouts are not read | `cauldron_2d_gamemaker/README.md`, Limits | `Runtime` detects the 2022 LTS and 2024 layouts |
| Depend on `~> 0.2` | `README.md:96-98` | every package is 0.3.4; `cauldron_2d/README.md` says `~> 0.3` |
| `cauldron_3d_formats` reads the Quake family | `README.md` 3D section, `cauldron_3d_formats/README.md` | it also reads glTF and VRM (`Gltf`, `Gltf.*`, `Vrm`) |
| The terminal client draws on the graphics card "when the player asks for it", and games offer `--gpu`/`--window` | `cauldron_gpu/README.md` | the card is used by default (`cauldron_2d_drafter/README.md`); the switch is `--picture …,window`; only courtyard has `--gpu`/`--window` |
| `Client.Game`'s `worlds/0` | `cauldron_2d/lib/cauldron_2d/worlds.ex:15` | the callback is `worlds/1` |
| The default look cycles "all three" projections, and the look has a `density` | `cauldron_2d/lib/cauldron_2d/client/game.ex:148-149` | five projections are listed; `density` is not a look key |
| The scene type: movers are `{art, {x, y}}` | `cauldron_2d/lib/cauldron_2d/client/game.ex:226-243` | movers also take a heading and a tint map (`cauldron_2d_drafter/lib/cauldron_2d/drafter/surface.ex:32`); the type omits `:gpu_size` |
| `Game.input` is `held`, `aim`, `strength`, `heading` | `cauldron_2d/lib/cauldron_2d/game.ex:51-56` | the client also sends `:options` and `:request` |
| The scene keys are `:labels`, `:volumes`, `:layers`, `:heading` | `cauldron_2d/README.md` | also `:screen`, `:subject`, `:native`, `:gpu_size` |
| The findings are in `GAP_ANALYSIS.md` | `STATE.md:4` | that file is `../dev_docs/GAP_ANALYSIS.md` |
| NxDiffusion Studio at `../../../ai/nx_diffusion_studio` | `cauldron_2d_assets/README.md:3` | a path on one machine |

### Offered, but named in no README

- **Menus and screens drawn by the game:** `Menu`, `Menu.Item`, `Menu.Layout`, `Screen`,
  `Front`, `Client.Hud`. Every game with its own title, pause menu or hud uses these;
  they are listed only in `cauldron_2d/CHANGELOG.md`.
- **Networked play without distribution:** `World.Rollback`, `Link`, the `:rollback`
  and `:join_props` world options, per-player frame rates (`World.frames/3`).
- **Atlas detail:** poses (`:front`, `:back`, `:side`), faces, storey height,
  `:stand`/`:eye`, fonts, frame cutting, and the column format of `atlas.txt`
  (`Atlas.Manifest`).
- **Audio detail:** `Audio.Recording`, the `{:pcm, binary, rate, channels}` music
  form, `:static_music`.
- **Text-mode and helper projections:** `Projection.Glyphs`, `Projection.Ground`,
  `Projection.Canvas`.
- **Picture tools in linocut:** `Linocut.Pixelate` (the asset pipeline's finishing),
  `Linocut.Slices` (nine-slice panels), `Linocut.BitmapFont`; and the options of four of
  its five mix tasks.
- **3D:** `Cauldron3D.SpringBones`, `Cauldron3D.WalkGrid`, `Cauldron3D.Scene.Gltf`.
- **The asset manifest:** `from:` edits, `video:` and `rig:` animations, `:finish`,
  `:fit`, `:outline`, and the `--only`, `--manifest`, `--out` flags
  (`cauldron_2d_assets/lib/cauldron_2d/assets/manifest.ex` only).
- **The GameMaker runtime:** `Runtime.Audio`, `Curves`, `Extensions`, `Fonts`,
  `Functions`, `Objects`, `Particles`, `Pictures`, `Rooms`.
- **Packages missing from the root README:** `cauldron_3d_kino`, `cauldron_3d_scene`;
  and `cauldron_examples/3d/courtyard`, the one example of a game drawn on the graphics card.

### Questions the documentation does not answer

- **How a player switches between pixels and characters.** The terminal client picks
  kitty, iTerm2 or sixel images where the terminal shows them and characters elsewhere.
  A player switches on the settings screen (the Display and Drawing rows) or with the
  `display` key, which is unbound until a game binds it. `CAULDRON_MODE` forces a
  protocol or text. None of this is in a README; the display values are only in the
  `Settings` typedoc and `CAULDRON_MODE` only in the `Renderer` moduledoc. Nothing warns
  that a game which unbinds the settings key and leaves `display` unbound — beast — has
  taken every way to switch away from its players.
- **How sprites face and mirror.** A mover's heading picks a pose and mirrors it; the
  rule is spread over `Atlas.put/4`, `Surface`, `Client.Game` and the drafter `Surface`.
- **How to animate by state** (walk, strike, idle): frames loop on the clock, and
  choosing a frame from a state's age is left to each game.
- **How to build a menu, a hud on `:screen`, or a title with `Front`.**
- **How the sector-map engine fits together** (`Sectors.*`, 14 modules).
- **Which picture options apply to which game.** `native`, `png`, `swap`, `gpu` and
  `window` act on a scene with `:picture` or `:gpu`; a tile-surface game has only the
  display choice.

### Reference structure

- `cauldron_2d/mix.exs` has no `groups_for_modules`: hexdocs lists 113 modules flat.
- The 31 optional `Client.Game` callbacks are one bullet list in the moduledoc, with no
  `@doc` each and no index.
- The root has design and history documents (`STATE.md`, `ENGINE_ADDITIONS.md`,
  `GAMEMAKER_DESIGN.md`, `GAMES_OVERHAUL.md`, `THE_TOWER.md`) that `README.md` neither
  links nor marks as internal.
- No License section in `cauldron_2d_assets`, `cauldron_3d_kino`, `cauldron_3d_net`,
  `cauldron_gpu`, `cauldron_3d_scene`.

## 2. Engine features against other 2D libraries

The comparison is with what Godot 2D, Phaser, HaxeFlixel, LÖVE with its common
libraries, Bevy 2D, MonoGame and Defold give a game.

Cauldron is as strong as those, or stronger, at networking (authoritative worlds,
lockstep, rollback, `Link`, `Beacon`), replays and determinism (`Rng`, fixed tick,
`checksum`), input and rebinding, audio (positional, keyed, sectioned music), menus and
on-screen items, pathfinding (`Grid.Path`, `Grid.Coarse`, `Route`, `Steer`, `Robot`,
`Grid.Fov`) and the asset pipeline.

It is weak at gameplay: moving things, hitting things, timing things. The library's
versions are thin, and none of the examples uses them — no example calls `Body`,
`Collision`, `Collision.Buckets`, `Overlap`, `Particles`, `Camera.Follow`, `States`,
`Thinkers` or `Loop`. Each game writes its own.

### Projectiles

Not in the library. Beast and megablast each have a full system:

- **beast** — one `missiles` list fed by creature and boss shots; `Beast.Game.fly/4`
  moves arcing seeds, homing orbs and straight arrows; a missile goes when it enters
  rock, leaves the region or ages 5 s; `Beast.Combat.wounds/1` and `broken/2` settle
  hits.
- **megablast** — player volleys and homing in `Megablast.Weapons`, enemy bullet
  patterns (aimed, ring, fan, rain) in `Megablast.Pattern`, movement and culling in
  `Megablast.Game`, piercing hits and the hit-once list in `Megablast.Combat`.

The two share their shape: straight motion `x + vx·dt`; homing
`v += (dir·speed − v)·min(1, k·dt)` (beast k 1.2, speed 3.5; megablast k 4, speed 16);
removal by bounds, tiles and age; a set of what each shot has already hit.

### Collision

`Collision` sweeps circles against a tile grid without one-way platforms; `Shape` and
`Overlap` test pixel masks and rectangles in world pixels. The games work in float
tile units with boxes, so each writes its own: beast boxes and missile boxes
(`cauldron_examples/games/beast/lib/beast/combat.ex`), `Body.covers?` for pickups and its own box body
with one-way platforms (`cauldron_examples/games/beast/lib/beast/body.ex`); megablast a square distance
test (`cauldron_examples/games/megablast/lib/megablast/combat.ex:233`); cistern interval tests for drops
in jars. All of them test every pair; none uses `Collision.Buckets`.

### Area by area

| Area | Library | Written by the games |
|---|---|---|
| Bodies and movement | `Body`: a point with heading, thrust, gravity, drag, wrap. No box body, platform movement, coyote time or jump buffer | beast's box body and variable jump; town and parade share line-for-line walking code; courtyard a variant |
| Collision | circles against tiles, pixel masks, a broad phase; ray casts only on sector maps | every game, as above |
| Projectiles | none | beast, megablast |
| Hitboxes and frame data | none | beast `Moves`, `strike/1`, `hurtbox/1`, the `landed` set |
| Effects | `Particles` (no emitters, no colour or size over life); shake in `Camera.Follow`; no hit-stop | blasts, splashes, pops, bolts aged by hand; hit-stop in beast (seconds) and megablast (steps); shake written twice |
| Animation | frames on the clock; `States` counted in ticks; no easing | frames chosen from age by hand in three scenes; `{state, t}` by hand across beast |
| Timers and cooldowns | none | about ten `max(0.0, x - dt)` fields per game |
| Camera | `Camera`, `Camera.Follow`, parallax; no bounds or deadzone | beast clamps by hand |
| Levels | `Map` (text grid), sector maps, GameMaker rooms; no Tiled or LDtk | town and parade parse their own legends |
| Input | keymaps, pads, rebinding; no pressed/released this step, no buffering | five games compute `held − last` by hand |
| Entities | plain maps; no id allocator | `serial` counted by hand; `replace/2` in two games |
| High scores | `Ledger` exists | `scores.ex` near-identical in beast, megablast and cistern_complete, reading its file with `Code.eval_string` |

### What to add

Each is a module a game may call or ignore. None changes the `Cauldron.Game` contract;
all work on plain values carried in the game state, as `Rng` and `Tuning` do. Ordered
by how much duplicated code each replaces.

1. **`Cauldron2D.Projectiles`** — a list of shots, each with position, velocity, motion
   (straight, arcing under gravity, homing at a speed and turn rate), time to live,
   damage, owner, whether it pierces, and what it has hit. `step/3` moves them and drops
   those out of bounds, inside solid tiles or expired; `hits/3` returns the hits and the
   shots left, hitting each target once.
2. **`Cauldron2D.Projectiles.Pattern`** — aimed, ring, fan, spiral and rain volleys.
3. **`Cauldron2D.Box`** — boxes in tile units: overlap, contains, from a centre, the
   tiles under a box; collision layers and masks; boxes in `Collision.Buckets`.
4. **A box body against tiles** — moves each axis apart, lands on one-way platforms only
   from above and can drop through them, follows diagonal tiles as slopes, reports
   whether it stands on ground. `Collision` learns the `:platform` tile.
5. **`Cauldron2D.Jump`** — coyote time, jump buffer, held-jump height, fall-speed cap,
   with the numbers from `Tuning`.
6. **Pressed and released per step, and buffering** — in `Input`, or added by the world
   to the input map for games that want it.
7. **`Cauldron.Timers`** — named countdowns: start, step, done, left.
8. **`Cauldron.Impact`** — hit-stop (time slowed for a moment) and shake that replays
   the same way, usable without a follow camera.
9. **`Cauldron.Moves`** — strike frame data: wind-up, active and recovery times, the
   box a strike covers relative to facing, damage and knock-back, hit-once per strike.
10. **Steering** — seek, arrive, flee, homing and wander in `Steer`.
11. **`Cauldron2D.Walk`** — direction from held actions, analog strength, movement
    relative to the camera, sliding along walls.
12. **`Cauldron.Effects`** — sprites that play once and go; emitters and colour or size
    over life in `Particles`.
13. **Timed states and easing** — `States` in seconds with a frame chosen by time in the
    state; `Cauldron.Ease` and a tween value.
14. **`Cauldron.Scores`** — a local high-score table with initials, stored as terms, on
    `Ledger`, with an initials menu item.
15. **Camera bounds and deadzone, a tile ray cast, a debug item that outlines boxes, and a
    Tiled/LDtk reader into `Map`** with object layers for spawn points.

## 3. Forced on every game, and what it can choose

### Callbacks

`Cauldron.Client.Game` has 43 callbacks: 12 required, 31 optional.
`Cauldron.Game` has 7 required and 4 optional. The required ones include several that
most games fill with the same body:

| Body | Games |
|---|---|
| `toggles, do: []` | 6 of 7 |
| `chat?, do: false`, against a default of `true` | 6 of 7 |
| `listener(%{me: nil}), do: nil` | 6 of 7 |
| `scene(view), do: scene(view, …)` — `scene/1` is required even when `scene/2` exists | 5 of 7 |
| `outcome(view), do: Game.outcome(view)` | 5 of 7 |
| silent `sounds`, `music []`, `cue → nil` | 3 of 7 |
| `hud(_view), do: []` | 3 of 7 |
| the same `client_keys/0` map, word for word | 3 of 7 |
| `leave/2` as `Map.delete` (world) | 7 of 7 |

Defaults for optional callbacks are literals at each call site in each front end
(`optional(game, :chat?, [], true)` and the like), not one table.

### Behaviour the terminal client imposes

- **Screens.** A game can replace the title and summary (`fronts/1`) and skip title or
  lobby (`start/0`). It cannot replace the settings or guide screens.
- **The settings screen is fixed:** preset, bindings, pointer, effects, music, display,
  drawing, frame rate. A game cannot choose items or add its own; its only switch is to
  unbind the key, which hides all of them. The display and frame-rate values are private
  (`cauldron_2d_drafter/lib/cauldron_2d/drafter/client/settings.ex:68-71`), so a game
  cannot rebuild those rows in its own menu.
- **A frame rate chosen in a game's own menu is saved but not applied.** Settings
  changed through a game menu go through `put_settings`
  (`cauldron_2d_drafter/lib/cauldron_2d/drafter/client.ex:1091`), which never calls
  `apply_frame_rate`; only the built-in screen does (`client.ex:1060-1066`).
- **Always started, whatever the game says:** chat (`Chat.ensure_started` and its joins,
  with chat off), session tracking and presence, an audio process (for silent games
  too), and in `cauldron_2d` itself Atlas, Presence, Sessions, Events, Worlds and a
  sweeper. Chat is started unsupervised.
- **Default look** cycles top, iso and first person: a game that omits `look/0` offers
  views it may not support.
- **Fixed:** the initial refresh rate, the rule `:auto` frame rate follows, `^Q`/`^C`.
- **Settings files** go to `$XDG_CONFIG_HOME/<title slug>/`. The desktop client and the
  server name their files after the atlas, the browser keys localStorage by the atlas,
  music is cached under `home/0`. The two cistern examples share the title "CISTERN"
  and so share a settings folder.
- **The server** broadcasts a beacon and starts distribution unless told not to.

### Front ends that ignore a game's choices

The desktop (`cauldron_2d_wx`) and browser (`cauldron_2d_net`) clients read `lobby?`,
`pages`, `steering`, `guide`, `opening` and `join_props`. They ignore `start/0`,
`fronts/1`, `client_keys/0`, `look/0`, `options/0`, `open_menu`/`menu_event` and
`chat?`. Beast's title, summary and pause menu exist only in the terminal, and nothing
says so. Section 6 gives where this stands now.

### What to change

- **`use Cauldron.Client.Game`** defining the common bodies above as overridable
  defaults, so a game writes only what differs. Required callbacks drop to `title`,
  `atlas`, `actions`, `keymaps`, `worlds` and one `scene`. The same for
  `Cauldron.Game`: `leave/2` and `drain_events/1`.
- **Defaults in one place**, read by every front end.
- **Chat, presence, sessions and audio start only when the game uses them**; chat
  defaults to off and is supervised.
- **Settings items the game chooses**, and menu items for display, drawing and frame
  rate (`Menu.Item.display/0` and the like) so a game's own options menu can offer them.
  `put_settings` applies the frame rate.
- **One storage name per game:** `home/0`, in every front end.
- **Every front end honours the same callbacks,** or each callback's documentation names
  the front ends that read it.
- **Beacon and distribution opt-in** on the server.

## 4. Configuration

### What is read today

| Knob | Where | Also an option? | Order |
|---|---|---|---|
| `CAULDRON_MODE`, `config :cauldron_2d, :mode` | `cauldron_2d/lib/cauldron_2d/renderer.ex:86,92` | yes | argument > env > app env |
| `CAULDRON_AUDIO` | `cauldron_2d/lib/cauldron_2d/audio.ex:464` | `:mode` | **env > argument** |
| `CAULDRON_TRACE` | `cauldron_2d/lib/cauldron_2d/trace.ex:163` | no | env |
| `config :cauldron_core, :sweeper` | `cauldron_core/lib/cauldron/application.ex:17` | no | undocumented |
| `config :cauldron_core, :beacon_port` | `cauldron_core/lib/cauldron/beacon.ex:32` | `:beacon_port` | |
| `CAULDRON_PICTURE`, `config :cauldron_2d_drafter, :picture` | `cauldron_2d_drafter/lib/cauldron_2d/drafter/client/picture.ex:89-90` | `:picture` | prop > app env > env > look |
| `CAULDRON_MUTE`, `config :cauldron_2d_drafter, :mute` | `cauldron_2d_drafter/lib/cauldron_2d/drafter/client.ex:2239-2249` | `:mute` | prop > app env > env |
| `NX_STUDIO_URL`, `NX_STUDIO_TOKEN`, `config :cauldron_2d_assets, :studio` | `cauldron_2d_assets/lib/cauldron_2d/assets/studio.ex:49,55` | no | app env > env |
| `config :quake_c, :cache_dir` | `quake_c/lib/quake_c/compiler.ex:74` | no | |
| `CAULDRON_ASSETS` | `cauldron_examples/3d/courtyard/lib/courtyard/assets.ex:29` | no | |
| `MEGABLAST_SCROLL`, `MEGABLAST_SHIELDS` | `cauldron_examples/games/megablast/config/runtime.exs` | overrides | |
| `BEAST_RUN`, `BEAST_LIVES`, `config :beast` | `cauldron_examples/games/beast/config/` | — | **read by nothing**; its numbers disagree with `Beast.Tuning` |
| `PLUMB_HEX` | every `mix.exs` | no | path or hex dependencies |

Three knobs, three different orders: the environment beats an explicit argument for
audio, the application env beats the environment for pictures and the Studio, and the
environment beats the application env for the renderer.

The example games' mix tasks copy one ten-line runner and accept only `--name`, so
mute, picture, start and the rest can be set only through the environment.
`Cauldron2D.Drafter.Launcher` already resolves values in layers (flag, saved launcher
file, discovery, default), but only its own README uses it.

### What to change

- **One resolver, `Cauldron.Launch`, with one order for every knob:** explicit option
  or prop, then the game's launch file, then the environment, then application config,
  then discovery, then the default. An explicit option can no longer lose to the
  environment.
- **Every environment variable also an option** — audio mode, trace, sweeper, the Studio
  address and token.
- **A launch file per game** at `$XDG_CONFIG_HOME/<home>/launch.config`, extending the
  launcher's file: front end, picture, mute, start, name.
- **`mix cauldron.play MyGame.Client`** with `--name --mute --picture --start --front
  terminal|desktop|browser`, built on `Cauldron.Launch`, in place of the copied
  runners.
- **One reference section** in `cauldron_2d/README.md` listing every knob, its option,
  its variable and its order.
- **Beast's dead configuration** removed, or fed into `Beast.Tuning.new/1`.

## 5. Order of work

1. Fix the wrong statements in section 1 and the frame-rate bug in section 3; they
   mislead or break today.
2. `Cauldron.Launch` and `use Cauldron.Client.Game`: every later module and front
   end builds on one way of configuring and one table of defaults.
3. The opt-in changes to the terminal client (chat, audio, presence, settings items,
   storage name).
4. Gameplay modules 1–9 from section 2, each moved into the library from the example
   that has it and the example rewritten to use it, so the module is proven by a game.
5. The remaining gameplay modules, then the documentation additions: README sections
   for menus and screens, rollback, facing, animation by state, display switching; module
   groups on hexdocs; an index of the root documents.

## 6. Where each item stands

Built, and used by the example games (`STATE.md`, "Library gaps: first round"): every
wrong statement in section 1; the frame-rate fix; `Cauldron.Launch` and the shared
runner; `use Cauldron.Client.Game`; chat started only for games with chat; one storage
name per game; menu rows for display, drawing and frame rate; the front-end table in
`Cauldron.Client.Game`; and from section 2's list, items 1–9, 11, 12 (one-shot effects)
and 14.

Also built: `Steering` (seek, flee, arrive, pursue, evade, wander, separation), `Ease`
and `Tween`, `States` counted in seconds, `Grid.Ray`, a scene's `:outlines`,
`Map.Tiled` and `Map.Ldtk`, `Particles.Emitter`, camera bounds in `Camera` and a
deadzone in `Camera.Follow`; and the README sections on menus and screens drawn by the
game, rollback and `Link`, sprite facing, animation by state and the `atlas.txt` format.

**The terminal, the desktop and the browser are one client.** All three draw a scene with
`Cauldron2D.Draw`, so a game's layers, projections, `:screen`, `:outlines` and menu
look the same in each. All three read the game through the same modules of
`cauldron_2d`: `Cauldron.Client.Fronts` (the game's own title and summary),
`Client.Menus` (its menu), `Client.Look` and `Client.Keys` (the look and the client's
keys), `Client.Start` (`start/0`), `Client.Seats` and `Client.Controllers` (players and
controllers on one machine), and `Cauldron.Chat` (the lobby and world rooms, shared
across front ends). The browser and the desktop run the player's client on the server
side (`Client.Stage`, `Client.Controls`, `Client.Party` in `Cauldron.Net.Session`)
and send it raw input, so `fronts/1`, `open_menu`/`menu_event`, `client_keys/0`,
`look/0`, `options/0`, `start/0` and `chat?/0` work in every front end. A server chooses
whether it draws pictures for its clients or sends them scenes to draw
(`Cauldron2D.Net.Drawing`); the browser draws scenes with a JavaScript copy of `Draw`
checked against it byte for byte. The callbacks some front ends have no use for,
`holds/0` and `sink/1`, are named in `Cauldron.Client.Game`'s moduledoc.

Open:

* **Each front end's own screens.** The lobby, settings and guide are each front end's
  own: a game replaces the title and summary, not those.
* **Opt-in audio and presence.** Audio still starts for a silent game, and session
  tracking and presence still run for games without a lobby.
* **Documentation** not yet written: a README section on the sector-map engine; the
  remaining README gaps in linocut, `cauldron_2d_assets` and the GameMaker runtime
  modules.
