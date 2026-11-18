defmodule Cauldron3D.Scene.Capabilities do
  @moduledoc """
  What a renderer can do with a scene, beyond drawing it: the effects a game may ask for
  with `{:effects, [...]}` in a change list, as `Cauldron3D.Scene.Target.capabilities/1`
  reports them. A renderer ignores an effect it lacks, so a game reads these to offer the
  player only what will show.

    * `:ray_tracing` — `:ray_traced_shadows`, `:ray_traced_reflections`,
      `:ray_traced_ambient_occlusion` and `:ray_traced_global_illumination`
    * `:upscaling` — `:upscaling`, drawing at a lower size and scaling up
    * `:frame_generation` — frames made between the drawn ones

      if Cauldron3D.Scene.Target.capabilities(target).ray_tracing,
        do: [:ray_traced_shadows],
        else: []
  """

  @type t :: %__MODULE__{
          ray_tracing: boolean(),
          upscaling: boolean(),
          frame_generation: boolean()
        }

  defstruct ray_tracing: false, upscaling: false, frame_generation: false

  @doc "The capabilities a renderer's info map gives (any of its keys `:ray_tracing`, `:upscaling`, `:frame_generation`)."
  @spec from_info(map()) :: t()
  def from_info(info) do
    %__MODULE__{
      ray_tracing: Map.get(info, :ray_tracing, false),
      upscaling: Map.get(info, :upscaling, false),
      frame_generation: Map.get(info, :frame_generation, false)
    }
  end
end
