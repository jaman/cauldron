defmodule Cauldron2D.GameMaker.TileLayers do
  @moduledoc """
  A room's tile layers, each drawn as one picture.

  `Cauldron2D.GameMaker.Draw.run/1` gives a visible layer's tiles as one draw list item
  (`item/4`) whose picture is `{:tile_layer, room, layer, blend}`: the room's index, the
  layer's name, and the colour `Cauldron2D.GameMaker.World.put_layer/3`'s `:tile_blend`
  gave an asset layer's tiles, or `nil`. It stands at the layer's offset plus the top-left
  corner of its tiles. `raster/3` draws that picture from the game's data: every tile as
  the layer would draw it on its own, mirrored, flipped and turned as its cell says, in
  its colour and alpha. A key always names the same pixels, so a picture drawn once can
  be kept and drawn again.

      raster = Cauldron2D.GameMaker.TileLayers.raster(data, key, &MyGame.picture/1)
  """

  alias Cauldron2D.DrawList
  alias Cauldron2D.GameMaker.{Background, Data}
  alias Cauldron2D.GameMaker.Room.{Layer, Tile}
  alias FrenchCurve.Raster

  @type key :: {:tile_layer, non_neg_integer(), String.t(), {byte(), byte(), byte()} | nil}

  @doc """
  The draw list item for the tiles of `layer`, a layer of room `room` already moved to
  where it is drawn, its asset tiles blended `blend` (or `nil`); `nil` when it has no
  tiles.
  """
  @spec item(Data.t(), non_neg_integer(), Layer.t(), {byte(), byte(), byte()} | nil) ::
          map() | nil
  def item(%Data{} = data, room, %Layer{offset: {offset_x, offset_y}} = layer, blend) do
    case bounds(data, layer) do
      nil ->
        nil

      {left, top, _right, _bottom} ->
        %{
          picture: {:tile_layer, room, layer.name, blend},
          position: {offset_x + left, offset_y + top},
          depth: layer.depth
        }
    end
  end

  @doc """
  The picture `key` names, drawn with `pictures` (a function from a tile's picture key,
  `{:tile, background, tile}` or `{:sprite_part, sprite, rectangle}`, to its raster);
  `nil` when the room has no such layer or the layer no tiles.
  """
  @spec raster(Data.t(), key(), (term() -> Raster.t() | nil)) :: Raster.t() | nil
  def raster(%Data{} = data, {:tile_layer, room, name, blend}, pictures) do
    with %{layers: layers} <- Enum.at(data.rooms, room),
         %Layer{} = layer <- Enum.find(layers, &(&1.name == name)),
         {left, top, right, bottom} <- bounds(data, layer) do
      layer
      |> tiles(data, blend)
      |> DrawList.render({ceil(right - left), ceil(bottom - top)}, pictures, view: {left, top})
    else
      _none -> nil
    end
  end

  defp tiles(%Layer{content: {:tiles, %{tileset: tileset, cells: cells}}}, data, _blend) do
    case Enum.at(data.backgrounds, tileset) do
      %Background{tiles: %{size: {width, height}}} ->
        for {row, y} <- Enum.with_index(Tuple.to_list(cells)),
            {{tile, flags}, x} <- Enum.with_index(Tuple.to_list(row)) do
          {scale_x, scale_y, angle} = orientation(flags)

          %{
            picture: {:tile, tileset, tile},
            position: {x * width + width / 2, y * height + height / 2},
            origin: {width / 2, height / 2},
            scale: {scale_x, scale_y},
            angle: angle
          }
        end

      _none ->
        []
    end
  end

  defp tiles(%Layer{content: {:assets, %{tiles: tiles}}}, _data, blend) do
    for %Tile{} = tile <- tiles, area?(tile) do
      {red, green, blue, alpha} = blended(tile.colour, blend)

      %{
        picture: {:sprite_part, tile.picture, tile.source},
        position: tile.position,
        scale: tile.scale,
        blend: {red, green, blue},
        alpha: alpha / 255
      }
    end
  end

  defp tiles(%Layer{}, _data, _blend), do: []

  defp bounds(data, %Layer{content: {:tiles, %{tileset: tileset, cells: cells}}}) do
    with %Background{tiles: %{size: {width, height}}} <- Enum.at(data.backgrounds, tileset),
         rows when rows > 0 <- tuple_size(cells),
         columns when columns > 0 <- tuple_size(elem(cells, 0)) do
      {0, 0, columns * width, rows * height}
    else
      _none -> nil
    end
  end

  defp bounds(_data, %Layer{content: {:assets, %{tiles: tiles}}}) do
    tiles
    |> Enum.filter(&area?/1)
    |> Enum.map(&tile_bounds/1)
    |> Enum.reduce(nil, &union/2)
  end

  defp bounds(_data, %Layer{}), do: nil

  defp tile_bounds(%Tile{
         position: {x, y},
         source: {_sx, _sy, width, height},
         scale: {scale_x, scale_y}
       }) do
    {far_x, far_y} = {x + width * scale_x, y + height * scale_y}
    {floor(min(x, far_x)), floor(min(y, far_y)), ceil(max(x, far_x)), ceil(max(y, far_y))}
  end

  defp union(box, nil), do: box

  defp union({left, top, right, bottom}, {other_left, other_top, other_right, other_bottom}),
    do:
      {min(left, other_left), min(top, other_top), max(right, other_right),
       max(bottom, other_bottom)}

  defp blended(colour, nil), do: colour
  defp blended({_red, _green, _blue, alpha}, {red, green, blue}), do: {red, green, blue, alpha}

  defp area?(%Tile{source: {_x, _y, width, height}}), do: width > 0 and height > 0

  defp orientation(flags) do
    {if(:mirror in flags, do: -1, else: 1), if(:flip in flags, do: -1, else: 1),
     if(:rotate in flags, do: -90, else: 0)}
  end
end
