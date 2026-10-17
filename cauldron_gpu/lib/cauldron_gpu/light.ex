defmodule CauldronGPU.Light do
  @moduledoc """
  A light in the scene. `:directional` lights shine along `direction` from everywhere;
  `:point` lights shine from `position` out to `range`; `:spot` lights also narrow to a
  cone around `direction`, full inside `inner_cone` radians and none past `outer_cone`.
  `intensity` scales `color`. The first directional light with `shadows: true` casts
  shadows.
  """

  @type vec3 :: {number(), number(), number()}
  @type t :: %__MODULE__{
          kind: :directional | :point | :spot,
          color: vec3(),
          intensity: number(),
          position: vec3(),
          direction: vec3(),
          range: number(),
          inner_cone: number(),
          outer_cone: number(),
          shadows: boolean()
        }

  defstruct kind: :point,
            color: {1.0, 1.0, 1.0},
            intensity: 1.0,
            position: {0.0, 0.0, 0.0},
            direction: {0.0, -1.0, 0.0},
            range: 10.0,
            inner_cone: 0.4,
            outer_cone: 0.6,
            shadows: false
end
