# Overhauling Megablast, Beast and Cistern

Status: **in progress.** The shared work (A, B) is built for the terminal client;
Cistern is rewritten as the tutorial's game, `cauldron_examples/games/cistern_complete` is the finished
game, and Megablast and Beast are rewritten. What remains is listed under each part.

## Why the three are weak

1. The front ends draw every title, menu, settings page and summary themselves, in one
   fixed look. A game cannot draw its own. NidhOX, Half-Life, Doom and Quake each draw
   their own menus; an engine should never decide how a game's menus look.
2. The hud is rows of text runs; the only pixel font is `Linocut.Font` at 3×5.
3. No feel: no hit-stop, no hit flash, no shake in use. Beast and Megablast make no
   sound effects; Beast has no music.
4. The art is hand-typed `.pic` files of 16–24 pixels with ten colours.
5. They were built code-first, with no design behind them: Beast's runner cannot
   fight, Megablast cycles six wave shapes forever with no bosses, shop or weapons, and
   Cistern does not explain itself.

## A. Menus and huds: tools in the engine, the look in the game

The engine provides the parts; the game decides how they look. A stock look ships as
an example a game can opt into, so a game that does not care does no extra work.

* **Screen flow** — title, lobby, settings, guide, pause, summary, and the moves
  between them, as data the game can use as given, change, or replace.
* **Menu behaviour** — focus, moving between items, choosing, going back, key
  rebinding, sliders and toggles bound to settings, saving them. No drawing.
* **Drawing is the game's** — every screen is a scene the game draws with its own
  atlas, font and music, as `scene/1` already is.
* **Parts to draw with** — bitmap fonts loaded from the atlas (glyph strips, any size),
  nine-slice panels, bars, icon and digit strips, text with outlines and shadows.
* **The stock look** — one module that draws every screen and the hud from those
  parts, used by a game that names it and copied by a game that wants to start from it.
* **Attract mode** — `Cauldron.Replay.Viewer` playing a recorded run behind a title.
* **High scores** — initials entry, kept through `Cauldron.Ledger`.
* **Feel** — hit-stop (freeze N ticks), a flash tint per mover, shake through
  `Cauldron2D.Camera.Follow`, bursts through `Cauldron2D.Particles`.

### Built

* `Cauldron.Menu` and `Cauldron.Menu.Item` — menu behaviour: pages, cursor,
  toggles, choices, sliders, key binding, typed text, yes/no prompts, the game's own
  actions working the menu; answers `open_menu/1` and `menu_event/3` as they are.
* `Cauldron2D.Menu.Layout` — a menu as screen items in the game's own font, panel,
  cursor, slider art and colours.
* `Cauldron2D.Screen` — a scene's `:screen`: art, text, nine-slice panels, bars and
  fills fixed to the pane by anchor and pivot.
