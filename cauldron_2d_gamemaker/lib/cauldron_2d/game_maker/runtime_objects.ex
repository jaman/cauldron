defmodule Cauldron2D.GameMaker.Runtime.Objects do
  @moduledoc """
  Version inspection of the `OBJT` chunk: the managed flag present from 2022.5 and
  dropped again in 2026.1.
  """

  alias Cauldron2D.GameMaker.Bytes
  alias Cauldron2D.GameMaker.Runtime

  @event_types 15

  @doc "The runtime after inspecting the objects of the chunk in `context`."
  @spec probe(Runtime.t(), Runtime.context()) :: Runtime.t()
  def probe(runtime, context) do
    if Runtime.at_least?(runtime, 2, 3) and not settled?(runtime),
      do: infer(runtime, context),
      else: runtime
  end

  defp settled?(runtime),
    do: Runtime.at_least?(runtime, 2022, 5) and not Runtime.at_least?(runtime, 2024, 13)

  defp infer(runtime, %{data: data, at: at, size: size}) do
    cond do
      managed_flag?(data, at, at + size) -> Runtime.raise_to(runtime, 2022, 5)
      Runtime.at_least?(runtime, 2024, 13) -> Runtime.set(runtime, 2026, 1)
      true -> runtime
    end
  end

  defp managed_flag?(data, at, limit) do
    case Bytes.u32(data, at) do
      0 -> false
      _ -> events_follow_vertices?(data, Bytes.u32(data, at + 4), limit)
    end
  end

  defp events_follow_vertices?(data, object, limit) do
    vertices = Bytes.u32(data, object + 64)
    events = object + 68 + 12 + vertices * 8

    if events < limit,
      do: not (Bytes.u32(data, events) == @event_types and sub_lists_follow?(data, events + 4)),
      else: true
  end

  defp sub_lists_follow?(data, pointer_at), do: pointer_at + 60 == Bytes.u32(data, pointer_at)
end
