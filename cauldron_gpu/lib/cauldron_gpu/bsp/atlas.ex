if Code.ensure_loaded?(Cauldron3D.Bsp) do
  defmodule CauldronGPU.Bsp.Atlas do
    @moduledoc """
    A BSP world's face lightmaps packed into pages of luxels, row by row, tallest first. A
    face's place is `page_size` luxels wide per slot; a page holds `slots` slots side by
    side (the most light styles any face has, at most four), slot `k` holding each face's
    lightmap for its `k`-th style, so a page is `page_size * slots` luxels wide and as tall
    as its rows need.
    """

    alias Cauldron3D.Bsp, as: World
    alias Cauldron3D.Bsp.Face
    alias CauldronGPU.Texture

    @type place ::
            {page :: non_neg_integer(), x :: non_neg_integer(), y :: non_neg_integer(),
             pos_integer(), pos_integer()}
    @type t :: %__MODULE__{
            places: %{non_neg_integer() => place()},
            heights: tuple(),
            page_size: pos_integer(),
            slots: 1..4
          }

    @enforce_keys [:places, :heights, :page_size, :slots]
    defstruct [:places, :heights, :page_size, :slots]

    @doc "Packs every lit face of `bsp`."
    @spec pack(World.t(), pos_integer()) :: t()
    def pack(%World{faces: faces}, page_size) do
      sizes =
        for index <- 0..(tuple_size(faces) - 1)//1,
            face = elem(faces, index),
            face.lightmap != nil,
            do: {index, size(face)}

      {places, shelves} =
        sizes
        |> Enum.sort_by(fn {_index, {_w, h}} -> -h end)
        |> Enum.reduce({%{}, [{0, 0, 0, 0}]}, fn {index, {w, h}}, {places, [shelf | done]} ->
          {place, shelves} = place(shelf, w, h, page_size)
          {Map.put(places, index, place), shelves ++ done}
        end)

      slots =
        faces
        |> Tuple.to_list()
        |> Enum.map(fn face -> if face.lightmap, do: length(face.styles), else: 1 end)
        |> Enum.max(fn -> 1 end)
        |> min(4)
        |> max(1)

      %__MODULE__{places: places, heights: heights(shelves), page_size: page_size, slots: slots}
    end

    @doc "Face `face`'s light styles as four numbers, 255 where it has none."
    @spec styles(Face.t()) :: [0..255]
    def styles(%Face{styles: styles}),
      do: styles |> Enum.take(4) |> Kernel.++([255, 255, 255, 255]) |> Enum.take(4)

    @doc "The page face `index` is on, or `nil` for an unlit face."
    @spec page(t(), non_neg_integer()) :: non_neg_integer() | nil
    def page(%__MODULE__{places: places}, index) do
      case places do
        %{^index => {page, _, _, _, _}} -> page
        _ -> nil
      end
    end

    @doc "Lightmap coordinates on its page for texture place `{s, t}` of face `index`."
    @spec uv(t(), non_neg_integer(), Face.t(), number(), number()) :: {float(), float()}
    def uv(
          %__MODULE__{places: places, heights: heights, page_size: page_size, slots: slots},
          index,
          face,
          s,
          t
        ) do
      case places do
        %{^index => {page, x, y, _, _}} ->
          {mins_s, mins_t} = face.mins

          {(x + (s - mins_s) / face.luxel + 0.5) / (page_size * slots),
           (y + (t - mins_t) / face.luxel + 0.5) / elem(heights, page)}

        _ ->
          {0.0, 0.0}
      end
    end

    @doc "One RGBA texture per page, filled from `bsp`'s lightmap samples."
    @spec textures(t(), World.t()) :: [Texture.t()]
    def textures(%__MODULE__{} = atlas, %World{} = bsp) do
      for page <- 0..(tuple_size(atlas.heights) - 1)//1 do
        height = elem(atlas.heights, page)
        segments = page_segments(atlas, bsp, page)

        pixels =
          for row <- 0..(height - 1)//1,
              into: <<>>,
              do: row(Map.get(segments, row, []), atlas.page_size * atlas.slots)

        %Texture{
          width: atlas.page_size * atlas.slots,
          height: height,
          pixels: pixels,
          format: :linear,
          wrap: :clamp,
          mipmaps: false
        }
      end
    end

    defp size(%Face{extents: {s, t}, luxel: luxel}), do: {div(s, luxel) + 1, div(t, luxel) + 1}

    defp place({page, x, y, shelf_height}, w, h, page_size)
         when x + w <= page_size and y + max(shelf_height, h) <= page_size do
      {{page, x, y, w, h}, [{page, x + w, y, max(shelf_height, h)}]}
    end

    defp place({page, _x, y, shelf_height} = shelf, w, h, page_size)
         when y + shelf_height + h <= page_size do
      {placed, [next]} = place({page, 0, y + shelf_height, 0}, w, h, page_size)
      {placed, [next, shelf]}
    end

    defp place({page, _x, _y, _shelf_height} = shelf, w, h, page_size) do
      {placed, [next]} = place({page + 1, 0, 0, 0}, w, h, page_size)
      {placed, [next, shelf]}
    end

    defp heights(shelves) do
      shelves
      |> Enum.group_by(fn {page, _, _, _} -> page end, fn {_, _, y, height} -> y + height end)
      |> Enum.sort()
      |> Enum.map(fn {_page, bottoms} -> max(Enum.max(bottoms), 1) end)
      |> List.to_tuple()
    end

    defp page_segments(atlas, bsp, page) do
      for {index, {^page, x, y, w, h}} <- atlas.places,
          face = elem(bsp.faces, index),
          slot <- 0..(min(length(face.styles), atlas.slots) - 1)//1,
          row <- 0..(h - 1),
          reduce: %{} do
        segments ->
          offset = face.lightmap + (slot * h + row) * w * bsp.light_channels
          at = x + slot * atlas.page_size
          bytes = samples(bsp, offset, w)
          Map.update(segments, y + row, [{at, bytes}], &[{at, bytes} | &1])
      end
    end

    defp samples(%World{lightmaps: lightmaps, light_channels: 1}, offset, count) do
      for <<level <- binary_part(lightmaps, offset, count)>>,
        into: <<>>,
        do: <<level, level, level, 255>>
    end

    defp samples(%World{lightmaps: lightmaps, light_channels: 3}, offset, count) do
      for <<r, g, b <- binary_part(lightmaps, offset, count * 3)>>,
        into: <<>>,
        do: <<r, g, b, 255>>
    end

    defp row(segments, page_size) do
      {iodata, end_x} =
        segments
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.reduce({[], 0}, fn {x, bytes}, {iodata, at} ->
          {[iodata, :binary.copy(<<0, 0, 0, 255>>, x - at), bytes], x + div(byte_size(bytes), 4)}
        end)

      IO.iodata_to_binary([iodata, :binary.copy(<<0, 0, 0, 255>>, page_size - end_x)])
    end
  end
end
