defmodule Cauldron3D.Formats.Wad3 do
  @moduledoc """
  `WAD3` collections: wall textures with their mips and their own palettes, and pictures
  with their own palettes.

      textures = Cauldron3D.Formats.Wad3.textures(File.read!("halflife.wad"))
      textures["c1a0_labflrd"]
      #=> [%Cauldron3D.Texture{palette: <<...>>}, ...]

      Cauldron3D.Formats.Wad3.pictures(File.read!("gfx.wad"))["crosshairs"]

  Names are lower case. In a texture whose name begins `{`, colour 255 is see-through.
  """

  alias Cauldron3D.Formats.Bsp
  alias Cauldron3D.Texture

  @doc "Every texture in the collection: its four mips, by name."
  @spec textures(binary() | nil) :: %{String.t() => [Texture.t()]}
  def textures(data) do
    for {0x43, name, lump} <- lumps(data),
        {_, [_ | _] = mips} <- [Bsp.miptex(lump, true)],
        into: %{},
        do: {name, mips}
  end

  @doc "Every picture in the collection, by name."
  @spec pictures(binary() | nil) :: %{String.t() => Texture.t()}
  def pictures(data) do
    for {0x42, name, lump} <- lumps(data),
        picture = picture(lump),
        picture != nil,
        into: %{},
        do: {name, picture}
  end

  @doc "A picture with its palette: width, height, pixels, then 256 colours; `nil` when it is not one."
  @spec picture(binary()) :: Texture.t() | nil
  def picture(<<width::little-32, height::little-32, rest::binary>>)
      when width > 0 and height > 0 do
    size = width * height

    case rest do
      <<pixels::binary-size(^size), 256::little-16, palette::binary-768, _::binary>> ->
        Texture.new(width, height, pixels, palette)

      _ ->
        nil
    end
  end

  def picture(_data), do: nil

  @doc "Every font in the collection, by name, as `font/1` reads it."
  @spec fonts(binary() | nil) :: %{String.t() => map()}
  def fonts(data) do
    for {0x46, name, lump} <- lumps(data),
        font = font(lump),
        font != nil,
        into: %{},
        do: {name, font}
  end

  @doc """
  A font lump: `%{texture:, height:, glyphs:}`, `texture` the 256-pixel-wide sheet of
  characters with its palette (colour 255 see-through), `height` a character's height in
  pixels, and `glyphs` a tuple of 256 `{x, y, width}` places on the sheet. `nil` when it
  is not one.
  """
  @spec font(binary()) :: map() | nil
  def font(
        <<_widest::little-32, height::little-32, _rows::little-32, row_height::little-32,
          rest::binary>>
      )
      when height > 0 and row_height > 0 do
    case rest do
      <<info::binary-1024, pixels::binary-size(256 * ^height), colours::little-16,
        palette::binary-768, _::binary>>
      when colours <= 256 ->
        glyphs =
          for <<offset::little-16, char_width::little-16 <- info>> do
            {rem(offset, 256), div(offset, 256), char_width}
          end

        %{
          texture: Texture.new(256, height, pixels, palette),
          height: row_height,
          glyphs: List.to_tuple(glyphs)
        }

      _ ->
        nil
    end
  end

  def font(_data), do: nil

  @doc "The lumps of a `WAD3` as `{type, name, bytes}`."
  @spec lumps(binary() | nil) :: [{byte(), String.t(), binary()}]
  def lumps(<<"WAD3", count::little-32, table::little-32, _::binary>> = data)
      when table + count * 32 <= byte_size(data) do
    for <<at::little-32, size::little-32, _disk::little-32, type, _compression, _pad::16,
          name::binary-16 <- binary_part(data, table, count * 32)>>,
        at + size <= byte_size(data),
        do:
          {type, name |> :binary.split(<<0>>) |> hd() |> String.downcase(),
           binary_part(data, at, size)}
  end

  def lumps(_data), do: []
end
