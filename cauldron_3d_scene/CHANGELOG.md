# Changelog

## [Unreleased]

- The package is `cauldron_3d_scene`, and its modules are `Cauldron3D.Scene.*` (`Cauldron3D.Scene.Mesh`, `Cauldron3D.Scene.Stream`, `Cauldron3D.Scene.Target`, the converters…), in place of `cauldron_gpu_scene` and `CauldronGPU.*`: the scene is drawn by any renderer, not only the graphics card.
- `Cauldron3D.Scene.Target.capabilities/1` and `Cauldron3D.Scene.Capabilities`: the effects a renderer draws (ray tracing, upscaling, frame generation), so a game offers only those.
- Morph targets: `Cauldron3D.Scene.Mesh` `morphs` and `Cauldron3D.Scene.Pose` `weights`, in stream operations 24 and 25, drawn by the software renderer. `Cauldron3D.Scene.Gltf.upload/3` uploads a mesh's first 64 morph targets and returns `morphs`, the instances that have them.
- `Cauldron3D.Scene.Gltf.Animator`: plays a document's clips on the instances `Cauldron3D.Scene.Gltf.upload/3` placed, as poses.
- `Cauldron3D.Scene.Software`: a `Target` drawn on the CPU by `cauldron_3d`, for a machine whose graphics card will not draw a scene; frames go to a function of the caller's. `Cauldron3D.Scene.Software.Picture` lists what it draws.

The first release, holding the plain-Elixir modules that were in `cauldron_gpu`, with the
same names.

### Added

- `CauldronGPU.Texture.encoded/2`: a PNG or JPEG texture kept as its file bytes, with
  its size read from the header; streamed as op 23.
- `CauldronGPU.Gltf.upload/3`: a glTF document (`Cauldron3D.Formats.Gltf`) through any
  `CauldronGPU.Target`, with `:first_id`, `:place`, `:places` and `:shadows`. Only the
  meshes its nodes place, and the materials and images those use, are uploaded. Meshes
  with joints and weights are uploaded skinned, and the result lists the skinned
  instances (`skins`) for posing.
