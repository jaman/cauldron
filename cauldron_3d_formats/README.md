# Cauldron3D.Formats

Cauldron3D.Formats reads the Quake family of game files into
[`cauldron_3d`](https://hexdocs.pm/cauldron_3d) structures. It reads archives, maps,
models, sprites, picture collections, pictures and sounds.

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

## Usage

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

Each game names its own conventions through `Bsp.parse/2`'s options. `:hulls` gives the
collision box sizes. `:texture` gives each texture its kind: sky, liquid, hidden or
masked. So the same reader serves Quake and Half-Life.

## License

MIT. No game data is included.