* `Linocut.BitmapFont` (pixel fonts from a sheet, proportional, aligned, wrapped,
  outlined, shadowed), `Linocut.Slices` (nine-slice), fonts on the atlas
  (`Atlas.put_font/3`, `Atlas.load/3`'s `:fonts`).
* `Cauldron.Front` and the client's `fronts/1` — a title or summary the game draws
  and runs itself, with the client keeping the moves between screens.
* A mover's `:tint` (`{art, pos, heading, %{tint: name}}`) for flashes.
* The terminal client draws all of it in every mode: pixels, kitty placements, block
  and braille cells, and glyphs.

### Still to build

* The browser client (`cauldron_2d_net`) and the window client (`cauldron_2d_wx`):
  `:screen`, `fronts/1` and mover tints. Neither draws parallax layers or `:picture`
  scenes yet either.

## B. Asset generation in nx_diffusion and the Studio

Already there: FLUX.2 klein edits with references, SDXL with canny, depth and tile
ControlNets, BiRefNet background removal, LoRA merging in the library, the FLUX.2 LoRA
trainer, upscalers, ACE-Step with stem extract, add, repaint and extend, Wan VACE with
references, Hunyuan3D and TRELLIS.2 with painters, Qwen3-TTS.

To add:

| Piece | What it does |
|---|---|
| Pixel-art finishing | find the real pixel grid and sample to it, quantise to a fixed palette with optional ordered dither, hard alpha, optional outline; writes a PNG `Cauldron2D.Atlas.load/3` reads |
| Style LoRAs in `generate_image` | the library merges them; the Studio does not take them yet |
| A style LoRA per game | trained on that game's first approved assets, so the rest match |
| Seamless tiling | circular padding in the UNet and VAE, for panoramas with `wrap: :x` and repeating walls |
| OpenPose ControlNet for SDXL | poses frames by skeleton |
| Animation from video | VACE clip of a character on a plain ground, background removed per frame, frames chosen, loop ends matched, pixel-art finishing, a strip |
| Animation from 3D | concept → mesh → fixed angles rendered in `cauldron_gpu` → pixel-art finishing; for ships, turrets, banking |
| Sound effects | port ThinkSound (pwilkin/thinksound.cpp is a GGML port for CUDA, Vulkan and ROCm, no Mac); an sfxr-style generator in `tuning_fork` for arcade sounds |
| Character voices | OpenMOSS TTS (pwilkin/openmoss) for cloning and designed voices, beside Qwen3-TTS |
| Loopable music | ACE-Step track, seam repainted, split into stems that become `Cauldron.Audio.Music` layers |
| An asset manifest per game | `assets.exs`: prompt, model, seed, size, palette, frames, finishing; `mix cauldron.assets` queues it through the Studio and writes `priv/art` |

Check each model's licence before it ships in a game.

### Built

* `Linocut.Pixelate` — background keyed from the picture's edge (flood fill, enclosed
  pockets, blended fringe), the model's pixel grid found at fractional sizes and
  sampled, palette, ordered dither, outline, trim, fit.
* `cauldron_2d_assets` — `assets.exs`, `mix cauldron.assets` and
  `mix cauldron.assets.pick`: candidates asked of the Studio over its MCP HTTP API,
  sheets to choose from, a lock that rebuilds without asking again, edits of a chosen
  picture (`from:`, FLUX.2 instruct) so a character stays itself across poses, and
  animations from video (`video:`, Wan VACE from the chosen picture, frames finished on
  one grid and palette into a strip).
* `Atlas.load/3`'s per-art `frame:` for strips of any frame size.
* Music: whole ACE-Step songs, a section each, played through and started again, held
  in memory only while playing (`render: :on_cue`). Each game has a main theme for its
  title and summary; its other songs are `cover_music` versions of that theme in other
  styles, so every song is complete and different and the theme runs through them all.
  A tempo-locked dance genre makes the planner write a loop; those themes are written
  with the planner off and the sections spelled out.

### Still to build, in nx_diffusion and the Studio

* Style LoRAs in `generate_image`, and a per-game style LoRA from its first assets.
* Seamless tiling (circular padding); the games mirror a picture to repeat it meanwhile.
* An OpenPose ControlNet for SDXL.
* Sound effects from a model: a ThinkSound port; the games synthesise theirs.
* OpenMOSS voices, for The Tower; Fish Audio Drama 3 beside it, for spoken direction
  tags (its community licence needs "Built with Fish Audio" and a paid licence above
  US$500,000 a year).
* MOSS-Image (5B, FLUX.2 VAE, layout boxes, lettering) in `generate_image`, tried
  against FLUX.2 klein on backdrops and title paintings once its licence is confirmed;
  klein stays for edits.
* UniForge3D in `make_3d`, from a few views of a chosen picture drawn by klein edits,
  for ships and turrets rendered at roll angles.

These change the Studio that is running and the nx_diffusion repository, which holds a
large body of uncommitted work, so they are left for a session working there.

## Megablast — a Bitmap Brothers vertical shooter

References: Xenon 2 Megablast, Raptor, DoDonPachi, Ikaruga, Sine Mora.

* Five authored stages of about three minutes, each a timeline of spawns by depth.
* A mid-boss and a multi-part boss per stage, with phases, on `Cauldron.States`.
* The brake that holds the scroll back stays.
* Kills drop credit; a shop between stages with an animated trader sells spread,
  laser, homing, rear and side guns, speed, drones and bombs.
* A chain multiplier; a hitbox smaller than the ship; bullets in bright magenta and
  cyan with dark edges.
