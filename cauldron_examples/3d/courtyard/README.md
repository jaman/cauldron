# Courtyard

Three lit 3D scenes drawn by the graphics card, where a character is walked in the
terminal with the keys, the mouse or a controller, seen from behind by a camera that
swings round her. It is a Cauldron game run by `cauldron_2d_drafter`'s client, built the
way Half-Life's client is.

```sh
mix courtyard            # in the terminal (Ghostty, kitty, WezTerm)
mix courtyard --window   # in a window of its own
mix courtyard.fetch      # download the alley, the atrium and the character
mix courtyard.serve      # serve it at http://localhost:4310/play
```

Served, each player's own machine draws the scene (`Cauldron3D.Net.Drawer`): a browser
with three.js, and a desktop or phone client with its graphics card.

The character is the VRoid Project's CC0 avatar AvatarSample_D (Darkness), a VRM file
(`mix courtyard.fetch character`, 17 MB). She walks and runs with a gait made from sines
(`lib/courtyard/gait.ex`); her hair, sleeves and skirt swing with the spring bones the VRM
file describes. Walls stop her and keep the camera on her side of them: each scene has a
walk grid built from its triangles, kept beside the scene's files after the first run.

The scenes:

1. **Courtyard** — made in code: a checkered floor, a gold and a blue sphere, a lamp and a
   ring of turning crates. It needs nothing downloaded.
2. **Alley** — a night-time alley between an apartment block and a factory, from Poly
   Haven's CC0 "Hidden Alley" models: the building fronts are assembled from the modular
   facade kits, with a fire escape, street lamps, security lights and a burning barrel
   stove. `mix courtyard.fetch alley` downloads 87 MB.
3. **Atrium** — Intel's Sponza (CC-BY), lit by a sun whose hour can be moved.
   `mix courtyard.fetch atrium` downloads about 2.1 GB once and keeps about 260 MB: the model and
   its textures at 2048 and 1024 pixels a side.

Downloads go to the user cache folder (`~/Library/Caches/cauldron/assets` on macOS,
`~/.cache/cauldron/assets` on Linux), or to `$CAULDRON_ASSETS` when it is set. A fetch
that stops carries on when run again.

`N` shows the next scene and `1`, `2`, `3` a scene by number. The scene shown stays, dimmed,
while the next one loads; then it fades in. A scene not yet downloaded names the command
that fetches it in the status bar. Each scene remembers where you stood in it.

Keys: `W` `A` `S` `D` and `↑` `↓` walk her, relative to the camera; held keys run, a
controller's left stick walks slower the less it is pushed. `←` `→`, `PgUp` `PgDn`, the
right stick and the mouse (once the `mouse` preset is chosen in the settings, `Tab`) swing
the camera round her; `Z` and `C` (or a controller's `A` and `B`) bring it closer and take
it farther. `R`, `G`
and `U` switch ray tracing, global illumination and upscaling. `=` and `-` widen or narrow
the picture, and `]` and `[` add or take away crates in the courtyard. `,` and `.` move the
atrium's sun earlier and later. `F` shows the frames drawn a second, `?` shows the key
hints, `Tab` opens the settings (frame rate, bindings) and `Q` quits.

## Where things are

- `lib/courtyard/game.ex` is the world. Each tick it walks the character from the actions
  held, swings the camera, poses her and keeps the camera clear of walls; it also keeps
  the scene shown, the hour, the crate count and the picture width.
- `lib/courtyard/character.ex` loads the avatar's rig and VRM data for the world and
  uploads it for the picture; `lib/courtyard/gait.ex` poses her legs, arms and spine.
- `lib/courtyard/grounds.ex` builds and keeps each scene's walk grid.
- `lib/courtyard/client.ex` is the `Cauldron.Client.Game`: the bindings, the status bar
  and the picture.
- `lib/courtyard/picture.ex` is the scene's `:gpu`. It swaps scenes, fades them in and
  sends each frame's moving parts and the camera.
- `lib/courtyard/scene.ex` is what a scene provides; `lib/courtyard/scenes/` holds the
  three.
- `lib/courtyard/loader.ex` uploads a scene away from the drawing.
- `lib/courtyard/kit.ex` builds a glTF document from a modular kit's parts;
  `lib/courtyard/scenes/alley/buildings.ex` lays out the alley's fronts with it.
- `lib/courtyard/fetch.ex` and `lib/courtyard/fetch/` download the scenes. The atrium is
  read straight out of Intel's 3.9 GB zip with ranged requests.
- `priv/assets.json` pins every file: its address, size and checksum.

## Credits

- "Hidden Alley" models and the cobblestone floor: [Poly Haven](https://polyhaven.com),
  CC0.
- Sponza: Intel Corporation, [CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/).
- AvatarSample_D (Darkness): VRoid Project (pixiv), CC0, from
  [OpenGameArt](https://opengameart.org/content/vroid-studio-cc0-models).
