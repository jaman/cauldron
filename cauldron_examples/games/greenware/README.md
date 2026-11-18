# GREENWARE

A stop-motion clay adventure for Cauldron. You are a faceless clay mender in a world
that is drying out. You fix what you can: a cup, a door, a bird, a dam, a choir of
plates, a heart, and finally the sky.

The game is one 1280 by 720 picture painted by the game itself, so the same world runs
in a terminal, a desktop window, a native macOS app, an iPhone and an Android phone.

## A look

| Title | The workshop |
| --- | --- |
| ![Title](screenshots/title.png) | ![Hub](screenshots/hub.png) |
| **A mending** | **Mended and ready to use** |
| ![Mend](screenshots/mend-cup.png) | ![Mended](screenshots/mended-cup.png) |

## Run it

```sh
mix deps.get
mix greenware            # terminal, in Ghostty, kitty, WezTerm or iTerm2
mix greenware.desktop    # a desktop window (wx)
mix test                 # the world, every mending, saves and the painter
```

The terminal client scales the picture to the pane. With an image protocol (kitty,
iTerm2 or sixel) it draws the picture itself; without one it draws a coarse coloured
character approximation, as Cauldron's terminal client does.

Native targets are described in `mix.exs` and `config/config.exs`:

```sh
mix cauldron_native.build macos --run
mix cauldron_native.build ios --team TEAM_ID --run
mix cauldron_native.build android --run
```

The macOS app was built and launched on this machine:

```
_build/macos_prod/cauldron_native/macos/xcode/build/Build/Products/Release/App.app
```

The iOS simulator build was also installed and launched on an iPhone 17 simulator, so
the touch path, the title's tap menus and the native screen are exercised. Xcode's Swift
macro plugin server needs access to its caches outside the project; if a sandboxed build
fails with `ObservationMacros.ObservableMacro ... malformed response`, run the build
with full disk access. Android is configured but not built here.

## Play

The game is mouse, touch or d-pad first. Every menu can be clicked or tapped; every
scene is clicked or tapped; the mending view takes a dragged pointer.

| Action | Keys |
| --- | --- |
| move the cursor / choose | arrows, WASD, left stick, pointer |
| interact / mend / advance | Enter, Space, A, tap or click |
| test the mend | T |
| reset the clay | R |
| undo a stroke | Z |
| cat hint | H |
| back to the workshop | Q, Backspace |
| pause, options, controls | Escape |

Tools are the seven rows at the right of a mending: **thumb** presses clay in, **pin**
carves it away, **paddle** flattens, **sponge** smooths, **wire** adds an armature,
**water** softens, **heat** fires. Keys 1–7 choose one; clicking or tapping a row does
too. Shape while the clay is wet, then fire it. The tests at the bottom of the screen
tell you what the puzzle wants; Enter or Test runs them.

## The loop

Every scene is the same promise, made concrete:

1. **Find** the broken thing in the act hub.
2. **Mend** it in a close-up of the actual object: press clay into the crack, add an armature, soften, fire.
3. **Test** the mend against its physical promise — holds water, bears weight, rings true.
4. **Use** it. The mended cup fills; the key turns; the bird flies; the bridge carries you. That use is the scene's payoff and its completion.

A mended thing is only a promise until it is used. That sentence is the design of the
whole game, and it is in the Cat's opening lines.

## Structure

Five acts, fifteen mends, three endings.

| Act | Place | Mends |
| --- | --- | --- |
| 1 | The Workshop | cup, latch, bird (optional) |
| 2 | The Garden | well/bucket, the Green Man's arm, the dam |
| 3 | The Cellar | lamp, cracked choir/plate, fired doll |
| 4 | The Fair | ferris hub, mirror face, music box |
| 5 | The Kiln Road | ash bridge, the Mender's heart, the sky |

Each act has a hub with cards for its mends and a way on when its required mends are
done. Progress is saved after every completed scene, act and ending. The title offers
Continue when a save exists.

