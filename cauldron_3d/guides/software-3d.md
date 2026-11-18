# Software 3D

`cauldron_3d` draws 3D pictures on the CPU: cameras, polygons, meshes, BSP worlds and
collision, with no graphics card and no window. A camera says where a picture is taken
from, a list of polygons says what is in it, and the renderer answers a frame: a binary
of pixels, one byte or four a pixel.

Nothing in the package belongs to one game. Your game reads its own files into these
structures and decides what moves, what collides and what is drawn.

The world is right-handed with `z` up. Yaw 0 faces `+x`, yaw `:math.pi() / 2` faces
`+y`, and pitch above zero looks up. This is not the frame of `cauldron_3d_scene`, which
is `+y` up; a scene camera is turned into this one by `Cauldron3D.Scene.Software`.

## What it draws

| You have | Module | It holds |
| --- | --- | --- |
| A place to look from | `Cauldron3D.Camera` | position, yaw, pitch, roll, a projection |
| A camera fitted to a picture | `Cauldron3D.View` | the projection from world points to pixels |
| A flat convex face | `Cauldron3D.Polygon` | points, paint, culling, depth, blend |
| A keyframed model | `Cauldron3D.Mesh` | frames, triangles, skins |
| A picture in the world | `Cauldron3D.Billboard` | a polygon facing the view |
| A world cut into leaves | `Cauldron3D.Bsp` | planes, nodes, leaves, faces, lightmaps |
| A moving box | `Cauldron3D.Hull`, `Cauldron3D.Move` | traces, slides, steps |
| A floor to walk on | `Cauldron3D.WalkGrid` | blocked cells seen from above |
| A picture in memory | `Cauldron3D.Texture`, `Cauldron3D.Frame` | indexed or RGBA pixels |

`Cauldron3D.Skeleton` poses bones from their parents and `Cauldron3D.SpringBones` swings
chains of bones — hair, sleeves, skirts — on their own. `Cauldron3D.Vec` and
`Cauldron3D.Quat` do the arithmetic the rest uses.

## A picture is built in four steps

A `Cauldron3D.Camera` holds the eye. `Cauldron3D.View.new/3` fits it to a picture
`{width, height}`, with `:pixel_aspect` for pixels that are taller than they are wide.
The view keeps the camera's axes, so a point is turned into camera space with
`Cauldron3D.View.to_camera/2` and projected with `Cauldron3D.View.project/2`.

A `Cauldron3D.Polygon` is the unit of drawing: a flat, convex list of points and a paint.
`Cauldron3D.Render.setups/3` clips each polygon to the near plane, projects it, and
reduces it to the rows it covers, a plane for each attribute across the picture, and its
edges. A polygon that is wholly behind the camera, edge-on, facing away, or off the
picture becomes `nil` and is dropped.

`Cauldron3D.Raster.rows/4` turns those setups into rows of pixels. Where two polygons
overlap it solves for the pixel where they are equally near, so each pixel is painted
once, by the polygon that owns it. There is no depth buffer.

`Cauldron3D.Render.draw_setups/3` puts the rows together and answers a
`Cauldron3D.Frame` of the view's size. `Cauldron3D.Render.draw/3` does both steps at
once.

## Frames of indexed colour

A frame is one byte per pixel, or four. `%Cauldron3D.Frame{}` carries `width`, `height`,
`pixels` and `format`, which is `:indexed` or `:rgba`.

An indexed frame is a palette index at every pixel. `Cauldron3D.Frame.rgba/2` takes it
through a palette of 768 bytes — 256 colours of red, green and blue — and gives four
bytes a pixel. `Cauldron3D.Frame.rgb/2` gives three.

Lit paints read a **light table**: rows of 256 colours, brightest first. Light value 128
is a texture's own colours; 255 is full brightness. `Cauldron3D.Render.draw/3` takes the
table as `:light_table`, and its row count as `:light_rows` (default the table's size
over 256).

Pass `:palette` to `Cauldron3D.Render.draw/3` to draw in full colour instead: four bytes
a pixel, with tints, blending and dynamic lights. Leave it out to draw one index a pixel.

## Paints

A polygon's `paint` is one of these.

