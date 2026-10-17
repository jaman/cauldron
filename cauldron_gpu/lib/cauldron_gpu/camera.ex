defmodule CauldronGPU.Camera do
  @moduledoc """
  The eye: a position and a rotation (looking down its -Z with +Y up), a vertical field of
  view in radians, and near and far distances. `snap: true` places it without
  interpolating from where it was on the previous tick.

  `viewport` is the part of the frame the view is drawn into, `{x, y, width, height}` as
  fractions of the frame from its top left; the rest of the frame is black under the
  overlay. `aspect` is how wide the viewport shows on screen against its height, for
  frames whose pixels are not square; `nil` takes it from the viewport's pixels.
  `resolution`, `{columns, rows}`, shows the view as that many blocks across and down its
  viewport, each the colour at its centre; `nil` shows every pixel.
  """

  alias CauldronGPU.Quat

  @type t :: %__MODULE__{
          position: {number(), number(), number()},
          rotation: Quat.t(),
          fov_y: number(),
          near: number(),
          far: number(),
          snap: boolean(),
          viewport: {number(), number(), number(), number()},
          aspect: number() | nil,
          resolution: {pos_integer(), pos_integer()} | nil
        }

  defstruct position: {0.0, 0.0, 0.0},
            rotation: {0.0, 0.0, 0.0, 1.0},
            fov_y: 1.2,
            near: 0.05,
            far: 1000.0,
            snap: false,
            viewport: {0.0, 0.0, 1.0, 1.0},
            aspect: nil,
            resolution: nil
end
