defmodule Cauldron3D.Scene.Pose do
  @moduledoc """
  How an instance's mesh is bent this tick, applied on the graphics card before drawing,
  shadows and ray tracing.

    * `blend_to` and `blend` — vertex animation: each vertex moves `blend` (0 to 1) of the
      way to the same vertex of `blend_to`, a mesh handle with as many vertices (a later
      keyframe), and the normals with it
    * `bones` — skinning: a list of 3×4 matrices, each 12 numbers row by row, used by a mesh
      uploaded with a `skin` (`Cauldron3D.Scene.Mesh`); a vertex becomes the weighted sum of its
      bones' matrices applied to it, after any blending
    * `weights` — morph targets: how far each of the mesh's `morphs` is applied (0 to 1, in
      the order uploaded), before skinning; weights beyond the mesh's targets are ignored

  Up to 255 bones and 64 weights. A pose with none of them leaves the mesh as uploaded.

      {:pose, 7, %Cauldron3D.Scene.Pose{blend_to: run_2, blend: 0.4}}
  """

  alias Cauldron3D.Scene.Handle

  @type matrix :: [number()]
  @type t :: %__MODULE__{
          blend_to: Handle.t() | nil,
          blend: number(),
          bones: [matrix()],
          weights: [number()]
        }

  defstruct blend_to: nil, blend: 0.0, bones: [], weights: []
end
