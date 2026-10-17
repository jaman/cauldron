defmodule Cauldron2D.GameMaker.Runtime.Rooms do
  @moduledoc """
  Version inspections of the `ROOM` chunk: image speed in placed instances (2.2.2.302),
  layer effects (2022.1), compressed tile layers (2024.2 and 2024.4) and text items in
  asset layers (2024.6).
  """

  alias Cauldron2D.GameMaker.Bytes
  alias Cauldron2D.GameMaker.Runtime

  @layer_list 88
  @instance_list 48
  @path 0
  @background 1
  @instances 2
  @assets 3
  @tiles 4
  @effect 6
  @path_alias 7
  @layer_kinds [@path, @background, @instances, @assets, @tiles, @effect, @path_alias]

  @doc "The runtime after inspecting the rooms of the chunk in `context`."
  @spec probe(Runtime.t(), Runtime.context()) :: Runtime.t()
  def probe(runtime, %{data: data, at: at}) do
    rooms = Runtime.live_pointers(data, at)

    runtime
    |> tile_compression(data, rooms)
    |> layer_effects(data, rooms)
    |> image_speed(data, rooms)
    |> text_items(data, rooms)
  end

  defp tile_compression(runtime, data, rooms) do
    if Runtime.at_least?(runtime, 2023, 2) and not Runtime.at_least?(runtime, 2024, 4) do
      survey =
        Enum.reduce(rooms, %{compressed: false, unaligned: false}, &survey_room(data, &1, &2))

      runtime
      |> compressed_tiles(survey)
      |> aligned_tiles(survey)
    else
      runtime
    end
  end

  defp compressed_tiles(runtime, %{compressed: true}), do: Runtime.raise_to(runtime, 2024, 2)
  defp compressed_tiles(runtime, _survey), do: runtime

  defp aligned_tiles(runtime, %{unaligned: false}) do
    if Runtime.at_least?(runtime, 2024, 2), do: Runtime.set(runtime, 2024, 4), else: runtime
  end

  defp aligned_tiles(runtime, _survey), do: runtime

  defp survey_room(data, room, survey) do
    {list, sequences} = layer_bounds(data, room)

    case Bytes.i32(data, list) do
      count when count > 0 ->
        layers = for index <- 0..(count - 1), do: {list + 4 * index, index == count - 1}

        {_after_tiles, survey} =
          Enum.reduce(layers, {false, survey}, fn {slot, last?}, {after_tiles?, survey} ->
            survey_layer(data, slot, last?, sequences, after_tiles?, survey)
          end)

        survey

      _ ->
        survey
    end
  end

  defp survey_layer(data, slot, last?, sequences, after_tiles?, survey) do
    survey = if after_tiles? and rem(slot, 4) != 0, do: %{survey | unaligned: true}, else: survey
    layer = Bytes.u32(data, slot + 4) + 8
    following = if last?, do: sequences, else: Bytes.u32(data, slot + 8)

    case Bytes.i32(data, layer) do
      @tiles -> {true, tiles_layer(data, layer, following, survey)}
      _ -> {false, survey}
    end
  end

  defp tiles_layer(data, layer, following, survey) do
    effects = Bytes.i32(data, layer + 36)
    sizes_at = layer + 40 + effects * 12 + 4
    [width, height] = [Bytes.i32(data, sizes_at), Bytes.i32(data, sizes_at + 4)]

    if following - (sizes_at + 8) != width * height * 4,
      do: %{survey | compressed: true},
      else: survey
  end

  defp layer_effects(runtime, data, rooms) do
    if Runtime.at_least?(runtime, 2, 3) and not Runtime.at_least?(runtime, 2022, 1) and
         effect_layout?(data, rooms),
       do: Runtime.set(runtime, 2022, 1),
       else: runtime
  end

  defp effect_layout?(data, rooms) do
    rooms
    |> Enum.find_value(false, &first_layer_verdict(data, &1))
    |> verdict()
  end

  defp first_layer_verdict(data, room) do
    {list, sequences} = layer_bounds(data, room)

    with count when count > 0 <- Bytes.i32(data, list),
         layer = Bytes.u32(data, list + 4) + 8,
         following = if(count == 1, do: sequences, else: Bytes.u32(data, list + 8)),
         kind when kind in @layer_kinds and kind not in [@path, @path_alias] <-
           Bytes.i32(data, layer) do
      {:found, longer_layer?(data, kind, layer + 4, following)}
    else
      _ -> nil
    end
  end

  defp verdict({:found, result}), do: result
  defp verdict(false), do: false

  defp longer_layer?(_data, @background, after_kind, following), do: following - after_kind > 64

  defp longer_layer?(data, @instances, after_kind, following) do
    following - (after_kind + 28) != Bytes.i32(data, after_kind + 24) * 4
  end

  defp longer_layer?(data, @assets, after_kind, _following) do
    tiles = Bytes.i32(data, after_kind + 24)
    position = after_kind + 28
    tiles != position + 8 and tiles != position + 12
  end

  defp longer_layer?(data, @tiles, after_kind, following) do
    width = Bytes.i32(data, after_kind + 28)
    height = Bytes.i32(data, after_kind + 32)
    following - (after_kind + 36) != width * height * 4
  end

  defp longer_layer?(data, @effect, after_kind, following) do
    following - (after_kind + 32) != Bytes.i32(data, after_kind + 28) * 12
  end

  defp image_speed(runtime, data, rooms) do
    if Runtime.at_least?(runtime, 2) and not Runtime.at_least?(runtime, 2, 2, 2, 302) and
         image_speed_layout?(data, rooms),
       do: Runtime.set(runtime, 2, 2, 2, 302),
       else: runtime
  end

  defp image_speed_layout?(data, rooms) do
    rooms
    |> Enum.find_value(false, &first_instance_verdict(data, &1))
    |> verdict()
  end

  defp first_instance_verdict(data, room) do
    list = Bytes.u32(data, room + @instance_list)
    tiles = Bytes.u32(data, room + @instance_list + 4)

    case Bytes.i32(data, list) do
      count when count > 0 ->
        first = Bytes.u32(data, list + 4)
        second = if count == 1, do: tiles, else: Bytes.u32(data, list + 8)
        {:found, second - first == 48}

      _ ->
        nil
    end
  end

  defp text_items(runtime, data, rooms) do
    if Runtime.at_least?(runtime, 2, 3) and not Runtime.at_least?(runtime, 2024, 6) and
         Enum.any?(rooms, &room_has_extra_asset_data?(runtime, data, &1)),
       do: Runtime.set(runtime, 2024, 6),
       else: runtime
  end

  defp room_has_extra_asset_data?(runtime, data, room) do
    {list, _sequences} = layer_bounds(data, room)

    data
    |> Bytes.pointers(list)
    |> Enum.any?(fn layer ->
      Bytes.i32(data, layer + 8) == @assets and asset_pointers_overrun?(runtime, data, layer)
    end)
  end

  defp asset_pointers_overrun?(runtime, data, layer) do
    start = layer_data(runtime, data, layer)

    pointers =
      3 + if(Runtime.at_least?(runtime, 2, 3, 2), do: 0, else: 1) + particle_pointer(runtime)

    Bytes.u32(data, start) > start + 4 * pointers
  end

  defp particle_pointer(runtime),
    do: if(Runtime.current_at_least?(runtime, 2023, 2), do: 1, else: 0)

  defp layer_data(runtime, data, layer) do
    if Runtime.at_least?(runtime, 2022, 1),
      do: layer + 36 + 12 + 12 * Bytes.u32(data, layer + 44),
      else: layer + 36
  end

  defp layer_bounds(data, room),
    do: {Bytes.u32(data, room + @layer_list), Bytes.u32(data, room + @layer_list + 4)}
end
