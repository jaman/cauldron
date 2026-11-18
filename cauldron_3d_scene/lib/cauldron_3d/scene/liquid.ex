defmodule Cauldron3D.Scene.Liquid do
  @moduledoc """
  How a material shows as standing water (`Cauldron3D.Scene.Material`'s `liquid`): what is
  under it is seen through it, bent by its ripples and tinted by its depth; the sky
  mirrors in it at glancing angles; foam lines its shore.

    * `shallow` — the tint of what lies just under the surface
    * `deep` — the colour the water goes to with depth
    * `clarity` — the depth, in scene units, by which about two thirds of the way to
      `deep` is covered
    * `gloss` — how strongly the sky and the sun mirror in it, 0 to 1
    * `foam` — the foam's colour, and `foam_width` the depth of water it covers at the shore
    * `wave_size` — the length of the longest ripple, `wave_pace` how fast ripples
      travel, `wave_height` how steep they are (0 is flat)
    * `refraction` — how far ripples bend what is seen through the water

      %Cauldron3D.Scene.Material{liquid: %Cauldron3D.Scene.Liquid{deep: {0.02, 0.16, 0.3}}, double_sided: true}
  """

  @type rgb :: {number(), number(), number()}
  @type t :: %__MODULE__{
          shallow: rgb(),
          deep: rgb(),
          clarity: number(),
          gloss: number(),
          foam: rgb(),
          foam_width: number(),
          wave_size: number(),
          wave_pace: number(),
          wave_height: number(),
          refraction: number()
        }

  defstruct shallow: {0.45, 0.85, 0.8},
            deep: {0.03, 0.2, 0.35},
            clarity: 2.5,
            gloss: 0.8,
            foam: {1.0, 1.0, 1.0},
            foam_width: 0.35,
            wave_size: 6.0,
            wave_pace: 1.0,
            wave_height: 0.08,
            refraction: 0.6
end
