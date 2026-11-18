# 3D file formats

`cauldron_3d_formats` reads the files of the Quake family into structures the renderers
draw: `Cauldron3D.Bsp`, `Cauldron3D.Mesh` and `Cauldron3D.Texture`. It also reads glTF
2.0 documents and VRM avatars, which `Cauldron3D.Scene.Gltf` uploads as scene meshes,
materials and instances.

It ships no game data. A game brings its own copy, reads it here, and follows the licence
of the data it brought.

## Finding a game's files

`Cauldron3D.Formats.Files.open/2` gathers one or more directories, their numbered
`pak0.pak`, `pak1.pak`, … archives, and their `.pk3` zips, including zips inside them.
Names are matched without regard to case.

```elixir
{:ok, files} = Cauldron3D.Formats.Files.open("/games/quake", within: "id1")

Cauldron3D.Formats.Files.read!(files, "maps/e1m1.bsp")
Cauldron3D.Formats.Files.exists?(files, "progs/player.mdl")
Cauldron3D.Formats.Files.list(files, "maps/")
```

Within a directory, `.pak` archives come first in number order, then `.pk3` archives in
name order, then loose files. A later source overrides an earlier one, and a later
directory overrides an earlier directory. `:within` names a subdirectory to use in place
of a directory that holds no archives, which is how `id1` and `valve` are opened.

| Call | Answers |
| --- | --- |
| `Files.read/2` | the file's bytes, or `nil` |
| `Files.read!/2` | the bytes, raising `KeyError` when the file is missing |
| `Files.exists?/2` | whether the name is there |
| `Files.list/2` | the lower-case names beginning with a prefix, sorted |
| `Files.package/2` | the archive or directory a name came from |

## What can be loaded

| File | Reader | Answers | In a scene |
| --- | --- | --- | --- |
| `.bsp` | `Cauldron3D.Formats.Bsp.parse/2` | a `Cauldron3D.Bsp` and the entity text | `Cauldron3D.Scene.Bsp.upload/4`, then `instances/2` |
| Quake `.mdl` | `Cauldron3D.Formats.Mdl.parse/1` | `Cauldron3D.Mesh`, frames, flags, box | `Cauldron3D.Scene.AliasModel.upload/4` |
| Half-Life `.mdl` | `Cauldron3D.Formats.Studio.parse/1` | bones, sequences, body parts, textures | `Cauldron3D.Scene.StudioModel.upload/3` |
| `.spr` | `Cauldron3D.Formats.Spr.parse/1` | frames of `Cauldron3D.Texture` with origins | `Cauldron3D.Scene.Billboards.mesh/2` |
| `WAD2` | `Cauldron3D.Formats.Wad2.pictures/2` | pictures by name | a texture handle |
| `WAD3` | `Cauldron3D.Formats.Wad3.textures/1`, `pictures/1`, `fonts/1` | mips, pictures, fonts | texture handles, or a font for your own drawing |
| `.tga`, `.bmp` | `Cauldron3D.Formats.Tga.parse/1`, `Cauldron3D.Formats.Bmp.parse/1` | `Cauldron3D.Texture` | a texture handle |
| `.wav` | `Cauldron3D.Formats.Wav.read/1` | rate, 16-bit PCM, loop | your sound player |
| `.gltf`, `.glb` | `Cauldron3D.Formats.Gltf.read/1` | the document | `Cauldron3D.Scene.Gltf.upload/3` |
| `.vrm` | `Gltf.read/1` then `Cauldron3D.Formats.Vrm.read/1` | humanoid, chains, colliders | `Gltf.Rig`, `Cauldron3D.SpringBones` |

A map's entity text has its own reader: `Cauldron3D.Formats.Entities.parse/1` turns it
into one map of keys and values per entity, and `vector/1` and `number/1` read the values
a map uses.

## Maps

