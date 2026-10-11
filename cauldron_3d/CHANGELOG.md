# Changelog

## [0.2.0]

### Added

* `Cauldron3D.Camera` and `Cauldron3D.View`: perspective and orthographic cameras, with
  first-person, follow, side-on and top-down set-ups, fitted to a picture and its pixel
  shape.
* `Cauldron3D.Render`, `Setup`, `Raster` and `Paint`: polygons drawn into an
  indexed-colour `Cauldron3D.Frame`, each row resolved into runs of the nearest polygon,
  bands of rows drawn in parallel; flat, textured, light-table, per-vertex shaded,
  surface, liquid, sky and game-defined paints; see-through and always-on-top polygons.
* Full colour: `Render.draw/3` with `:palette` draws RGBA frames (`Cauldron3D.Paint.Rgba`);
  textures may carry their own palette or be RGBA; surfaces are built from grey or
  red-green-blue lightmaps (`Bsp.light_channels`) through a `:curve`; polygons blend by
  alpha or add (`Polygon.blend`); `Frame.blit/4` and `scale/3` take RGBA frames.
* `:masked` texture kind, `{:skybox, faces}` paint and `Bsp.Draw`'s `:skybox` option;
  brush models drawn turned (`{model, origin, angles}`).
* `Cauldron3D.Mesh` (keyframed, blended, lit by normals) and `Cauldron3D.Billboard`.
* `Cauldron3D.Bsp`, `Bsp.Face`, `Bsp.Draw` and `Bsp.Surfaces`: BSP worlds, what a leaf can
  see, faces drawn with lightmapped surfaces made in parallel and cached per mip level.
  `Bsp.visible_leaves/2` gives world leaves only (`Bsp.world_leaves`), never a brush
  model's. `Bsp.game` names the game a map was made for, `:quake` or `:half_life`.
* `Cauldron3D.Bsp.Light`, the light under a point, and `Bsp.Light.on_face/4`, a face's
  lightmap light at a point on it.
* `Cauldron3D.Quat` and `Cauldron3D.Skeleton` (bone transforms from parent-relative
  poses).
* `Cauldron3D.Hull` (point and box hulls, traces) and `Cauldron3D.Move` (sliding, stepping).
* `Cauldron3D.Texture`, `Cauldron3D.Frame` (`rgba/2`, `rgb/2`, `blit/4`, `scale/3`) and
  `Cauldron3D.Vec`.