| Paint | Gives |
| --- | --- |
| `{:flat, colour}` | one colour: a palette index, or `{r, g, b}` in full colour |
| `{:texture, texture, light}` | a texture through the light table at `light`, or as it is when `light` is `nil` |
| `{:shaded, texture}` | a texture lit per vertex from the polygon's `lights` |
| `{:surface, texture}` | a texture already lit, its edge pixels repeated |
| `{:warp, texture, opts}` | a texture rippling as liquid does |
| `{:sky, layers, opts}` | a sky at no distance, from layers of texture |
| `{:fun, fun}` | your own function of the run |

In a full-colour picture there are two more: `{:skybox, faces}` for six faces of sky, and
`{:lit, paint, lighting}` for dynamic lights added to a flat surface. Both are in
`Cauldron3D.Paint.Rgba`.

## A first picture

```elixir
palette = :binary.copy(<<0, 0, 0>>, 256)

camera = Cauldron3D.Camera.first_person({0.0, 0.0, 0.0}, 0.0, 0.0)
view = Cauldron3D.View.new(camera, {64, 48})

square = %Cauldron3D.Polygon{
  points: [
    {100.0, 30.0, -30.0},
    {100.0, -30.0, -30.0},
    {100.0, -30.0, 30.0},
    {100.0, 30.0, 30.0}
  ],
  paint: {:flat, {200, 60, 40}}
}

frame = Cauldron3D.Render.draw(view, [square], palette: palette)
rgba = Cauldron3D.Frame.rgba(frame, nil)
```

The polygon stands in front of the camera at `x` 100, and the frame is RGBA because of
`:palette`. For an indexed frame, give the paint a palette index and read the frame
through the palette.

## Drawing a world

```elixir
camera = Cauldron3D.Camera.first_person({0.0, 0.0, 48.0}, yaw, pitch)
view = Cauldron3D.View.new(camera, {320, 200}, pixel_aspect: 1.0)
cache = Cauldron3D.Bsp.Surfaces.new()
light = %{table: colormap, rows: 64, styles: %{0 => 256}, unlit: 255}

polygons =
  Cauldron3D.Bsp.Draw.polygons(bsp, view, surfaces: cache, light: light) ++
    Cauldron3D.Mesh.polygons(mesh, frame: 4, origin: origin, yaw: facing, light: 160)

frame = Cauldron3D.Render.draw(view, polygons, light_table: colormap)
Cauldron3D.Frame.rgba(frame, palette)
```

`colormap` is a light table, `bsp` a world from `cauldron_3d_formats` or your own loader,
and `mesh` a model. `Cauldron3D.Bsp.Draw.polygons/3` gives the faces of the leaves the
camera's leaf can see, plus the brush models placed with `:models`, and chooses a mip
level by distance. Liquid faces ripple, sky faces show their layers, hidden faces are left
out.

Give a polygon `clear:` to make it see-through where its paint is that colour, and
`depth: :always` to draw it over everything, as for a held weapon. See-through,
always-on-top and blended polygons are painted after the solid ones: the unblended first,
then the blended in the order given.

## What it does not do

It is a renderer and a collision library, not a scene description.

* It does not read files. `cauldron_3d_formats` reads Quake and Half-Life files into
  these structures; glTF and VRM it reads into documents a scene converter uploads.
* It does not draw a window or a terminal. It answers a `Cauldron3D.Frame`; turning
  those bytes into a picture is the front end's job. `Cauldron3D.Frame.rgba/2` gives
  bytes `Cauldron2D.Raster.from_rgba/4` takes for a terminal.
* It has no depth buffer. Polygons are painted by the run that owns each pixel, so order
  comes from distance, not from a buffer you can read or write.
* It has no dynamic shadows, reflections, refraction, fog, bloom or upscaling. BSP light is
  baked into lightmaps; a mesh is lit per vertex from a light value or a direction; a
  light table is what a palette game calls lighting.
* It has no shaders. Paints are the list above, and `{:fun, ...}` is the way to paint
  something the list does not cover.
* Textures repeat and are sampled at the nearest texel; there is no filtering. The only
  mip choice is the one `Cauldron3D.Bsp.Draw.polygons/3` makes for a face.
* It animates a mesh by blending keyframes (`Cauldron3D.Mesh.polygons/2` with
  `frame: {from, to, t}`) and a skeleton by posing bones. A timeline, blending between
  animations, or events on frames is yours.

