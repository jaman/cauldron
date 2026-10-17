defmodule Cauldron2D.GameMaker.Runtime.Particles do
  @moduledoc """
  Version inspection of the `PSEM` chunk: the emitter sizes of 2023.4, 2023.6 and 2023.8.
  """

  alias Cauldron2D.GameMaker.Bytes
  alias Cauldron2D.GameMaker.Runtime

  @doc "The runtime after inspecting the emitters of the chunk in `context`."
  @spec probe(Runtime.t(), Runtime.context()) :: Runtime.t()
  def probe(runtime, context) do
    if Runtime.at_least?(runtime, 2023, 8), do: runtime, else: emitters(runtime, context)
  end

  defp emitters(runtime, %{data: data, at: at, size: size}) do
    list = aligned(at) + 4
    count = Bytes.u32(data, list)
    runtime = if count < 11, do: Runtime.raise_to(runtime, 2023, 4), else: runtime

    case count do
      0 -> runtime
      1 -> from_chunk_size(runtime, size)
      _ -> from_emitter_gap(runtime, Bytes.u32(data, list + 8) - Bytes.u32(data, list + 4))
    end
  end

  defp from_chunk_size(runtime, 0xF8), do: Runtime.raise_to(runtime, 2023, 8)
  defp from_chunk_size(runtime, 0xD8), do: Runtime.raise_to(runtime, 2023, 6)
  defp from_chunk_size(runtime, 0xC8), do: Runtime.raise_to(runtime, 2023, 4)
  defp from_chunk_size(runtime, _size), do: runtime

  defp from_emitter_gap(runtime, 0xEC), do: Runtime.raise_to(runtime, 2023, 8)
  defp from_emitter_gap(runtime, 0xC0), do: Runtime.raise_to(runtime, 2023, 6)
  defp from_emitter_gap(runtime, 0xBC), do: Runtime.raise_to(runtime, 2023, 4)
  defp from_emitter_gap(runtime, _gap), do: runtime

  defp aligned(at) when rem(at, 4) == 0, do: at
  defp aligned(at), do: at + 4 - rem(at, 4)
end
