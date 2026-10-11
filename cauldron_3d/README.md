# Cauldron3D

A 3D software renderer and collision for the BEAM, in pure Elixir: cameras, polygons,
keyframed meshes, billboards, BSP worlds with lightmaps, and box tracing through
collision hulls. It draws indexed-colour pictures for a terminal (or anything that takes
RGBA), splitting each frame across the schedulers.

Nothing in it belongs to one game. A game reads its own files into these structures and
decides what moves, what collides and what is drawn.

## Installation

```elixir
def deps do
  [
    {:cauldron_3d, "~> 0.2"}
  ]
end
```

## What is here

| Module | What |
| --- | --- |
| `Cauldron3D.Camera` | Where a picture is taken from: perspective or orthographic, with first-person, follow, side-on and top-down set-ups |
| `Cauldron3D.View` | A camera fitted to a picture size and pixel shape: projection, rays, the near plane |
| `Cauldron3D.Polygon`, `Cauldron3D.Paint` | A flat convex polygon and how its pixels are coloured: flat, textured, lit through a light table, shaded per vertex, a lit surface, rippling liquid, sky, or a function of the game's own |
| `Cauldron3D.Render` | Polygons through a view into a `Cauldron3D.Frame`, in bands of rows drawn at once |
| `Cauldron3D.Setup`, `Cauldron3D.Raster` | The drawing itself: clipping and projection, then each row kept as runs of whichever polygon is nearest, so each pixel is painted once |
| `Cauldron3D.Mesh` | Textured triangles posed by keyframes, blended between frames, turned and lit by their normals |
| `Cauldron3D.Billboard` | A picture standing in the world facing the camera, upright or not |
| `Cauldron3D.Bsp`, `Bsp.Face` | A world cut into convex leaves: point location, what a leaf can see, the leaves a box touches |
| `Cauldron3D.Bsp.Draw`, `Bsp.Surfaces` | The faces a view can see, painted with textures lit by their lightmaps and light styles, made once per mip level and kept until the light changes |
| `Cauldron3D.Hull` | Tracing a point through a collision hull (a world's, or a box's) and what it hit |
| `Cauldron3D.Move` | Sliding along what a box hits and stepping up ledges, over the game's own trace |
| `Cauldron3D.Texture`, `Cauldron3D.Frame`, `Cauldron3D.Vec` | Indexed-colour pictures, scaling and overlays, and vectors |

## Drawing

```elixir
camera = Cauldron3D.Camera.first_person({0.0, 0.0, 48.0}, yaw, pitch)
view = Cauldron3D.View.new(camera, {320, 200}, pixel_aspect: 1.0)

polygons =
  Cauldron3D.Bsp.Draw.polygons(bsp, view, surfaces: cache, light: light) ++
    Cauldron3D.Mesh.polygons(mesh, frame: 4, origin: origin, yaw: facing, light: 160)

frame = Cauldron3D.Render.draw(view, polygons, light_table: colormap)
Cauldron3D.Frame.rgba(frame, palette)
```

A polygon with a `clear` colour is see-through there, and one with `depth: :always` is
drawn over everything (a held weapon); both are painted after the solid polygons.

## How it draws

Each row of the picture is a list of runs, each run the stretch of pixels where one
polygon is nearest. A polygon's nearness changes linearly along a row, so where two
overlap the boundary between them is found by solving for the one pixel where they are
equally near; a polygon is cut into the row's runs where it is in front, in any order.
Each pixel is then painted once, by the polygon that owns it, with its texture position
divided through for perspective. There is no depth buffer and nothing is drawn twice.

A frame is cut into bands of rows that are drawn at the same time, one per scheduler.
Lit surfaces of a BSP world are made in parallel too, each from the face's own texture,
lightmap samples and styles, and kept in an ETS table until a style's light changes.

## Collision

`Cauldron3D.Hull.trace/3` sweeps a point through a hull of planes; a box moves through a
world by tracing through a hull pushed out by the box's size, which is how a BSP world
keeps its collision. `Hull.box/2` makes a hull of a thing's box, so things collide the
same way. `Cauldron3D.Move` slides along up to four surfaces and steps up ledges, taking
the trace as a function so the game decides what is solid.

## License

MIT
