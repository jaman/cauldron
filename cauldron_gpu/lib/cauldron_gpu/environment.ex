defmodule CauldronGPU.Environment do
  @moduledoc """
  What surrounds the scene: a sky shaded from `sky_top` through `sky_horizon` to
  `sky_ground`, `ambient` light at `ambient_intensity` for surfaces without a lightmap,
  exponential fog of `fog_color` thickening at `fog_density` per unit, `exposure`
  before tone mapping, and `shadow_distance`, the half width of the square around the
  camera that the shadow-casting light covers, and `reflections`, how strongly surfaces
  mirror the sky. With ray-traced ambient occlusion requested, `ao_radius` is how far
  occluders are looked for and `ao_strength` how much they darken (0 to 1). With
  upscaling requested, frames are drawn at `render_scale` of the window's size (0.25 to
  1) and upscaled to it. Light brighter than `bloom_threshold` spreads into a glow added at
  `bloom_strength` (0 turns it off). `tone_map` turns light into screen colour: `:aces` (filmic,
  deep shadows), `:neutral` (keeps dark colours, rolls off highlights) or `:clamp` (no curve).

  `sky_picture` puts a picture in the sky in place of the shading, seen wherever nothing
  is drawn and on `sky` surfaces (`CauldronGPU.Material`):

    * `{:layers, back, front}` — two texture handles on a low dome overhead: the view's
      direction with its height stretched three times picks the point, about three
      repeats from the dome's centre to its rim, `front` over `back` by its alpha. Each
      layer drifts diagonally at its `sky_scroll` (`{back, front}`, repeats a second)
    * `{:box, %{pos_x:, neg_x:, pos_y:, neg_y:, pos_z:, neg_z:}}` — six texture handles,
      the faces of a box around the camera, each seen from inside with its first row at
      the top: `pos_x` has -Z on its right, `neg_x` +Z, `pos_z` +X and `neg_z` -X, all
      four with +Y at the top; `pos_y` and `neg_y` have +X on their right, `pos_y` +Z
      at its bottom and `neg_y` -Z at its bottom

  The caller keeps the handles a sky picture uses.

  `light_space: :display` lights surfaces with baked light (lightmaps and instances'
  `shading`) as palette games do: the texture's display colour times the light, in place of
  physically lit linear colour. Point, spot and directional lights then add to that light by
  the same rule: `colour * intensity * max(dot(normal, to_light), 0)`, times
  `max(1 - distance² / range², 0)` for point and spot lights, and for spot lights times
  `max(1 - x² - y², 0)`, `x` and `y` the point's offsets across the cone divided by the
  cone's half width at its distance (the outer cone angle).

  The finished picture's display values `v` become
  `clamp(v ** gamma * contrast + brightness, 0, 1)` before the screen tint and the overlay;
  a `gamma` below 1 brightens.

  `light_table`, `{texture, reach}`, turns baked light into light that falls with
  distance: each channel of the light (0 to 1, after light styles and the lightmap's scale)
  picks the column and the depth along the camera's view over `reach` the row (clamped) of
  `texture`, whose same
  channel is the light shown. The caller keeps the handle.
  """

  @type rgb :: {number(), number(), number()}
  @type t :: %__MODULE__{
          sky_top: rgb(),
          sky_horizon: rgb(),
          sky_ground: rgb(),
          ambient: rgb(),
          ambient_intensity: number(),
          fog_color: rgb(),
          fog_density: number(),
          exposure: number(),
          shadow_distance: number(),
          reflections: number(),
          ao_radius: number(),
          ao_strength: number(),
          render_scale: number(),
          bloom_strength: number(),
          bloom_threshold: number(),
          tone_map: :aces | :neutral | :clamp,
          sky_picture: sky_picture(),
          sky_scroll: {number(), number()},
          light_space: :linear | :display,
          gamma: number(),
          contrast: number(),
          brightness: number(),
          light_table: {CauldronGPU.Handle.t(), number()} | nil
        }
  @type sky_picture ::
          nil
          | {:layers, CauldronGPU.Handle.t(), CauldronGPU.Handle.t()}
          | {:box, %{atom() => CauldronGPU.Handle.t()}}

  defstruct sky_top: {0.25, 0.45, 0.85},
            sky_horizon: {0.75, 0.85, 0.95},
            sky_ground: {0.25, 0.22, 0.2},
            ambient: {0.4, 0.45, 0.5},
            ambient_intensity: 0.3,
            fog_color: {0.7, 0.8, 0.9},
            fog_density: 0.0,
            exposure: 1.0,
            shadow_distance: 60.0,
            reflections: 1.0,
            ao_radius: 1.0,
            ao_strength: 1.0,
            render_scale: 0.5,
            bloom_strength: 0.05,
            bloom_threshold: 1.0,
            tone_map: :aces,
            sky_picture: nil,
            sky_scroll: {0.0625, 0.125},
            light_space: :linear,
            gamma: 1.0,
            contrast: 1.0,
            brightness: 0.0,
            light_table: nil
end
