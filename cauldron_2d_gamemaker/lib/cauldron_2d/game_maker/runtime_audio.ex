defmodule Cauldron2D.GameMaker.Runtime.Audio do
  @moduledoc """
  Version inspections of the `SOND` chunk (the 2024.6 layout) and the `AGRP` chunk (the
  2024.14 layout).
  """

  alias Cauldron2D.GameMaker.Bytes
  alias Cauldron2D.GameMaker.Runtime

  @doc "The runtime after inspecting the sound entries of the chunk in `context`."
  @spec probe_sounds(Runtime.t(), Runtime.context()) :: Runtime.t()
  def probe_sounds(runtime, %{data: data, at: at}) do
    if Runtime.current_at_least?(runtime, 2023, 2) and not Runtime.at_least?(runtime, 2024, 6) and
         sound_length?(data, Runtime.live_pointers(data, at)),
       do: Runtime.set(runtime, 2024, 6),
       else: runtime
  end

  @doc "The runtime after inspecting the audio group entries of the chunk in `context`."
  @spec probe_groups(Runtime.t(), Runtime.context()) :: Runtime.t()
  def probe_groups(runtime, %{data: data, at: at, size: size}) do
    if Runtime.at_least?(runtime, 2024, 13) and not Runtime.at_least?(runtime, 2024, 14) and
         group_path?(data, Runtime.live_pointers(data, at), at + size),
       do: Runtime.set(runtime, 2024, 14),
       else: runtime
  end

  defp sound_length?(_data, [first, second | _]), do: first + 36 == second - 4

  defp sound_length?(data, [only]) do
    position = only + 36
    rem(position, 16) == 4 and Bytes.u32(data, position) != 0
  end

  defp sound_length?(_data, []), do: false

  defp group_path?(_data, [], _limit), do: false

  defp group_path?(data, [only], limit),
    do: only + 8 <= limit and Bytes.u32(data, only + 4) != 0

  defp group_path?(_data, [first, second | _], _limit), do: second - first != 4
end
