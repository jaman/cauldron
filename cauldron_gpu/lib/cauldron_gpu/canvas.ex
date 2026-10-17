defmodule CauldronGPU.Canvas do
  @moduledoc """
  A picture the renderer draws into: `width` × `height` RGBA pixels kept on the card. A
  canvas is a texture, so its handle can be drawn by sprites, warped by a column layer,
  shown as the overlay or used by a material. It starts transparent.

  `filter` is how it is sampled where it is drawn: `:nearest` (the default) or `:linear`.

      canvas = CauldronGPU.canvas(gpu, %CauldronGPU.Canvas{width: 320, height: 200})
  """

  @type t :: %__MODULE__{
          width: pos_integer(),
          height: pos_integer(),
          filter: :nearest | :linear
        }

  @enforce_keys [:width, :height]
  defstruct [:width, :height, filter: :nearest]
end
