defmodule CauldronGPU.Material do
  @moduledoc """
  How a surface reflects light, in glTF's metallic-roughness terms.

  Textures are `CauldronGPU.Handle`s from `CauldronGPU.texture/2`, or `nil`.

    * `base_texture` multiplies `base_color`
    * `metallic_roughness_texture` multiplies `roughness` by its green channel and
      `metallic` by its blue
    * `emissive_texture` multiplies `emissive` (times `emissive_strength`)
    * `normal_texture` bends the surface normal by a tangent-space normal map (red right,
      green up), its sideways part scaled by `normal_scale`
    * `occlusion_texture` darkens ambient and reflected light by its red channel
    * `lightmap` replaces ambient light with baked light read at the vertices' lightmap
      coordinates, scaled by `lightmap_scale`; with `lightmap_styles` above 1 it holds that
      many slots side by side, slot `k` lit by the vertex's `k`-th light style
      (`CauldronGPU.Mesh`) at its brightness from `{:light_styles, …}`

  Pixels whose base alpha is below `alpha_cutoff` are not drawn. `alpha_mode: :blend`
  draws the surface see-through by its base alpha, after the opaque scene, farthest
  instances first; it casts no shadow. `:add` adds its colour times its alpha to what is
  behind it, and `:multiply` multiplies what is behind it by its colour, as far as its alpha
  goes; both are drawn as `:blend` surfaces are. `unlit` surfaces show their base colour as is.

  `uv_scroll`, `{u, v}` in repeats a second, moves the texture coordinates over time.
  `uv_from: :reflection` takes them from the view reflected in the surface instead of the
  mesh: with `r` the reflected direction, `u = 0.5 - r.z / 2` and `v = 0.5 - r.y / 2`
  (environment mapping); `:mesh` is the default.
  `double_sided` surfaces are drawn from behind too.

  A `sky` surface shows the environment's sky (`CauldronGPU.Environment`) seen along the
  view through it, in place of its own colours; it casts no shadow, and rays that reach it
  see the sky. A `warp` surface's texture ripples: each texel is moved by up to 8 texels
  along `sin(texel / 8 + seconds)` of the other axis, as liquids do.

  A surface with `smear` above 0 shows the finished picture behind it instead of its
  texture, times its base colour: the frame is cut into square blocks `smear` of its height
  tall, and each block shows the picture `smear` above or below it, the choice changing
  every frame. Its base texture's alpha below
  `alpha_cutoff` still cuts it out. It is drawn after the opaque scene, as see-through
  surfaces are.

  """

  alias CauldronGPU.Handle

  @type rgb :: {number(), number(), number()}
  @type texture :: Handle.t() | nil
  @type t :: %__MODULE__{
          base_color: {number(), number(), number(), number()},
          base_texture: texture(),
          metallic: number(),
          roughness: number(),
          metallic_roughness_texture: texture(),
          emissive: rgb(),
          emissive_strength: number(),
          emissive_texture: texture(),
          normal_texture: texture(),
          normal_scale: number(),
          occlusion_texture: texture(),
          lightmap: texture(),
          lightmap_scale: number(),
          lightmap_styles: 1..4,
          alpha_cutoff: number(),
          unlit: boolean(),
          alpha_mode: :opaque | :blend | :add | :multiply,
          uv_scroll: {number(), number()},
          uv_from: :mesh | :reflection,
          double_sided: boolean(),
          sky: boolean(),
          warp: boolean(),
          smear: number()
        }

  defstruct base_color: {1.0, 1.0, 1.0, 1.0},
            base_texture: nil,
            metallic: 0.0,
            roughness: 1.0,
            metallic_roughness_texture: nil,
            emissive: {0.0, 0.0, 0.0},
            emissive_strength: 1.0,
            emissive_texture: nil,
            normal_texture: nil,
            normal_scale: 1.0,
            occlusion_texture: nil,
            lightmap: nil,
            lightmap_scale: 1.0,
            lightmap_styles: 1,
            alpha_cutoff: 0.0,
            unlit: false,
            alpha_mode: :opaque,
            uv_scroll: {0.0, 0.0},
            uv_from: :mesh,
            double_sided: false,
            sky: false,
            warp: false,
            smear: 0.0

  @doc "The texture handles `material` uses."
  @spec textures(t()) :: [Handle.t()]
  def textures(%__MODULE__{} = material) do
    Enum.reject(
      [
        material.base_texture,
        material.metallic_roughness_texture,
        material.emissive_texture,
        material.normal_texture,
        material.occlusion_texture,
        material.lightmap
      ],
      &is_nil/1
    )
  end
end
