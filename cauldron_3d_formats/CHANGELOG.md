# Changelog

## [Unreleased]

### Added

- `Cauldron3D.Formats.Gltf`: glTF 2.0 `.gltf` and `.glb` documents with their meshes
  (packed binaries), materials (`KHR_texture_transform`,
  `KHR_materials_emissive_strength`, `KHR_materials_unlit`), images and placed nodes.
  Documents also carry every node (`nodes`), skins with their joints and inverse bind
  matrices, and the top-level `extensions`. Primitives carry `joints` and `weights`, and
  keep only the vertices their triangles use.
- `Cauldron3D.Formats.Gltf.Rig`: a document's nodes as one skeleton, posed, with the bone
  matrices for a skin.
- `Cauldron3D.Formats.Gltf.Animations` and `Cauldron3D.Formats.Gltf.Clip`: a document's
  animation clips (`animations`), and `Clip.sample/3` and `Clip.blend/3` for the translations,
  rotations, scales and morph target weights a clip sets at a time, looped or not, with step,
  linear and cubic spline interpolation. `Cauldron3D.Formats.Gltf.Rig.pose_sample/3` poses a rig
  from a sample.
- Primitives carry their morph targets (`targets`), and meshes their starting `weights` and
  `target_names`.
- `Cauldron3D.Formats.Vrm`: the VRM 0.x avatar extension: humanoid bones, spring bone
  chains and colliders (`spring_bones/3`), and `lit/2` for its toon materials.

## [0.3.3]

### Changed

- No changes in this package; released with the rest of the cauldron packages.

## [0.3.2]

### Changed

- No changes in this package; released with the rest of the cauldron packages.

## [0.3.1]

### Changed

- No changes in this package; released with the rest of the cauldron packages.

## [0.3.0]

### Changed

- The README is rewritten in plain sentences.

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