## What it costs

A frame costs what its polygons and pixels cost. Before any pixel is painted, every
polygon is clipped, projected and set up; that work is split into chunks and run across
schedulers. The picture is cut into bands of rows, one per scheduler by default, and each
band receives only the polygons that cross its rows. Set `:bands` on
`Cauldron3D.Render.draw/3` or `Cauldron3D.Render.draw_setups/3` to choose how many.

Fill is usually the larger cost on a big picture. A 320×200 indexed frame is 64,000
bytes and a full-screen polygon writes all of them; the same frame in RGBA writes four
times as much.
Textured and lit runs are filled in C where the native library loaded
(`Cauldron3D.Paint.Spans.available?/0`), and RGBA layering in
`Cauldron3D.Frame.Pixels`; without a C compiler the same bytes are made in Elixir,
more slowly.

A BSP world pays once per surface. `Cauldron3D.Bsp.Surfaces.fetch/5` builds a face's lit
texture at a mip level and keeps it in an ETS table until its light changes, so a
static world with a static light spends its ticks on the polygons, not on the light.

Building the list is a cost too. `Cauldron3D.Bsp.Draw.polygons/3` walks the leaves the
camera's leaf can see and allocates a polygon for each visible face;
`Cauldron3D.Mesh.polygons/2` allocates a polygon for every triangle.

## Collision

`Cauldron3D.Hull` is a BSP tree of planes whose leaves are contents. A box moves through
a world by tracing a point through a hull pushed out by the box's size, and a world keeps
one hull per box size it allows.

```elixir
hull = Cauldron3D.Hull.box({-16.0, -16.0, -24.0}, {16.0, 16.0, 32.0})
from = {0.0, 0.0, 24.0}
to = {64.0, 0.0, 24.0}
trace = Cauldron3D.Hull.trace(hull, from, to)

trace.fraction
trace.end_pos
trace.normal
```

`Cauldron3D.Move.slide/5` slides along up to four surfaces, and
`Cauldron3D.Move.step/6` also steps up ledges. Both take the trace as a function, so your
game decides what is solid. `Cauldron3D.WalkGrid.build/3` answers where something walking
on a flat floor can go, as a grid of cells seen from above.

| Call | Answers |
| --- | --- |
| `Cauldron3D.Hull.trace/3` | how far a point got, and what stopped it |
| `Cauldron3D.Hull.contents/2` | what a point is inside |
| `Cauldron3D.Move.slide/5` | the origin, velocity and hits after sliding |
| `Cauldron3D.Move.step/6` | the same, after trying a step up |
| `Cauldron3D.WalkGrid.free?/3` | whether a body of a radius fits at a point |

## When to reach for `cauldron_gpu`

| You want | Use |
| --- | --- |
| A window at 1080p or more, redrawn at the display's rate | `cauldron_gpu` |
| Metallic-roughness materials, normal maps, shadows, fog, bloom | `cauldron_gpu` |
| Ray-traced shadows, reflections, occlusion or global illumination | `cauldron_gpu` |
| The same scene in a browser or a Livebook cell | `cauldron_3d_net` or `cauldron_3d_kino` |
| One picture, a HUD, a minimap, or a small pane | this package |
| A machine with no usable graphics card | this package |

The two are not exclusive. A BSP world and its models can be uploaded through
`cauldron_3d_scene` and drawn on the card, while the same game keeps the software
renderer for a machine without one — the scene package's `Cauldron3D.Scene.Software` is
this renderer behind the scene protocol, and the terminal client falls back to it.

## Where to go next

| You want to | Read |
| --- | --- |
| Describe a scene that any renderer can draw | [`cauldron_3d_scene`'s scenes](https://hexdocs.pm/cauldron_3d_scene/scenes.html) |
| Draw it on the graphics card | [`cauldron_gpu`'s gpu](https://hexdocs.pm/cauldron_gpu/gpu.html) |
| Read Quake, glTF or VRM files | [`cauldron_3d_formats`' files](https://hexdocs.pm/cauldron_3d_formats/files.html) |
| Put the frame in a terminal | [`cauldron_2d_drafter`](https://hexdocs.pm/cauldron_2d_drafter) |