`Cauldron3D.Formats.Bsp.parse/2` reads Quake's `BSP29` and `BSP2` layouts and Half-Life's
`BSP30`, whose textures keep their own palettes and whose lighting is red, green and blue.
It answers the world and the entity text.

```elixir
{:ok, %{bsp: bsp, entities: text}} =
  Cauldron3D.Formats.Bsp.parse(bytes,
    hulls: [{{-16.0, -16.0, -24.0}, {16.0, 16.0, 32.0}}],
    texture: fn name, mips -> Cauldron3D.Formats.Bsp.solid(name, mips) end
  )
```

`:hulls` gives the boxes of hulls 1 and up, in the order the map was compiled with; hull
0, the point hull, is built from the nodes. `:texture` is your function of the lower-case
name and the four mips. It gives the entry in the world's `textures`: its kind (`:solid`,
`:masked`, `:sky`, `:liquid` or `:hidden`) and whatever else the game keeps. The default is
`Cauldron3D.Formats.Bsp.solid/2`, and a texture the map names but does not hold becomes
`Cauldron3D.Formats.Bsp.missing/0`, a checked square.

A `BSP30` map may name textures it does not hold. `Cauldron3D.Formats.Bsp.miptex/2` reads
the record a WAD3 holds, and the `:texture` function can put it in the world. Only a
`:solid` face gets a lightmap.

`Cauldron3D.Scene.Bsp.upload/4` uploads the world's textures, lightmaps and brush models
for a renderer, and `Cauldron3D.Scene.Bsp.instances/2` gives the changes that place them.
`transform/1` and `point/2` turn map units into the renderer's frame at `:scale` metres a
unit, default `1 / 32`.

## Models

`Cauldron3D.Formats.Mdl.parse/1` reads a Quake model into a `Cauldron3D.Mesh` whose
frames are its poses. It keeps the model's flags (rocket trail, gib blood, rotation and so
on) and its box. `Cauldron3D.Formats.Mdl.pose/3` picks the pose for a frame number at a
time, including a frame group cycling through its poses, which is the `frame:` a mesh is
drawn at.

```elixir
{:ok, player} = Cauldron3D.Formats.Mdl.parse(bytes)
Cauldron3D.Mesh.polygons(player.mesh, frame: Cauldron3D.Formats.Mdl.pose(player, 0, 0.0))
```

`Cauldron3D.Formats.Studio.parse/1` reads a Half-Life studio model: bones, bone
controllers, hitboxes, sequences with their events, attachments, textures with their own
palettes, skin families, and body parts of skinned meshes. A model whose textures are in a
separate `…t.mdl` holds none until `Studio.add_textures/2`; a sequence in group `n` above 0
needs `Studio.add_group/3`, and `Studio.missing_groups/1` says which are still absent.

`Studio.locals/4` gives each bone's position and rotation for a frame of a sequence.
`Cauldron3D.Skeleton.pose/3` turns those into transforms, and `Studio.vertices/3` or
`Studio.polygons/3` gives the vertices or polygons to draw.

## Sprites

`Cauldron3D.Formats.Spr.parse/1` reads Quake's version 1 and Half-Life's version 2.
`frames` is a tuple of `{:single, picture}` or `{:group, [{picture, until}]}`, each picture
a `Cauldron3D.Texture` and the pixel that sits on the entity. Colour 255 is see-through.

`Cauldron3D.Formats.Spr.pictures/1` gives every frame's picture in order and
`Cauldron3D.Formats.Spr.picture/3` the picture for a frame at a time.
`Cauldron3D.Formats.Spr.rgba/3` turns a sprite's indexed picture into RGBA by the
sprite's format and its palette. A sprite in a scene is a board for
`Cauldron3D.Scene.Billboards.mesh/2`, which answers one mesh and the keys to give each
part a material.

## Pictures and fonts

