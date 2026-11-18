defmodule Cauldron3D.Scene.Canvas do
  @moduledoc """
  A picture the renderer draws into: `width` × `height` RGBA pixels kept on the card. A
  canvas is a texture, so its handle can be drawn by sprites, warped by a column layer,
  shown as the overlay or used by a material. It starts transparent.

  `filter` is how it is sampled where it is drawn: `:nearest` (the default) or `:linear`.

  `srgb` (default `false`) makes the canvas hold sRGB colours as a picture does, so a material that
  uses it as a texture shows the colours that were drawn. Only `Cauldron3D.Scene.TileLayer`s,
  `Cauldron3D.Scene.ShadowLayer`s and `Cauldron3D.Scene.PriorityLayer`s draw into such a canvas. On the native renderer a sprite layer that draws it into another target
  takes its colours as linear light, so make a canvas that sprites or the overlay show with `srgb: false`.

      canvas = CauldronGPU.canvas(gpu, %Cauldron3D.Scene.Canvas{width: 320, height: 200})
  """

  @type t :: %__MODULE__{
          width: pos_integer(),
          height: pos_integer(),
          filter: :nearest | :linear,
          srgb: boolean()
        }

  @enforce_keys [:width, :height]
  defstruct [:width, :height, filter: :nearest, srgb: false]
end
