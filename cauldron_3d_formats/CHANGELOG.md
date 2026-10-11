# Changelog

## [0.2.0]

### Added

- `Files`: a game's files from directories — `pak0.pak`… archives, `.pk3` zips (nested
  too) and loose files over several directories, later sources overriding earlier ones;
  `package/2` names the archive a file comes from.
- `Bsp`: `BSP29`, `BSP2` and Half-Life's `BSP30` maps into a `Cauldron3D.Bsp`, with game
  conventions as options: `Bsp.parse/2` takes `:hulls` and `:texture`. A `BSP30` map's
  `Bsp.game` is `:half_life`. Each model's bounds are spread by one unit on every side,
  as Quake engines load them. A map's visibility rows are as long as its world's visible
  leaves (model 0's `visleafs`), as Quake reads them, and the BSP keeps that count
  (`world_leaves`).
- `Mdl`: Quake models.
- `Studio`: Half-Life studio models with posing and drawing.
- `Spr`: Quake's and Half-Life's sprites.
- `Wad2` and `Wad3`: picture, texture and font collections; `Wad2.pictures/2` takes
  `:raw`.
- `Tga` and `Bmp` pictures.
- `Wav`: WAVE sounds, `Wav.read/1` returning 16-bit PCM.
- `Entities`: a map's entity text.
- `Normals`: the vertex normal table Quake models index into.
