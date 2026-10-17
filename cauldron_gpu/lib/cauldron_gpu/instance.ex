defmodule CauldronGPU.Instance do
  @moduledoc """
  A mesh placed in the scene with one material per mesh part (the last material serves
  any further parts). `hidden` instances are kept but not drawn; `shadows: false` keeps
  an instance out of the shadow map; `snap: true` places it without interpolating from
  its previous tick.

  `in_front: true` draws the instance over the rest of the scene, as a held weapon is: it
  is hidden only by itself and by surfaces closer than about the camera's near distance,
  casts no shadow and is not seen by rays.

  `shading` lights the instance by a fixed rule in place of the scene's lights and its
  materials' lightmaps: `{ambient, directional, direction}`, two `{r, g, b}` and a unit
  direction towards the light, give `ambient + directional * dot(normal, direction)`,
  never below zero, as baked light.

  `depth_test: false` draws the instance over everything before it, after the opaque scene,
  farthest instance first, and hides nothing. `swell`, `{width, height, speed}`, pushes
  each vertex out along its normal by `height * sin(u * width + seconds * speed)`, `u` its
  texture coordinate (a bulging shell).

  `standing`, `{floor, ceiling}` heights in the renderer's frame, is for a thing standing
  in a room: floors seen from above at or below `floor` and ceilings seen from below at or
  above `ceiling` (surfaces within 45 degrees of level) do not hide it, so it shows whole
  where it sinks into its own floor or reaches into its own ceiling; every other nearer
  surface hides it as usual. It
  is drawn after the opaque scene, farthest instance first, and casts no shadow.
  """

  alias CauldronGPU.{Handle, Transform}

  @type t :: %__MODULE__{
          mesh: Handle.t(),
          materials: [Handle.t()],
          transform: Transform.t(),
          hidden: boolean(),
          shadows: boolean(),
          snap: boolean(),
          in_front: boolean(),
          shading: {rgb(), rgb(), {number(), number(), number()}} | nil,
          depth_test: boolean(),
          swell: {number(), number(), number()} | nil,
          standing: {number(), number()} | nil
        }
  @type rgb :: {number(), number(), number()}

  @enforce_keys [:mesh]
  defstruct [
    :mesh,
    materials: [],
    transform: %Transform{},
    hidden: false,
    shadows: true,
    snap: false,
    in_front: false,
    shading: nil,
    depth_test: true,
    swell: nil,
    standing: nil
  ]
end
