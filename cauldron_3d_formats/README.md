# Cauldron3D.Formats

Cauldron3D.Formats reads the Quake family of game files into
[`cauldron_3d`](https://hexdocs.pm/cauldron_3d) structures. It reads archives, maps,
models, sprites, picture collections, pictures and sounds. It also reads glTF 2.0
documents and VRM avatars.

## Where it fits

The readers return `Cauldron3D` values: `Cauldron3D.Bsp`, `Cauldron3D.Mesh` and
`Cauldron3D.Texture`. `cauldron_3d` draws and collides them in software.
[`cauldron_gpu`](https://hexdocs.pm/cauldron_gpu) converts them and draws them on the
graphics card. A [`quake_c`](https://hexdocs.pm/quake_c) host starts from a map's entity
text and the game's `progs.dat`, both read through `Cauldron3D.Formats.Files`.

## Installation

Add the dependency to `mix.exs`:

```elixir
def deps do
  [
    {:cauldron_3d_formats, "~> 0.3"}
  ]
end
```

## What is here

| Module | What it reads |
| --- | --- |
| `Cauldron3D.Formats.Files` | Gathers a game's files from directories. It reads `pak0.pak`… archives, `.pk3` zips (zips inside zips too) and loose files. Later sources override earlier ones. Call `open/2`, then `read/2`, `read!/2`, `exists?/2` or `list/2`. |
| `Cauldron3D.Formats.Bsp` | Reads map files into a `Cauldron3D.Bsp` and the entity text. It reads `BSP29`, `BSP2` and Half-Life's `BSP30`, with its own texture palettes and coloured lighting. |
| `Cauldron3D.Formats.Mdl` | Reads Quake models into a `Cauldron3D.Mesh`, with frame groups, effect flags and a box. `pose/3` picks the pose for a frame at a time. |
| `Cauldron3D.Formats.Studio` | Reads Half-Life studio models (`.mdl` version 10). It reads bones, controllers, hitboxes, sequences and events, attachments, textures, skin families and meshes. It decodes the compressed animation to bone poses. |
| `Cauldron3D.Formats.Spr` | Reads Quake and Half-Life sprites. |
| `Cauldron3D.Formats.Wad2`, `Cauldron3D.Formats.Wad3` | Read picture, texture and font collections. |
| `Cauldron3D.Formats.Tga`, `Cauldron3D.Formats.Bmp` | Read TGA and BMP pictures. |
| `Cauldron3D.Formats.Wav` | Reads WAVE sounds to 16-bit PCM. |
| `Cauldron3D.Formats.Entities` | Reads a map's entity text into one map of keys and values per entity. |
| `Cauldron3D.Formats.Normals` | Holds the 162 vertex normals that Quake models index into. |
| `Cauldron3D.Formats.Gltf` | Reads glTF 2.0 documents, `.gltf` (with buffers and images beside it or inline) and `.glb`: meshes as packed triangle lists, metallic-roughness materials, images, the scene's placed meshes with their world matrices, the node tree and skins. Coordinates stay glTF's: metres, +Y up. |
| `Cauldron3D.Formats.Gltf.Rig` | Turns a document's nodes into one `Cauldron3D.Skeleton`, parents before children, for posing skinned meshes with `Cauldron3D.Skeleton.pose/3` and `Cauldron3D.SpringBones`. |
| `Cauldron3D.Formats.Gltf.Animations`, `Cauldron3D.Formats.Gltf.Clip` | Read a document's animation clips, and sample and blend them: the translations, rotations, scales and morph target weights a clip sets at a time, looped or not. `Gltf.Rig.pose_sample/3` poses a rig from a sample. Meshes carry their morph targets. |
| `Cauldron3D.Formats.Vrm` | Reads the VRM 0.x avatar extension of a `.vrm` file: the humanoid bone names to their nodes, and the swinging bone chains as `Cauldron3D.SpringBones` chains. |

## Usage

A Quake map and model:

```elixir
alias Cauldron3D.Formats.{Bsp, Files, Mdl}

{:ok, files} = Files.open("/games/quake", within: "id1")

{:ok, %{bsp: bsp, entities: text}} =
  Bsp.parse(Files.read!(files, "maps/e1m1.bsp"),
    hulls: [{{-16.0, -16.0, -24.0}, {16.0, 16.0, 32.0}}, {{-32.0, -32.0, -24.0}, {32.0, 32.0, 64.0}}],
    texture: &MyGame.texture/2
  )

{:ok, player} = Mdl.parse(Files.read!(files, "progs/player.mdl"))
Cauldron3D.Mesh.polygons(player.mesh, frame: Mdl.pose(player, 0, 0.0))
```

A glTF model and a VRM avatar:

```elixir
alias Cauldron3D.Formats.{Gltf, Vrm}

{:ok, sponza} = Gltf.read("Sponza/glTF/Sponza.gltf")
length(sponza.meshes)

{:ok, avatar} = Gltf.read("avatar.vrm")
{:ok, vrm} = Vrm.read(avatar)
rig = Gltf.Rig.new(avatar)
Vrm.node(vrm, "hips")
```

Each game names its own conventions through `Bsp.parse/2`'s options. `:hulls` gives the
collision box sizes. `:texture` gives each texture its kind: sky, liquid, hidden or
masked. So the same reader serves Quake and Half-Life.

## License

[AGPL-3.0-only](https://github.com/jaman/cauldron/blob/main/LICENSE). You may use, study, change and share it under the AGPL at
no cost.

A game or service whose source you do not publish needs a
[commercial license](https://github.com/jaman/cauldron/blob/main/COMMERCIAL.md).
