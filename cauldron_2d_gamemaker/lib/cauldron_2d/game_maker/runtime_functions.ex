defmodule Cauldron2D.GameMaker.Runtime.Functions do
  @moduledoc """
  Version inspection of the `FUNC` chunk: the code locals list that 2024.8 removed.
  """

  alias Cauldron2D.GameMaker.Bytes
  alias Cauldron2D.GameMaker.Chunks
  alias Cauldron2D.GameMaker.Runtime

  @function_size 12

  @doc "The runtime after inspecting the function list of the chunk in `context`."
  @spec probe(Runtime.t(), Runtime.context()) :: Runtime.t()
  def probe(runtime, %{bytecode: bytecode} = context) do
    if bytecode > 14 and Runtime.at_least?(runtime, 2) and not Runtime.at_least?(runtime, 2024, 8) and
         without_locals?(context),
       do: Runtime.set(runtime, 2024, 8),
       else: runtime
  end

  defp without_locals?(%{data: data, at: at, size: size, chunks: chunks}) do
    ending = at + size
    after_functions = at + 4 + @function_size * Bytes.u32(data, at)

    if after_functions == ending do
      true
    else
      case padding_end(data, after_functions, ending, 0) do
        {:ok, ^ending, padding} -> padding < 4 or code_count(data, chunks) > 0
        _ -> false
      end
    end
  end

  defp padding_end(_data, position, _ending, padding) when rem(position, 16) == 0,
    do: {:ok, position, padding}

  defp padding_end(_data, position, ending, _padding) when position >= ending, do: :error

  defp padding_end(data, position, ending, padding) do
    case binary_part(data, position, 1) do
      <<0>> -> padding_end(data, position + 1, ending, padding + 1)
      _ -> :error
    end
  end

  defp code_count(data, chunks) do
    if Chunks.filled?(chunks, "CODE"),
      do: Bytes.u32(data, elem(Map.fetch!(chunks, "CODE"), 0)),
      else: 0
  end
end