`Cauldron3D.Formats.Wad2.pictures/2` reads a WAD2's pictures by lower-case name, and
`Wad2.lmp/1` a loose `.lmp` picture. `Cauldron3D.Formats.Wad3.textures/1` reads a WAD3's
wall textures with their four mips and their own palettes, `pictures/1` its pictures,
`fonts/1` and `font/1` its fonts. `Tga.parse/1` and `Bmp.parse/1` read the two picture
files a game keeps loose.

The picture readers answer a `Cauldron3D.Texture`. In a scene that is what
`Cauldron3D.Scene.Target.texture/2` uploads, and a material's `base_texture` is the handle
that comes back.

## Sounds

`Cauldron3D.Formats.Wav.read/1` reads an 8- or 16-bit mono RIFF WAVE into 16-bit PCM.

```elixir
{:ok, %{rate: rate, pcm: pcm, loop: loop}} = Cauldron3D.Formats.Wav.read(bytes)
```

A file with a cue point loops from it, and `loop` says where, in seconds; it is `nil` for
a sound that plays once. Playing the samples is the game's business — `cauldron_core`
holds the sound modules — and this package stops at the bytes and the rate.

## Entities and normals

`Cauldron3D.Formats.Entities.parse/1` gives one map per entity, and `blocks/1` gives each
block's text with its keys. A `quake_c` host starts from a map's entity text and the game's
`progs.dat`, both read through `Cauldron3D.Formats.Files`.

`Cauldron3D.Formats.Normals.at/1` gives one of the 162 vertex normals a Quake model
indexes into; an index past the table is straight up.

## glTF 2.0

`Cauldron3D.Formats.Gltf.read/1` reads a `.gltf` file's JSON with its buffers and images
beside it or inline as `data:` URIs, or a `.glb` container. `parse/2` takes the bytes and a
`:base` folder for relative URIs.

A document holds `meshes` as packed triangle lists, `materials` in metallic-roughness
terms, `images` as PNG or JPEG bytes, and `instances` for every node of the scene with a
mesh and its world matrix. It also holds the `nodes` tree, `skins` with their inverse bind
matrices, the `animations`, and the top-level `extensions`. Coordinates are glTF's: metres,
`+y` up, texture rows from the top.

```elixir
{:ok, document} = Cauldron3D.Formats.Gltf.read("alley/barrel_stove_1k.gltf")

{:ok, placed} = Cauldron3D.Scene.Gltf.upload(target, document, first_id: 100)
Cauldron3D.Scene.Target.submit(target, placed.instances)
```

`Cauldron3D.Scene.Gltf.upload/3` uploads one mesh for each glTF mesh a node places, with a
part per primitive, the materials those parts use, and their images as encoded textures.
It answers `%{instances, handles, bounds, skins, morphs, next_id}`. That is the changes to
submit, every handle uploaded, the box around everything placed, `{id, skin}` for each
skinned instance, `{id, node, weights}` for each instance with morph targets, and the first
id not used.

A skinned mesh keeps its rest pose until
`{:pose, id, %Cauldron3D.Scene.Pose{bones: bones}}` arrives, with the bones
`Cauldron3D.Formats.Gltf.Rig.bones/4` gives. A mesh keeps its first 64 morph targets.

Not read: occlusion strength other than one, texture coordinate sets other than the first
for colour textures, and glTF's own lights and cameras.

`Cauldron3D.Formats.Gltf.Animations.read/3` reads the clips,
`Cauldron3D.Formats.Gltf.Clip.sample/3` and `blend/3` sample and blend them, and
`Cauldron3D.Formats.Gltf.Mixer` plays a weighted mix of them with a fade between mixes.
`Cauldron3D.Formats.Gltf.Rig.pose_sample/3` poses a rig from a sample.

## VRM

A `.vrm` file is a `.glb` with the VRM 0.x extension. Read it as a document first, then
with `Cauldron3D.Formats.Vrm.read/1`.

