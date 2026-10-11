# Cauldron3D.Formats

Readers for the Quake family of game files into `Cauldron3D` structures.

## Installation

```elixir
def deps do
  [
    {:cauldron_3d_formats, "~> 0.2"}
  ]
end
```

| Module | Reads |
| --- | --- |
| `Files` | a game's files from directories: `pak0.pak`… archives, `.pk3` zips (including zips inside zips), loose files; later sources override earlier ones |
| `Bsp` | map files: `BSP29`, `BSP2` and Half-Life's `BSP30` (textures with their own palettes, red-green-blue lighting), into a `Cauldron3D.Bsp` |
| `Mdl` | Quake models |
| `Studio` | Half-Life studio models (`.mdl` version 10): bones, controllers, hitboxes, sequences and events, attachments, textures, skin families, meshes, and the compressed animation decoded to bone poses |
| `Spr` | sprites, Quake's and Half-Life's |
| `Wad2`, `Wad3` | picture, texture and font collections |
| `Tga`, `Bmp` | TGA and BMP pictures |
| `Wav` | WAVE sounds to 16-bit PCM |
| `Entities` | a map's entity text |
| `Normals` | the vertex normal table Quake models index into |

```elixir
{:ok, files} = Cauldron3D.Formats.Files.open("/games/quake", within: "id1")
{:ok, %{bsp: bsp, entities: text}} =
  Cauldron3D.Formats.Bsp.parse(Cauldron3D.Formats.Files.read(files, "maps/e1m1.bsp"),
    hulls: [{{-16.0, -16.0, -24.0}, {16.0, 16.0, 32.0}}, {{-32.0, -32.0, -24.0}, {32.0, 32.0, 64.0}}],
    texture: &MyGame.texture/2
  )
```

Game conventions are options rather than built in: each game names its own hull sizes
and its own texture kinds (sky, liquid, hidden, masked), so the same reader serves Quake
and Half-Life.

## Sources

The readers follow the file formats. The `Normals` table is the 162 directions the MDL
format indexes into; MIT-licensed readers such as three.js's MD2 loader carry the same
table.

## License

MIT. No game data is included.
