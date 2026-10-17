defmodule CauldronGPU.Transform do
  @moduledoc """
  Where a scene entry stands: position, rotation (`CauldronGPU.Quat`) and scale, in the
  renderer's frame (right-handed, +Y up, units are metres by convention).
  """

  alias CauldronGPU.Quat

  @type vec3 :: {number(), number(), number()}
  @type t :: %__MODULE__{position: vec3(), rotation: Quat.t(), scale: vec3()}

  defstruct position: {0.0, 0.0, 0.0}, rotation: {0.0, 0.0, 0.0, 1.0}, scale: {1.0, 1.0, 1.0}

  @doc "A transform from keyword fields; `scale` may be one number for all three axes."
  @spec new(keyword()) :: t()
  def new(fields \\ []) do
    fields = Keyword.update(fields, :scale, {1.0, 1.0, 1.0}, &uniform/1)
    struct!(__MODULE__, fields)
  end

  defp uniform(scale) when is_number(scale), do: {scale, scale, scale}
  defp uniform({_, _, _} = scale), do: scale
end
