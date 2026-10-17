defmodule Cauldron2D.GameMaker.Runtime.Pictures do
  @moduledoc """
  Version inspections of the chunks that hold pictures: `SPRT` (2.3.2, 2024.6 and
  2024.14), `BGND` (2023.8 and 2024.14.1), `TXTR` (2.0.6, 2022.3 and 2022.5) and `TGIN`
  (2022.9 and 2023.1).
  """

  alias Cauldron2D.GameMaker.Bytes
  alias Cauldron2D.GameMaker.Runtime

  @compressed_magic "2zoq"
  @bzip2_block <<0x31, 0x41, 0x59, 0x26, 0x53, 0x59>>

  @doc "The runtime after inspecting the sprites of the chunk in `context`."
  @spec probe_sprites(Runtime.t(), Runtime.context()) :: Runtime.t()
  def probe_sprites(runtime, context) do
    runtime
    |> bounding_box_masks(context)
    |> special_sprites(context)
  end

  @doc "The runtime after inspecting the backgrounds of the chunk in `context`."
  @spec probe_backgrounds(Runtime.t(), Runtime.context()) :: Runtime.t()
  def probe_backgrounds(runtime, context) do
    runtime
    |> tile_separation(context)
    |> exported_sprites(context)
  end

  @doc "The runtime after inspecting the texture entries of the chunk in `context`."
  @spec probe_textures(Runtime.t(), Runtime.context()) :: Runtime.t()
  def probe_textures(runtime, context) do
    runtime
    |> compressed_pages(context)
    |> generated_mips(context)
  end

  @doc "The runtime after inspecting the texture group entries of the chunk in `context`."
  @spec probe_groups(Runtime.t(), Runtime.context()) :: Runtime.t()
  def probe_groups(runtime, %{data: data, at: at, size: size}) do
    if Runtime.at_least?(runtime, 2, 3) and not Runtime.current_at_least?(runtime, 2023, 1) do
      groups(runtime, data, at + 4, size)
    else
      runtime
    end
  end

  defp groups(runtime, data, base, size) do
    count = Bytes.u32(data, base)

    if count > 0 and wide_group?(data, base, count, base + size) do
      runtime
      |> Runtime.raise_to(2022, 9)
      |> then(&if(group_without_fonts?(data, base), do: current_2023_1(&1), else: &1))
    else
      runtime
    end
  end

  defp wide_group?(data, base, count, limit) do
    first = Bytes.u32(data, base + 4)
    second = if count >= 2, do: Bytes.u32(data, base + 8), else: limit
    pointer = Bytes.u32(data, first + 4)
    pointer < first or pointer >= second
  end

  defp group_without_fonts?(data, base) do
    first = Bytes.u32(data, base + 4)
    [fourth, next] = Bytes.u32s(data, first + 28, 2)
    next <= fourth
  end

  defp current_2023_1(runtime), do: %{Runtime.set(runtime, 2023, 1) | branch: :current}

  defp bounding_box_masks(runtime, %{data: data, at: at, size: size}) do
    if Runtime.current_at_least?(runtime, 2023, 2) and not Runtime.at_least?(runtime, 2024, 6) and
         bounding_box_masks?(data, at, at + size) do
      Runtime.set(runtime, 2024, 6)
    else
      runtime
    end
  end

  defp bounding_box_masks?(data, at, limit) do
    data
    |> Bytes.pointers(at)
    |> Runtime.with_next()
    |> Enum.reduce_while(false, fn {sprite, next}, _ ->
      case mask_layout(data, sprite, next, limit) do
        :undecided -> {:cont, false}
        :full -> {:halt, false}
        :bounding_box -> {:halt, true}
      end
    end)
  end

  defp mask_layout(data, sprite, next, limit) do
    [width, height] = Bytes.u32s(data, sprite + 4, 2)
    [left, right, bottom, top] = for index <- 0..3, do: Bytes.i32(data, sprite + 12 + 4 * index)
    box = {right - left + 1, bottom - top + 1}

    if box == {width, height},
      do: :undecided,
      else: special_mask_layout(data, sprite, next, {width, height}, box, limit)
  end

  defp special_mask_layout(data, sprite, next, full, box, limit) do
    if Bytes.i32(data, sprite + 56) == -1 do
      [version, kind] = Bytes.u32s(data, sprite + 60, 2)
      sprite_mask_layout(data, sprite, {version, kind}, {next, full, box, limit})
    else
      :full
    end
  end

  defp sprite_mask_layout(_data, _sprite, {_version, kind}, _shape) when kind != 0, do: :undecided
  defp sprite_mask_layout(_data, _sprite, {version, _kind}, _shape) when version != 3, do: :full

  defp sprite_mask_layout(data, sprite, _kind, {next, full, box, limit}) do
    [sequence, nine_slice, frames] = Bytes.u32s(data, sprite + 76, 3)
    masks_at = sprite + 88 + 4 * frames
    expected = expected_end(sequence, nine_slice, next, limit)
    compare_masks(Bytes.u32(data, masks_at), masks_at + 4, full, box, expected)
  end

  defp expected_end(sequence, _nine_slice, _next, _limit) when sequence != 0,
    do: {sequence, false}

  defp expected_end(_sequence, nine_slice, _next, _limit) when nine_slice != 0,
    do: {nine_slice, false}

  defp expected_end(_sequence, _nine_slice, next, _limit) when next != 0, do: {next, false}
  defp expected_end(_sequence, _nine_slice, _next, limit), do: {limit, true}

  defp compare_masks(0, _start, _full, _box, _expected), do: :undecided

  defp compare_masks(masks, start, {full_width, full_height}, {box_width, box_height}, expected) do
    full_end = start + padded(masks * div(full_width + 7, 8) * full_height)
    box_end = start + padded(masks * div(box_width + 7, 8) * box_height)

    cond do
      ends_at?(full_end, expected) -> :full
      ends_at?(box_end, expected) -> :bounding_box
      true -> :full
    end
  end

  defp ends_at?(position, {expected, _lenient}) when position == expected, do: true

  defp ends_at?(position, {expected, true}) when rem(position, 16) != 0,
    do: position + 16 - rem(position, 16) == expected

  defp ends_at?(_position, _expected), do: false

  defp padded(length) when rem(length, 4) == 0, do: length
  defp padded(length), do: length + 4 - rem(length, 4)

  defp special_sprites(runtime, %{data: data, at: at}) do
    if Runtime.at_least?(runtime, 2) do
      data
      |> Runtime.live_pointers(at)
      |> Enum.reduce(runtime, &special_sprite(&2, data, &1))
    else
      runtime
    end
  end

  defp special_sprite(runtime, data, sprite) do
    case Bytes.i32(data, sprite + 56) do
      -1 ->
        [version, kind] = Bytes.u32s(data, sprite + 60, 2)

        runtime
        |> nine_slices(version)
        |> vectors(data, sprite, version, kind)

      _ ->
        runtime
    end
  end

  defp nine_slices(runtime, version) when version >= 3, do: Runtime.raise_to(runtime, 2, 3, 2)
  defp nine_slices(runtime, _version), do: runtime

  defp vectors(runtime, data, sprite, version, 3) do
    vector_version = Bytes.i32(data, sprite + 76 + 4 * min(max(version - 1, 0), 2))
    if vector_version >= 4, do: Runtime.raise_to(runtime, 2024, 14), else: runtime
  end

  defp vectors(runtime, _data, _sprite, _version, _kind), do: runtime

  defp tile_separation(runtime, %{data: data, at: at, size: size}) do
    if Runtime.at_least?(runtime, 2024, 13) and not Runtime.at_least?(runtime, 2024, 14, 1) and
         misaligned_tileset?(data, at, at + size) do
      Runtime.set(runtime, 2024, 14, 1)
    else
      runtime
    end
  end

  defp misaligned_tileset?(data, at, limit) do
    data
    |> Bytes.pointers(at)
    |> Runtime.with_next()
    |> Enum.any?(fn {background, next} ->
      [items, tiles] = Bytes.u32s(data, background + 44, 2)
      theoretical = background + 64 + items * tiles * 4
      theoretical_end(theoretical, next, limit) != end_of(next, limit)
    end)
  end

  defp theoretical_end(position, 0, _limit), do: align(position, 16)
  defp theoretical_end(position, _next, _limit), do: align(position, 8)

  defp end_of(0, limit), do: limit
  defp end_of(next, _limit), do: next

  defp align(position, size) when rem(position, size) == 0, do: position
  defp align(position, size), do: position + size - rem(position, size)

  defp exported_sprites(runtime, %{data: data, at: at}) do
    if Runtime.at_least?(runtime, 2) and not Runtime.at_least?(runtime, 2023, 8) and
         Enum.any?(Runtime.live_pointers(data, at), &(Bytes.u32(data, &1 + 52) != 0)) do
      Runtime.set(runtime, 2023, 8)
    else
      runtime
    end
  end

  defp compressed_pages(runtime, %{data: data, at: at}) do
    if Runtime.at_least?(runtime, 2, 3) and not Runtime.at_least?(runtime, 2022, 3) and
         page_entries_with_size?(data, at) do
      runtime
      |> Runtime.set(2022, 3)
      |> then(&if(headerless_bzip2?(data, at), do: Runtime.set(&1, 2022, 5), else: &1))
    else
      runtime
    end
  end

  defp page_entries_with_size?(data, at) do
    case Bytes.u32(data, at) do
      1 -> Bytes.u32(data, at + 20) > 0
      count when count > 1 -> Bytes.u32(data, at + 4) + 16 == Bytes.u32(data, at + 8)
      _ -> false
    end
  end

  defp headerless_bzip2?(data, at) do
    data
    |> Bytes.pointers(at)
    |> Enum.map(&Bytes.u32(data, &1 + 12))
    |> Enum.find(&(binary_part(data, &1, 4) == @compressed_magic))
    |> case do
      nil -> false
      page -> not bzip2_stream?(binary_part(data, page + 8, 10))
    end
  end

  defp bzip2_stream?(<<"BZh", _level, @bzip2_block>>), do: true
  defp bzip2_stream?(_bytes), do: false

  defp generated_mips(runtime, %{data: data, at: at}) do
    if Runtime.at_least?(runtime, 2) and not Runtime.at_least?(runtime, 2, 0, 6) and
         mips?(data, at),
       do: Runtime.set(runtime, 2, 0, 6),
       else: runtime
  end

  defp mips?(data, at) do
    case Bytes.u32(data, at) do
      0 -> false
      1 -> Bytes.u32(data, Bytes.u32(data, at + 4) + 8) != 0
      _ -> Bytes.u32(data, at + 8) - Bytes.u32(data, at + 4) != 8
    end
  end
end
