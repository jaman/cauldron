defmodule Cauldron3D.Polygon do
  @moduledoc """
  A flat, convex polygon in the world, and how it is painted.

      %Cauldron3D.Polygon{
        points: [{0.0, 0.0, 0.0}, {64.0, 0.0, 0.0}, {64.0, 0.0, 64.0}],
        uvs: [{0.0, 0.0}, {64.0, 0.0}, {64.0, 64.0}],
        paint: {:texture, texture, 128}
      }

  `uvs` give each point's place on the paint, in its pixels; `lights` each point's light,
  0 to 255 with 128 as the picture's own colours, carried across the polygon for
  `{:shaded, texture}`. `cull` drops the polygon when its points run that way round on
  the screen: `:clockwise`, `:counter_clockwise`, or `:none` to keep both faces.

  In a picture drawn in full colour, `tints` gives each point a `{r, g, b, a}` that its
  paint's colour and alpha are multiplied by (1.0 leaves them as they are), carried
  across the polygon with the perspective; `blend` mixes the polygon with what is behind
  it: `{:alpha, amount}` lays it over at `amount` (0.0 to 1.0) times its alpha,
  `{:add, amount}` adds `amount` times its alpha of its colour to what is there,
  `{:premultiplied, amount}` adds `amount` of its colour (already multiplied by its
  alpha) to what is there kept at one minus `amount` times its alpha, and
  `{:darken, amount}` multiplies what is there by one minus `amount` of its colour.

  A polygon with a `clear` colour is see-through where its paint is that colour, and one
  with an `alpha_test` (0.0 to 1.0) where its paint's own alpha is below it; an unblended
  polygon that is see-through in places still hides what is behind it where it is not.
  `depth: :always` draws it over everything whatever its distance; `depth: :near_third`
  keeps its depth in the nearest third of the depth range, so that it is in front of
  everything else but what lies within half the near distance beyond the near plane,
  and is still in front or behind among its own kind.

  Blended, see-through and always-on-top polygons are drawn after the others, the
  unblended first, then the blended in the order given.

  The paints are those `Cauldron3D.Paint` draws.
  """

  alias Cauldron3D.Vec

  @type blend ::
          :none
          | {:alpha, float()}
          | {:add, float()}
          | {:premultiplied, float()}
          | {:darken, float()}
  @type tint :: {float(), float(), float(), float()}

  @type t :: %__MODULE__{
          points: [Vec.t()],
          uvs: [{float(), float()}] | nil,
          lights: [float()] | nil,
          tints: [tint()] | nil,
          paint: term(),
          cull: :none | :clockwise | :counter_clockwise,
          clear: byte() | nil,
          alpha_test: float() | nil,
          depth: :test | :always | :near_third,
          blend: blend()
        }

  defstruct points: [],
            uvs: nil,
            lights: nil,
            tints: nil,
            paint: {:flat, 0},
            cull: :none,
            clear: nil,
            alpha_test: nil,
            depth: :test,
            blend: :none

  @doc "The polygon moved by `offset`."
  @spec translate(t(), Vec.t()) :: t()
  def translate(%__MODULE__{} = polygon, offset),
    do: %{polygon | points: Enum.map(polygon.points, &Vec.add(&1, offset))}
end
