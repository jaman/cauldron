defmodule Cauldron2D.GameMaker.Pictures do
  @moduledoc """
  The pictures of a game, cut from its decoded texture pages as `FrenchCurve.Raster`s.

      {:ok, data} = Cauldron2D.GameMaker.Data.read("data.win")
      {:ok, pictures} = Cauldron2D.GameMaker.Pictures.new(data)

      frames = Cauldron2D.GameMaker.Pictures.sprite(pictures, Enum.at(data.sprites, 3))
      tile = Cauldron2D.GameMaker.Pictures.tile(pictures, Enum.at(data.backgrounds, 0), 17)

  `new/1` decodes every page once; a `Pictures` holds them as RGBA and every cut after
  that is binary slicing. A region is returned at its full `bounds`, its trimmed margins
  put back as see-through pixels, so a sprite frame is always the sprite's `size` and
  its `origin` applies unchanged.
  """

  alias Cauldron2D.GameMaker.Background
  alias Cauldron2D.GameMaker.Data
  alias Cauldron2D.GameMaker.Font
  alias Cauldron2D.GameMaker.Region
  alias Cauldron2D.GameMaker.Sprite
  alias Cauldron2D.GameMaker.Texture
  alias FrenchCurve.Raster

  @enforce_keys [:pages]
  defstruct [:pages]

  @type page :: {pos_integer(), pos_integer(), binary()}
  @type t :: %__MODULE__{pages: tuple()}

  @doc "Every texture page of `data`, decoded."
  @spec new(Data.t()) :: {:ok, t()} | {:error, term()}
  def new(%Data{textures: textures}) do
    textures
    |> Enum.reduce_while({:ok, []}, fn texture, {:ok, pages} ->
      case Texture.decode(texture) do
        {:ok, raster} -> {:cont, {:ok, [page(raster) | pages]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, pages} -> {:ok, %__MODULE__{pages: pages |> Enum.reverse() |> List.to_tuple()}}
      error -> error
    end
  end

  @doc "The picture `region` describes, at its full bounds."
  @spec region(t(), Region.t()) :: Raster.t()
  def region(%__MODULE__{} = pictures, %Region{bounds: {width, height}} = region),
    do: Raster.from_rgba(width, height, rgba(pictures, region))

  @doc "Every frame of `sprite`, in order."
  @spec sprite(t(), Sprite.t()) :: [Raster.t()]
  def sprite(%__MODULE__{} = pictures, %Sprite{frames: frames}),
    do: Enum.map(frames, &region(pictures, &1))

  @doc "The whole picture of `background`, `nil` for a background with none."
  @spec background(t(), Background.t()) :: Raster.t() | nil
  def background(%__MODULE__{}, %Background{picture: nil}), do: nil

  def background(%__MODULE__{} = pictures, %Background{picture: picture}),
    do: region(pictures, picture)

  @doc """
  Tile `id` of the tileset `background`, or the rectangle `{x, y, width, height}` of its
  picture that a GameMaker Studio 1 room's tile names. The tile is always its full size:
  the part of the rectangle outside the picture is see-through.
  """
  @spec tile(t(), Background.t(), non_neg_integer() | Region.rectangle()) :: Raster.t()
  def tile(%__MODULE__{} = pictures, %Background{} = background, id) when is_integer(id),
    do: tile(pictures, background, Background.tile_source(background, id))

  def tile(%__MODULE__{} = pictures, %Background{picture: picture}, rectangle),
    do: cut(rgba(pictures, picture), picture.bounds, rectangle)

  @doc """
  The rectangle `{x, y, width, height}` of `sprite`'s first frame that a tile on a
  GameMaker Studio 2 asset layer names, see-through outside the frame.
  """
  @spec sprite_part(t(), Sprite.t(), Region.rectangle()) :: Raster.t()
  def sprite_part(%__MODULE__{} = pictures, %Sprite{frames: [first | _]}, rectangle),
    do: cut(rgba(pictures, first), first.bounds, rectangle)

  @doc "The picture of `font`'s glyph for the code point `character`, `nil` when it has none."
  @spec glyph(t(), Font.t(), non_neg_integer()) :: Raster.t() | nil
  def glyph(%__MODULE__{}, %Font{picture: nil}, _character), do: nil

  def glyph(%__MODULE__{} = pictures, %Font{picture: picture, glyphs: glyphs}, character) do
    case Map.fetch(glyphs, character) do
      {:ok, %{source: {_x, _y, width, height} = source}} when width > 0 and height > 0 ->
        cut(rgba(pictures, picture), picture.bounds, source)

      _none ->
        nil
    end
  end

  @doc """
  Every picture `Cauldron2D.GameMaker.Draw` names, cut once, keyed as it names them:
  each sprite frame, each background, each tile of each tileset, each rectangle a
  room's placed tiles cut from a background or a sprite (rectangles with no area are
  left out), each glyph of each font as `{:glyph, font, character}`, and `:pixel`. Pass `&Map.get(table, &1)` to `Cauldron2D.DrawList.render/4`.
  """
  @spec table(t(), Data.t()) :: %{term() => Raster.t()}
  def table(%__MODULE__{} = pictures, %Data{} = data) do
    backgrounds = Enum.with_index(data.backgrounds)

    frames =
      for {sprite, index} <- Enum.with_index(data.sprites),
          {frame, number} <- Enum.with_index(sprite(pictures, sprite)),
          do: {{:sprite, index, number}, frame}

    wholes =
      for {background, index} <- backgrounds,
          raster = background(pictures, background),
          raster != nil,
          do: {{:background, index}, raster}

    tiles =
      for {%Background{tiles: %{count: count}} = background, index} <- backgrounds,
          background.picture != nil,
          tile <- 0..(count - 1)//1,
          do: {{:tile, index, tile}, tile(pictures, background, tile)}

    background_parts =
      for room <- data.rooms,
          %{picture: index, source: source} <- room.tiles,
          area?(source),
          %Background{picture: %Region{}} = background <- [Enum.at(data.backgrounds, index)],
          uniq: true,
          do: {{:tile, index, source}, tile(pictures, background, source)}

    sprite_parts =
      for room <- data.rooms,
          %{picture: index, source: source} <- asset_tiles(room),
          area?(source),
          %Sprite{frames: [_ | _]} = sprite <- [Enum.at(data.sprites, index)],
          uniq: true,
          do: {{:sprite_part, index, source}, sprite_part(pictures, sprite, source)}

    glyphs =
      for {font, index} <- Enum.with_index(data.fonts),
          font.picture != nil,
          sheet = rgba(pictures, font.picture),
          {character, %{source: {_x, _y, width, height} = source}} <- font.glyphs,
          width > 0 and height > 0,
          do: {{:glyph, index, character}, cut(sheet, font.picture.bounds, source)}

    Map.new(
      [{:pixel, Raster.from_rgba(1, 1, <<255, 255, 255, 255>>)}] ++
        frames ++ wholes ++ tiles ++ background_parts ++ sprite_parts ++ glyphs
    )
  end

  defp area?({_x, _y, width, height}), do: width > 0 and height > 0

  defp asset_tiles(room) do
    for %{content: {:assets, %{tiles: tiles}}} <- room.layers, tile <- tiles, do: tile
  end

  defp cut(rgba, {full_width, full_height}, {x, y, width, height}) do
    inside_width = min(x + width, full_width) - x
    inside_height = min(y + height, full_height) - y

    cut =
      if inside_width > 0 and inside_height > 0 do
        rgba
        |> crop(full_width, {x, y, inside_width, inside_height})
        |> place({0, 0, inside_width, inside_height}, {width, height})
      else
        :binary.copy(<<0, 0, 0, 0>>, width * height)
      end

    Raster.from_rgba(width, height, cut)
  end

  defp page(raster) do
    {width, height} = Raster.dimensions(raster)
    {width, height, Raster.to_rgba_binary(raster)}
  end

  defp rgba(%__MODULE__{pages: pages}, %Region{} = region) do
    {page_width, _height, page} = elem(pages, region.page)
    {_x, _y, source_width, source_height} = region.source
    {target_x, target_y, target_width, target_height} = region.target
    {width, height} = region.bounds

    cut = crop(page, page_width, region.source)

    cut =
      if {source_width, source_height} == {target_width, target_height},
        do: cut,
        else: resize(cut, {source_width, source_height}, {target_width, target_height})

    place(cut, {target_x, target_y, target_width, target_height}, {width, height})
  end

  defp crop(rgba, stride, {x, y, width, height}) do
    for row <- y..(y + height - 1)//1,
        into: <<>>,
        do: binary_part(rgba, (row * stride + x) * 4, width * 4)
  end

  defp resize(rgba, {width, height}, {new_width, new_height}) do
    for row <- 0..(new_height - 1)//1,
        column <- 0..(new_width - 1)//1,
        into: <<>> do
      source = div(row * height, new_height) * width + div(column * width, new_width)
      binary_part(rgba, source * 4, 4)
    end
  end

  defp place(rgba, {x, y, width, height}, {full_width, full_height}) do
    blank_row = :binary.copy(<<0, 0, 0, 0>>, full_width)
    left = :binary.copy(<<0, 0, 0, 0>>, x)
    right = :binary.copy(<<0, 0, 0, 0>>, max(full_width - x - width, 0))

    for row <- 0..(full_height - 1)//1, into: <<>> do
      if row >= y and row < y + height,
        do: left <> binary_part(rgba, (row - y) * width * 4, width * 4) <> right,
        else: blank_row
    end
  end
end