* Hit-stop on kills, flash on hits, shake on boss hits, particle explosions.
* Chrome logo, attract mode, high-score table; a bevelled metal hud frame.
* Chitin and chrome in 32 colours. Ship and turrets from 3D; creatures as short loops;
  walls from tiling textures and an autotile set; bosses as large multi-part sprites.
* ACE-Step acid-house breakbeat at 125 bpm, a track per stage and one for bosses, as
  stems; sfxr-style effects.

## Beast — a cinematic action-platformer

References: Shadow of the Beast for the look, Another World and Flashback for
rotoscoped motion and wordless story, Blasphemous and Hollow Knight for melee, Dead
Cells.

* One hand-built world in four regions: the red plain, the well and caverns, the great
  tree, the mage's castle. Parallax runs outside, rooms underground.
* Punch and kick combos, a charged blow, duck and dodge. Every enemy shows its attack
  before it lands and has a counter. Health, not three lives.
* Keys and items open the way; a boss ends each region.
* The story told in a few painted, wordless panels from Studio storyboards.
* Painted parallax layers made one at a time, tiling in x, lengthened with `extend`,
  background removed, pixel-art finished. Characters rotoscoped from video.
* An ethereal Amiga-style score per region; wind, cave and creature sounds.

## Cistern — a catching game in the line of Kaboom!

Kaboom! (Activision, 1981) is the catching game done right. A villain with a face moves
along the top and drops bombs; the player's stack of buckets catches them; the pace
climbs wave by wave; a miss costs a bucket and sets the pace back a wave, so a player
who is losing gets a breather instead of a death spiral. Cistern takes that structure
and makes it its own.

### The game

A hill town in drought; the cistern under the square is dry. A storm has come — the
**Squall**, a cloud with a face and a temper — but it will rain anywhere except where
it is wanted. The player is the keeper, carrying **three clay jars on a yoke**.

* **The yoke.** The jars hang side by side, so the yoke is three jars wide. A miss
  breaks an end jar and the yoke gets narrower: the player sees exactly how much harder
  it has become. A stretch of clean catching earns a jar back.
* **Catching.** Every falling drop casts a shadow on the jars' row, growing as it
  nears. A caught drop splashes into its jar, which fills visibly.
* **Pouring** (the complete game). A jar holds five drops; a drop into a full jar
  spills and counts as a miss. Full jars are emptied by standing over the cistern's
  grate and pouring, while the rain keeps falling. Catching is one skill, choosing when
  to run for the grate is the other. The score is the water in the cistern.
* **The Squall's moods** (the complete game). Each mood is a pattern the player learns
  to read from its face: *drizzle* (slow and steady), *gust* (a fast sweep spraying a
  line of drops), *sulk* (it stops, swells, and bursts), and in later storms *hail*
  (dodge it; a hit cracks a jar) and *lightning* (a column flickers, then strikes; get
  out of it). It grins at a miss and pouts at a streak.
* **Storms.** A filled cistern ends a storm; the next is faster and moodier. A miss
  sets the pace back one step, as Kaboom! does.
* **Versus** (the complete game). Each player, robot included, has their own square
  and their own Squall, side by side, with the same seed. A pour of three full jars
  sends a gust to the rival's Squall.

### Two versions in the repository

* **`cauldron_examples/games/cistern`** — the tutorial's game, small enough to build chapter by
  chapter: the Squall wandering and dropping rain, the yoke of three jars, shadows,
  catches and misses, jars lost and won back, storms that speed up and the step back
  on a miss, a square of its own for every player and robot. Each tutorial chapter adds
  one of these.
* **`cauldron_examples/games/cistern_complete`** — the same game finished: pouring, moods, hail and
  lightning, versus, its own title, menus and hud through A, art and music from B,
  attract mode and high scores. The tutorial ends by pointing at it: this is where the
  chapters lead.

## Order of work

1. A — menu and hud tools, the stock look, feel.
2. B — the asset generation additions.
3. Per game: a design page (core loop, references, palette, a mood board from the
   Studio), the first stage or region to finished quality, the style LoRA trained from
   it, then the rest in that style. Judged by playing it.