```elixir
{:ok, document} = Cauldron3D.Formats.Gltf.read("avatar.vrm")
{:ok, vrm} = Cauldron3D.Formats.Vrm.read(document)
rig = Cauldron3D.Formats.Gltf.Rig.new(document)

Cauldron3D.Formats.Vrm.node(vrm, "hips")
Cauldron3D.Formats.Vrm.spring_bones(vrm, rig, Cauldron3D.Skeleton.identity())
```

`humanoid` maps the standard bone names to their nodes, `chains` holds the swinging bone
chains as `Cauldron3D.SpringBones` chains, `colliders` the spheres they keep out of, and
`meta` the title, author and licence. `Cauldron3D.Formats.Vrm.lit/2` makes the avatar's
unlit toon materials lit, so the scene's lights reach them.

VRM 0.x writes collider offsets and gravity directions with the Z axis reversed from
glTF's; the reader puts them back. A VRM 0.x avatar faces `-z`.

## Where the data comes from

| Data | You supply | Open it with |
| --- | --- | --- |
| Quake | a Quake installation's `id1` directory, with `pak0.pak` and `pak1.pak` | `Files.open(path, within: "id1")` |
| A Quake mission pack | the pack's own directory beside `id1` | `Files.open([id1, pack])` |
| Half-Life | `valve/pak0.pak` | `Files.open("/games/half-life/valve")` |
| A Half-Life mod | the mod's directory, which overrides `valve` | `Files.open([valve, mod])` |
| Doom | a WAD read through `cauldron_2d`, whose map `Cauldron3D.Scene.Sectors` uploads | not this package |
| glTF | an export from Blender or another tool, with its `.bin` and images or as one `.glb` | `Gltf.read/1` |
| VRM | a `.vrm` avatar file | `Gltf.read/1`, then `Vrm.read/1` |
| Sounds | the `sound/` files inside the paks | `Wav.read/1` |

The package contains no `.bsp`, `.mdl`, `.spr`, `.wad`, `.wav`, `.gltf`, `.glb` or `.vrm`
file, no palette and no `progs.dat`. It cannot download a game, unpack an installer, or
take the place of the data's licence. A palette is 768 bytes with no header:
`Files.read!/2` gives it, and `Cauldron3D.Frame.rgba/2` or a scene converter takes it as
it is.

It also does not write: no archive writer, no map or model exporter, no image encoder.
`Cauldron3D.Scene.PNG` writes a frame's pixels as a PNG.

## A load from start to finish

```elixir
alias Cauldron3D.Formats.{Bsp, Files}

{:ok, files} = Files.open("/games/quake", within: "id1")

{:ok, %{bsp: bsp}} =
  Bsp.parse(Files.read!(files, "maps/e1m1.bsp"),
    hulls: [{{-16.0, -16.0, -24.0}, {16.0, 16.0, 32.0}}],
    texture: fn name, mips -> Bsp.solid(name, mips) end
  )

palette = Files.read!(files, "gfx/palette.lmp")

world = Cauldron3D.Scene.Bsp.upload(target, bsp, palette, scale: 1 / 32)
Cauldron3D.Scene.Target.submit(target, Cauldron3D.Scene.Bsp.instances(world, first_id: 1))
```

## Where to go next

| You want to | Read |
| --- | --- |
| Draw what was loaded, without a card | [`cauldron_3d`'s software 3D](https://hexdocs.pm/cauldron_3d/software-3d.html) |
| Put it in a scene and draw it on the card | [`cauldron_3d_scene`'s scenes](https://hexdocs.pm/cauldron_3d_scene/scenes.html), [`cauldron_gpu`'s gpu](https://hexdocs.pm/cauldron_gpu/gpu.html) |
| Run QuakeC against a map | [`quake_c`](https://hexdocs.pm/quake_c) |
| Read Doom sectors and pictures | [`cauldron_2d`](https://hexdocs.pm/cauldron_2d) |
