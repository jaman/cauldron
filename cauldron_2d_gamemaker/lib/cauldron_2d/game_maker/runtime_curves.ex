defmodule Cauldron2D.GameMaker.Runtime.Curves do
  @moduledoc """
  Version inspection of the `ACRV` chunk: the curve point layout of 2.3.1.
  """

  alias Cauldron2D.GameMaker.Bytes
  alias Cauldron2D.GameMaker.Runtime

  @doc "The runtime after inspecting the animation curves of the chunk in `context`."
  @spec probe(Runtime.t(), Runtime.context()) :: Runtime.t()
  def probe(runtime, %{data: data, at: at}) do
    if Runtime.at_least?(runtime, 2, 3, 1) or not bezier_point?(data, aligned(at) + 4),
      do: runtime,
      else: Runtime.set(runtime, 2, 3, 1)
  end

  defp aligned(at) when rem(at, 4) == 0, do: at
  defp aligned(at), do: at + 4 - rem(at, 4)

  defp bezier_point?(data, list) do
    case Bytes.u32(data, list) do
      0 ->
        false

      _ ->
        [first, second] = Bytes.u32s(data, Bytes.u32(data, list + 4) + 8, 2)
        first != 0 or second == 0
    end
  end
end
