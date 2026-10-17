defmodule CauldronGPU.Sprite do
  @moduledoc """
  A rectangle of a texture placed in a `CauldronGPU.SpriteLayer`.

    * `texture` — the handle of a texture or canvas
    * `source` — `{x, y, width, height}` in the texture's pixels, the part drawn; `nil`
      (the default) draws the whole texture
    * `position` — `{x, y}` in the layer's view, where the sprite's origin lands
    * `origin` — `{x, y}` in the source's pixels, the point placed at `position` and
      turned about; default `{0, 0}`
    * `scale` — `{x, y}`; negative mirrors, zero draws nothing; default `{1, 1}`
    * `angle` — degrees, counter-clockwise as seen; exact at whole quarter turns
    * `colour` — `{r, g, b}` from 0 to 1, multiplied into the texture's colours
    * `alpha` — 0 to 1, multiplied into the texture's alpha
    * `mode` — `:over` (the default), `:add` or `:subtract`

  Colours are display values: they are blended as stored, with no conversion to linear
  light. A pixel is drawn when its centre lies inside the turned and scaled rectangle;
  it takes the texture's sample at that point, by the texture's own filter.

  `:over` lays the colour over what is there by its alpha. `:add` adds the colour times
  its alpha, each channel at most 1, and adds the alpha. `:subtract` multiplies each
  channel by one less the colour times its alpha, keeping the alpha.
  """

  alias CauldronGPU.Handle

  @type t :: %__MODULE__{
          texture: Handle.t(),
          source: {number(), number(), number(), number()} | nil,
          position: {number(), number()},
          origin: {number(), number()},
          scale: {number(), number()},
          angle: number(),
          colour: {number(), number(), number()},
          alpha: number(),
          mode: :over | :add | :subtract
        }

  @enforce_keys [:texture, :position]
  defstruct [
    :texture,
    :position,
    source: nil,
    origin: {0, 0},
    scale: {1, 1},
    angle: 0,
    colour: {1.0, 1.0, 1.0},
    alpha: 1.0,
    mode: :over
  ]
end