## How it is built

| Piece | Module |
| --- | --- |
| world, screens, dialogue, endings | `Greenware.Game` |
| campaign data and story | `Greenware.Campaign` |
| the clay field, tools and predicates | `Greenware.Mend`, `.Check`, `.Shape`, `.Objects`, `.Puzzles` |
| painter and layout | `Greenware.Render`, `Greenware.Canvas`, `Greenware.Layout`, `Greenware.UI` |
| art and fonts | `Greenware.Art`, `Greenware.Fonts` |
| title, summary, menus | `Greenware.Title`, `Greenware.Summary`, `Greenware.Menus` |
| sound and music | `Greenware.Sound` |
| save file | `Greenware.Progress` (`Cauldron.Save`) |

The world is pure; the save is the one deliberate side effect, at scene and act
boundaries. `Cauldron.Test` drives the whole loop without a clock.

### The picture

`Greenware.Canvas` lays the game out in 640 by 360 design units and paints at 1280 by
720. Backgrounds, figures and props are the clay artwork in `priv/art`; if a file is
missing the procedural placeholder in `Greenware.Art` is drawn instead, so the game
never depends on an asset being present. Fonts are two bitmap sheets in `priv/fonts`
(American Typewriter for the world, Baskerville for titles) cut at 2x.

### The clay

A mending is a 96 by 72 height field plus wire, wetness, firedness, clay, water and
fuel. The player raises and lowers the field with brushes; the puzzle is a list of
plain checks (`{:fill, zone, threshold, label}`, `{:wire, n, label}`, `{:tuned, ...}`,
`{:fired, n, label}`) that the engine evaluates without knowing what the object is.
`Greenware.Mend.Objects` builds the bodies, `Puzzles` gives them goals. Every puzzle is
solvable; `mix test` proves it for all fifteen.

### Performance

The first version painted 30 full 1280 by 720 frames a second, created a new native
bitmap for every one, and never released the old ones. It grew to a 9 GB process and
pinned the CPU. It now paints at 12 fps — the stop-motion rate — caches a frame until
something visible changes, and releases the previous wx bitmap when a new one is shown.
On the same machine that measured 9.2 GB and a pegged CPU, an idle world measures about
**465 MB** and **0.1% of the BEAM's scheduler capacity**.

## Assets and provenance

The clay art is made with NxDiffusion Studio (`nx_studio.json` declares the work
commercial), model `flux2_klein_4b` with the `clay` style. Raw generations are kept in
`art_source/`; `tools_process_art.py` trims the chroma key and writes the runtime
`priv/art` files. The music is ACE-Step (`ace_step_15_turbo`), two instrumental cues,
normalised to 48 kHz stereo WAV. See [ASSETS.md](ASSETS.md) for the list, seeds and
prompts.

## Known limits

* Android is configured but was not built here; iOS was built and launched in the
  simulator.
* Without an image protocol the terminal shows a coarse coloured-character version of
  the picture rather than the painted one; use kitty, iTerm2 or sixel for the full
  image.
* The music is a 60-second title bed and a 45-second epilogue; the play loop uses the
  title bed and falls silent after it ends.
* There are fifteen mends, not the forty scenes of the original pitch. The data-driven
  campaign is built to take more: a scene is a map in `Campaign`, a puzzle is a body in
  `Mend.Objects` and a list of checks in `Puzzles`. Each scene also carries its `use`.
* This is a stylised, hand-made-looking indie game, not an AA production. The clay
  images are AI-assisted stills; figures do not have full puppet animation. The mended
  states, close-up mending art, use beats and performance work make the loop readable,
  but they do not turn stills into a Pixar-grade asset pipeline.

## Credits

Designed and built as a Cauldron game. Clay art made with NxDiffusion Studio, music
with ACE-Step, title face Baskerville, body face American Typewriter.
