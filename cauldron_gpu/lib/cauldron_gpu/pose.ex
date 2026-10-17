defmodule CauldronGPU.Pose do
  @moduledoc """
  How an instance's mesh is bent this tick, applied on the graphics card before drawing,
  shadows and ray tracing.

    * `blend_to` and `blend` — vertex animation: each vertex moves `blend` (0 to 1) of the
      way to the same vertex of `blend_to`, a mesh handle with as many vertices (a later
      keyframe), and the normals with it
    * `bones` — skinning: a list of 3×4 matrices, each 12 numbers row by row, used by a mesh
      uploaded with a `skin` (`CauldronGPU.Mesh`); a vertex becomes the weighted sum of its
      bones' matrices applied to it, after any blending

  Up to 255 bones. A pose with neither leaves the mesh as uploaded.

      {:pose, 7, %CauldronGPU.Pose{blend_to: run_2, blend: 0.4}}
  """

  alias CauldronGPU.Handle

  @type matrix :: [number()]
  @type t :: %__MODULE__{blend_to: Handle.t() | nil, blend: number(), bones: [matrix()]}

  defstruct blend_to: nil, blend: 0.0, bones: []
end
