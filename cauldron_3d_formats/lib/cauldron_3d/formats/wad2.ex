defmodule Cauldron3D.Formats.Wad2 do
  @moduledoc """
  `WAD2` picture collections and loose `.lmp` pictures, read into `Cauldron3D.Texture`s
  of palette indices.

      Cauldron3D.Formats.Wad2.pictures(File.read!("gfx.wad"), raw: %{"conchars" => {128, 128}})["num_0"]

  A picture lump holds its width and height before its pixels; `:raw` names lumps that
  are bare pixels and gives their `{width, height}`.
  """

  alias Cauldron3D.Texture

  @doc "Every picture in a `WAD2`, by lower-case name."
  @spec pictures(binary() | nil, keyword()) :: %{String.t() => Texture.t()}
  def pictures(data, opts \\ [])

  def pictures(<<"WAD2", count::little-32, table::little-32, _::binary>> = data, opts) do
    raw = Keyword.get(opts, :raw, %{})

    for <<at::little-32, size::little-32, _disk::little-32, type, _compression, _pad::16,
          name::binary-16 <- binary_part(data, table, count * 32)>>,
        name = String.downcase(clean(name)),
        picture = lump(type, name, binary_part(data, at, size), Map.get(raw, name)),
        picture != nil,
        into: %{},
        do: picture
  end

  def pictures(_data, _opts), do: %{}

  @doc "A loose `.lmp` picture: width, height and its pixels; `nil` when it is not one."
  @spec lmp(binary() | nil) :: Texture.t() | nil
  def lmp(<<width::little-32, height::little-32, pixels::binary>>)
      when width > 0 and height > 0 and byte_size(pixels) >= width * height,
      do: Texture.new(width, height, binary_part(pixels, 0, width * height))

  def lmp(_data), do: nil

  defp lump(_type, name, data, {width, height}) when byte_size(data) >= width * height,
    do: {name, Texture.new(width, height, binary_part(data, 0, width * height))}

  defp lump(0x42, name, data, nil) do
    case lmp(data) do
      nil -> nil
      texture -> {name, texture}
    end
  end

  defp lump(_type, _name, _data, _raw), do: nil

  defp clean(name), do: name |> :binary.split(<<0>>) |> hd()
end
