defmodule Cauldron2D.GameMaker.Runtime.Extensions do
  @moduledoc """
  Version inspections of the `EXTN` chunk: the layouts added in 2022.6 and 2023.4.
  """

  alias Cauldron2D.GameMaker.Bytes
  alias Cauldron2D.GameMaker.Runtime

  @doc "The runtime after inspecting the extension list of the chunk in `context`."
  @spec probe(Runtime.t(), Runtime.context()) :: Runtime.t()
  def probe(runtime, context) do
    runtime
    |> since_2022_6(context)
    |> since_2023_4(context)
  end

  defp since_2022_6(runtime, context) do
    if Runtime.at_least?(runtime, 2, 3) and not Runtime.at_least?(runtime, 2022, 6) and
         padded_extensions?(context),
       do: Runtime.set(runtime, 2022, 6),
       else: runtime
  end

  defp since_2023_4(runtime, %{data: data, at: at}) do
    if Runtime.at_least?(runtime, 2022, 6) and not Runtime.at_least?(runtime, 2023, 4) and
         string_before_files?(data, at),
       do: Runtime.set(runtime, 2023, 4),
       else: runtime
  end

  defp padded_extensions?(%{data: data, at: at, size: size}) do
    limit = at + size

    case Bytes.i32(data, at) do
      count when count > 0 ->
        first = Bytes.u32(data, at + 4)
        expected_end = if count >= 2, do: Bytes.u32(data, at + 8), else: limit
        extension_end(data, first + 12, limit, count) == {:ok, expected_end}

      _ ->
        false
    end
  end

  defp extension_end(data, at, limit, count) do
    [files, options] = Bytes.u32s(data, at, 2)
    after_pointers = at + 8

    with true <- files == after_pointers,
         true <- options > after_pointers and options < limit,
         {:ok, position} <- after_options(data, options, limit) do
      {:ok, align_single(position, count)}
    else
      _ -> :error
    end
  end

  defp after_options(data, options, limit) do
    case Bytes.u32(data, options) do
      0 ->
        {:ok, options + 4}

      count ->
        last = options + 4 + 4 * (count - 1)
        reached = if last < limit, do: Bytes.u32(data, last) + 12
        if reached && reached < limit, do: {:ok, reached}, else: :error
    end
  end

  defp align_single(position, 1), do: align(position + 16)
  defp align_single(position, _count), do: position

  defp align(position) when rem(position, 16) == 0, do: position
  defp align(position), do: position + 16 - rem(position, 16)

  defp string_before_files?(data, at) do
    case Bytes.i32(data, at) do
      count when count > 0 ->
        first = Bytes.u32(data, at + 4)
        [files, options] = Bytes.u32s(data, first + 12, 2)
        files > options

      _ ->
        false
    end
  end
end
