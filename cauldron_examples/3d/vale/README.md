# Vale

An open land drawn by the graphics card: a lake, meadows with grass and flowers, woods,
a stepped crag, and a small figure who walks, dashes, jumps, climbs and swims across it.

```
mix deps.get
mix vale.figure
mix vale
mix vale --window
```

`mix vale.figure` copies the figure and her clips out of an imachine library into the
cache folder (`Vale.Figure.folder/0`). `priv/figure.json` names the library and the
items. Without them the land still draws and the status bar says the figure is missing.

`Vale.Client` lists the keys.

## What it is made of

| Part | Module | Built on |
| --- | --- | --- |
| The land: heights, ground kinds, water, trees, bushes, boulders, panels | `Vale.Land` | `Cauldron.OpenWorld.Map`, `Cell`, `Thing`, `Panel`, `Store`, `Cauldron.Noise` |
| Walking, falling, climbing, swimming, stamina | `Vale.Game` | `Cauldron.OpenWorld.Mover` |
| Which clips play and how they fade | `Vale.Game` | `Cauldron3D.Formats.Gltf.Mixer` |
| The figure and her clips | `Vale.Figure` | `Cauldron3D.Formats.Gltf`, `Gltf.Rig`, `Gltf.Clip.onto/3` |
| Meshes, textures, materials and the light of each hour | `Vale.Looks` | `Cauldron3D.Scene.Mesh`, `Material`, `Liquid`, `Environment` |
| Keeping the land round the figure drawn | `Vale.Picture` | `Cauldron3D.Scene.OpenWorld.Shown` |

## Where the land ends

The map is eight cells of 64 metres a side. The inner six by six are simulated. The
outer ring is drawn and never entered: `Cauldron.OpenWorld.Edge.Scenery` stops the
figure at the line, and the status bar says so. Beyond the ring four panels stand on the
map's sides with mountain ranges painted on them (`Vale.Looks` paints the picture), and
`Cauldron.OpenWorld.Edge.Backdrop` would stop anything that reached them.

## The figure

She is a poppet, a Small creature, drawn 0.9 metres tall. Her model was made in a
T-pose so her sleeves do not fuse with her coat, rigged with imachine's 22-joint body
skeleton, and animated with HY-Motion clips. Each clip is a glTF file with the same
skeleton; `Vale.Figure` reads the skin from one file and only the clip from the others.

The clips are licensed for non-commercial use (HY-Motion 1.0 Community License, Hunyuan
3D 2.0 Community License). They are not in this repository.
