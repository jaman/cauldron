defmodule Cauldron2D.GameMaker.Runtime.Fonts do
  @moduledoc """
  Version inspections of the `FONT` chunk: the ascender added in 2022.2, the line
  height added in 2023.6, the glyph field added in 2024.11 and the alignment added in
  2024.14.
  """

  alias Cauldron2D.GameMaker.Bytes
  alias Cauldron2D.GameMaker.Runtime

  @table_size 512

  @doc "The runtime after inspecting the fonts of the chunk in `context`."
  @spec probe(Runtime.t(), Runtime.context()) :: Runtime.t()
  def probe(runtime, context) do
    runtime
    |> ascender(context)
    |> line_height(context)
    |> alignment(context)
  end

  defp ascender(runtime, %{bytecode: bytecode, data: data, at: at, size: size}) do
    if bytecode >= 17 and not Runtime.at_least?(runtime, 2022, 2) and
         ascender_layout?(data, at, size),
       do: Runtime.set(runtime, 2022, 2),
       else: runtime
  end

  defp ascender_layout?(data, at, size) do
    case Runtime.live_pointers(data, at) do
      [font | _] -> glyphs_back_to_back?(data, font + 48, size)
      [] -> false
    end
  end

  defp glyphs_back_to_back?(data, list, size) do
    count = Bytes.u32(data, list)

    cond do
      count * 4 > size -> false
      count == 0 -> true
      true -> chained?(data, list + 4, count)
    end
  end

  defp chained?(data, list, count) do
    pointers = Bytes.u32s(data, list, count)

    Enum.all?(pointers) and
      match?({:ok, _}, walk_plain(data, pointers, list + 4 * count))
  end

  defp walk_plain(_data, [], position), do: {:ok, position}

  defp walk_plain(data, [pointer | rest], position) when pointer == position do
    walk_plain(data, rest, position + 16 + 4 * Bytes.u16(data, position + 14))
  end

  defp walk_plain(_data, _pointers, _position), do: :error

  defp line_height(runtime, %{data: data, at: at, size: size}) do
    if Runtime.at_least?(runtime, 2022, 8) and not later_layout_known?(runtime) do
      line_height_layout(runtime, data, at, size)
    else
      runtime
    end
  end

  defp later_layout_known?(runtime) do
    (Runtime.at_least?(runtime, 2023, 6) and not Runtime.at_least?(runtime, 2024, 6)) or
      Runtime.at_least?(runtime, 2024, 11)
  end

  defp line_height_layout(runtime, data, at, size) do
    case font_bounds(data, at, size) do
      nil -> runtime
      {font, following} -> glyph_layout(runtime, data, font, following)
    end
  end

  defp font_bounds(data, at, size) do
    case data |> Bytes.pointers(at) |> Enum.reject(&(&1 == 0)) |> Enum.take(2) do
      [] -> nil
      [font] -> {font, at + size - @table_size}
      [font, following] -> {font, following}
    end
  end

  defp glyph_layout(runtime, data, font, following) do
    sdf = if Runtime.current_at_least?(runtime, 2023, 2), do: 4, else: 0
    list = font + 52 + sdf
    count = Bytes.u32(data, list)

    cond do
      count * 4 > following - (list + 4) -> runtime
      count == 0 -> Runtime.raise_to(runtime, 2023, 6)
      true -> glyph_kind(runtime, data, list, count, following)
    end
  end

  defp glyph_kind(runtime, data, list, count, following) do
    pointers = Bytes.u32s(data, list + 4, count)

    if Enum.all?(pointers) do
      case walk(data, pointers, list + 4 + 4 * count, following, :unknown) do
        :padded -> Runtime.set(runtime, 2024, 11)
        :plain -> Runtime.raise_to(runtime, 2023, 6)
        :broken -> runtime
      end
    else
      runtime
    end
  end

  defp walk(_data, [], _position, _following, :padded), do: :padded
  defp walk(_data, [], _position, _following, _mode), do: :plain

  defp walk(_data, [pointer | _rest], position, _following, _mode) when pointer != position,
    do: :broken

  defp walk(data, [_pointer | rest], position, following, mode) do
    {mode, ending} = glyph_end(data, position, List.first(rest) || following, mode)
    walk(data, rest, ending, following, mode)
  end

  defp glyph_end(data, glyph, _next, :plain),
    do: {:plain, glyph + 16 + 4 * Bytes.u16(data, glyph + 14)}

  defp glyph_end(data, glyph, _next, :padded),
    do: {:padded, glyph + 18 + 4 * Bytes.u16(data, glyph + 16)}

  defp glyph_end(data, glyph, next, :unknown) do
    plain_end = glyph + 16 + 4 * Bytes.u16(data, glyph + 14)

    if plain_end == next,
      do: {:plain, plain_end},
      else: {:padded, glyph + 18 + 4 * Bytes.u16(data, glyph + 16)}
  end

  defp alignment(runtime, %{data: data, at: at, size: size}) do
    if Runtime.at_least?(runtime, 2024, 13) and not Runtime.at_least?(runtime, 2024, 14) and
         unpadded_table?(data, at, size),
       do: Runtime.set(runtime, 2024, 14),
       else: runtime
  end

  defp unpadded_table?(data, at, size) do
    list_end = at + 4 + 4 * Bytes.u32(data, at)

    ending =
      case data |> Bytes.pointers(at) |> Enum.reject(&(&1 == 0)) |> List.last() do
        nil -> list_end
        font -> font_end(data, font)
      end

    ending != nil and ending + @table_size > at + size
  end

  defp font_end(data, font) do
    case Bytes.u32(data, font + 56) do
      0 ->
        nil

      glyphs ->
        last = Bytes.u32(data, font + 60 + 4 * (glyphs - 1))
        last + 18 + 4 * Bytes.u16(data, last + 16)
    end
  end
end
