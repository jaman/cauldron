# Greenware assets

Everything in `priv/art` and `priv/audio` was generated during development through the
NxDiffusion Studio MCP server. `nx_studio.json` declares the application commercial.

## Images

| Asset | Prompt summary | Seed |
| --- | --- | --- |
| `bg_workshop` | claymation workshop at night: workbench, clay jars, round moon window, hanging lamp | 7001 |
| `bg_garden` | clay garden at dusk: pressed-clay hills, giant leaves, dry well, crooked tree | 7002 |
| `bg_cellar` | clay cellar: low brick arches, jars, puddles, one warm lamp | 7003 |
| `bg_fair` | clay carnival at dusk: ferris wheel, tents, string lights | 7004 |
| `bg_kiln` | clay ash road to a cold kiln, embers, cracked ground | 7005 |
| `fig_greenware` | faceless terracotta mender with a brass key in its chest | 7101 |
| `fig_cat` | black plasticine cat with amber eyes | 7102 |
| `fig_green_man` | moss-green clay gardener with leaves for hair | 7103 |
| `fig_boy` | small paper-cut-out boy with a pencil face | 7104 |
| `fig_choir` | stack of cracked ceramic plates with painted faces | 7105 |
| `fig_potter` | tall hooded clay potter with ember eyes | 7106 |
| `prop_cup` | cracked terracotta cup | 7201 |
| `prop_bucket` | leaking terracotta bucket | 7202 |
| `prop_key` | clay key, one tooth missing | 7203 |
| `prop_lamp` | clay oil lamp | 7204 |
| `prop_plate` | cracked bone plate | 7205 |
| `prop_doll` | fired clay doll with a missing leg | 7206 |
| `prop_ferris` | miniature clay ferris wheel, one spoke missing | 7207 |
| `prop_mirror` | clay hand mirror with a brass frame | 7208 |
| `prop_box` | clay music box with a comb | 7209 |
| `prop_heart` | cracked terracotta heart | 7210 |
| `prop_kiln` | miniature brick kiln with an ember mouth | 7211 |
| `prop_door` | miniature clay workshop door | 7212 |
| `prop_well` | miniature clay garden well | 7213 |
| `prop_bird` | clay bird with a torn wing | 7214 |
| `prop_dam` | miniature clay dam with a crack | 7215 |
| `prop_arm` | moss-green clay arm | 7216 |
| `prop_chasm` | broken clay bridge over a dark crack | 7217 |

Each broken prop has a **mended counterpart** (`prop_*_mended.png`), made with
`edit_image` from the same picture: the crack closed, a thin gold kintsugi seam, no
open damage. The scene swaps to it after the test passes, and the use beat plays from
there.

Model: `flux2_klein_4b` (4 steps, commercial use allowed by the Studio's listing),
style `clay`, 1024x576 for backgrounds and 768x768 for isolated figures and props.
Prompts are kept with each generation in the Studio project `greenware`; raw files are
in `art_source/`. The isolated pieces are keyed from a flat magenta background by
`tools_process_art.py` (connected component, no hole fill that would close real
openings), trimmed and scaled to the runtime sizes.

## Music

| Asset | Prompt | Model | Seed | Length |
| --- | --- | --- | --- | --- |
| `title.wav` | handmade stop-motion lullaby: music box, thumb piano, bowed saw, detuned upright piano, clay ocarina, 5/4, warm and melancholy | `ace_step_15_turbo` | 8101 | 60 s |
| `ending.wav` | slow sparse epilogue, music box and low strings, the same lullaby far away | `ace_step_15_turbo` | 8102 | 45 s |

Both are 48 kHz stereo 16-bit PCM, loudness-normalised to -19 LUFS, true peak -2 dBFS.
`Greenware.Sound` loads them as `Cauldron.Audio.Recording`s and cues the title bed or the
epilogue.

## Type

`priv/fonts/body.png` and `display.png` are placeholder bitmap sheets cut from
American Typewriter and Baskerville at 2x. They can be replaced with hand-lettered
sheets of the same cell sizes without touching code.
