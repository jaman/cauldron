# Cauldron3D

Cauldron3D is a 3D software renderer with collision, written in Elixir. It draws
cameras, polygons, keyframed meshes, billboards and BSP worlds with lightmaps. It traces
boxes through collision hulls. Each frame comes out as indexed-colour or full-colour
pixels, drawn in parallel across the schedulers.

Nothing in it belongs to one game. Your game reads its own files into these structures.
It decides what moves, what collides and what is drawn.

## Where it fits

* [`cauldron_3d_formats`](https://hexdocs.pm/cauldron_3d_formats) reads Quake and
  Half-Life files into this package's structures. It reads maps, models, sprites,
  pictures and sounds.
* [`quake_c`](https://hexdocs.pm/quake_c) runs a game's QuakeC against builtins the host
  writes. A 3D host answers the tracing and movement builtins with `Cauldron3D.Hull` and
  `Cauldron3D.Move`.
* [`cauldron_gpu`](https://hexdocs.pm/cauldron_gpu) draws the same worlds and models on
  the graphics card. It converts a `Cauldron3D.Bsp` and its models into its own scene.
* `Cauldron3D.Frame.rgba/2` gives a frame's RGBA bytes. Show them anywhere a picture
  goes. For example, make a `FrenchCurve.Raster` with `FrenchCurve.Raster.from_rgba/3`
  for the terminal, or write a file.

## Installation

Add the dependency to `mix.exs`:

```elixir
def deps do
  [
    {:cauldron_3d, "~> 0.3"}
  ]
end
```

Part of the drawing is in C, built by `elixir_make`. It needs a C compiler. Without one,
the same pixels are made in Elixir, more slowly.

## What is here

| Module | What it does |
| --- | --- |
| `Cauldron3D.Camera` | Says where a picture is taken from. It is perspective or orthographic. `first_person/4`, `follow/3`, `side/2` and `top_down/2` set one up. |
| `Cauldron3D.View` | Fits a camera to a picture size and pixel shape. It projects points and casts rays. |
| `Cauldron3D.Polygon` | Holds one flat convex polygon and its paint. |
| `Cauldron3D.Paint` | Lists the paints. A polygon can be flat, textured, lit through a light table, shaded per vertex, a lit surface, rippling liquid or sky. It can also be painted by a function of your own. |
| `Cauldron3D.Render` | Draws polygons through a view into a `Cauldron3D.Frame`. |
| `Cauldron3D.Setup`, `Cauldron3D.Raster` | Do the drawing. Setup clips and projects a polygon. Raster fills each row. |
| `Cauldron3D.Mesh` | Holds textured triangles posed by keyframes. It blends between frames, and turns and lights the triangles by their normals. |
| `Cauldron3D.Skeleton` | Poses bones from their parents into transforms. |
| `Cauldron3D.Quat` | Holds rotations as quaternions. |
| `Cauldron3D.Billboard` | Stands a picture in the world facing the camera, upright or not. |
| `Cauldron3D.Bsp`, `Cauldron3D.Bsp.Face` | Hold a world cut into convex leaves. They find the leaf at a point, what a leaf can see, and the leaves a box touches. |
| `Cauldron3D.Bsp.Draw` | Gives the polygons of the faces a view can see. It draws brush models, liquids, skies and skyboxes, and adds dynamic lights. |
| `Cauldron3D.Bsp.Surfaces` | Makes each face's texture lit by its lightmap and light styles. It keeps them until the light changes. |
| `Cauldron3D.Bsp.Light` | Says how brightly the world is lit at a point. Use it to light the models standing there. |
| `Cauldron3D.Hull` | Traces a point through a collision hull and says what it hit. |
| `Cauldron3D.Move` | Slides a box along what it hits and steps it up ledges. |
| `Cauldron3D.Texture`, `Cauldron3D.Frame` | Hold indexed-colour and RGBA pictures. Frame also scales pictures and lays one over another. |
| `Cauldron3D.Vec` | Does vector arithmetic. |

## A first picture

This draws one square in front of the camera, in full colour:

```elixir
camera = Cauldron3D.Camera.first_person({0.0, 0.0, 0.0}, 0.0, 0.0)
view = Cauldron3D.View.new(camera, {64, 48})

square = %Cauldron3D.Polygon{
  points: [{100.0, 30.0, -30.0}, {100.0, -30.0, -30.0}, {100.0, -30.0, 30.0}, {100.0, 30.0, 30.0}],
  paint: {:flat, {200, 60, 40}}
}

frame = Cauldron3D.Render.draw(view, [square], palette: :binary.copy(<<0, 0, 0>>, 256))
rgba = Cauldron3D.Frame.rgba(frame, nil)
```

The world has `z` up. Yaw 0 faces `+x`.

Pass `:palette` to `Render.draw/3` to draw four bytes a pixel (`Cauldron3D.Paint.Rgba`).
In full colour, polygons can have tints, blending and dynamic lights. Leave `:palette`
out to draw one palette index a pixel through `:light_table`.

## Drawing a world

```elixir
camera = Cauldron3D.Camera.first_person({0.0, 0.0, 48.0}, yaw, pitch)
view = Cauldron3D.View.new(camera, {320, 200}, pixel_aspect: 1.0)
cache = Cauldron3D.Bsp.Surfaces.new()

polygons =
  Cauldron3D.Bsp.Draw.polygons(bsp, view, surfaces: cache, light: light) ++
    Cauldron3D.Mesh.polygons(mesh, frame: 4, origin: origin, yaw: facing, light: 160)

frame = Cauldron3D.Render.draw(view, polygons, light_table: colormap)
Cauldron3D.Frame.rgba(frame, palette)
```

Give a polygon a `clear` colour to make it see-through there. Give it `depth: :always`
to draw it over everything, as for a held weapon. Both kinds are painted after the solid
polygons.

## How it draws

Each row of the picture is a list of runs. A run is the stretch of pixels where one
polygon is nearest. Where two polygons overlap, the renderer solves for the pixel where
they are equally near. Each pixel is then painted once, by the polygon that owns it.
There is no depth buffer.

A frame is cut into bands of rows. The bands are drawn at the same time, one per
scheduler by default. Each band gets only the polygons that cross its rows. Set
`:bands` on `Render.draw/3` to choose how many.

C code fills the pixels of textured and lit-surface runs (`Cauldron3D.Paint.Spans`). It
also lays one RGBA picture over another and maps a picture through a 256-entry table
(`Cauldron3D.Frame.Pixels`). The lit surfaces of a BSP world are made in parallel. They
are kept in an ETS table until a light style changes.

## Collision

`Cauldron3D.Hull.trace/3` sweeps a point through a hull of planes. A box moves through a
world by tracing through a hull pushed out by the box's size. A BSP world keeps one such
hull per box size. `Hull.box/2` makes a hull from a thing's box, so things collide the
same way.

`Cauldron3D.Move.slide/5` slides along up to four surfaces. `Cauldron3D.Move.step/6` also
steps up ledges. Both take the trace as a function, so your game decides what is solid.

## License

MIT
