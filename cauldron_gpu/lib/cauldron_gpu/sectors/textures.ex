if Code.ensure_loaded?(Cauldron2D.Sectors.Map) do
  defmodule CauldronGPU.Sectors.Textures do
    @moduledoc """
    Pictures of a `Cauldron2D.Sectors.Pictures` set uploaded as RGBA textures through a
    768-byte palette. Masked pixels (mask byte `0`) are see-through.

    The set must keep its pictures in Elixir (`Pictures.new(named, tables, native: false)`).

        textures = CauldronGPU.Sectors.Textures.upload(gpu, pictures, palette, [3, 7], :nearest)
        %{handle: handle, masked: false} = textures[3]
    """

    alias Cauldron2D.Sectors.Pictures
    alias CauldronGPU.{Handle, Texture}

    @type entry :: %{handle: Handle.t(), masked: boolean()}

    @doc """
    Uploads pictures `ids` of `pictures`, filtered with `filter`. Raises `ArgumentError`
    when the set keeps its pictures in the native library.
    """
    @spec upload(
            CauldronGPU.Target.t(),
            Pictures.t(),
            binary(),
            [non_neg_integer()],
            :linear | :nearest
          ) ::
            %{non_neg_integer() => entry()}
    def upload(gpu, %Pictures{pictures: pictures}, palette, ids, filter)
        when is_tuple(pictures) do
      colours = for(<<r, g, b <- palette>>, do: <<r, g, b, 255>>) |> List.to_tuple()

      Map.new(ids, fn id ->
        picture = elem(pictures, id)
        texture = %{texture(picture, colours) | filter: filter}
        {id, %{handle: CauldronGPU.Target.texture(gpu, texture), masked: picture.mask != nil}}
      end)
    end

    def upload(_gpu, %Pictures{}, _palette, _ids, _filter) do
      raise ArgumentError, "the pictures must be kept in Elixir: Pictures.new(..., native: false)"
    end

    @doc "The RGBA texture of one column-by-column `picture` in `colours`, a tuple of 256 RGBA binaries."
    @spec texture(Pictures.picture(), tuple()) :: Texture.t()
    def texture(%{width: width, height: height, pixels: pixels} = picture, colours) do
      mask = Map.get(picture, :mask)

      rgba =
        for y <- 0..(height - 1)//1, x <- 0..(width - 1)//1, into: <<>> do
          at = x * height + y
          colour(elem(colours, :binary.at(pixels, at)), mask, at)
        end

      %Texture{width: width, height: height, pixels: rgba}
    end

    defp colour(rgba, nil, _at), do: rgba

    defp colour(<<r, g, b, _alpha>> = rgba, mask, at) do
      if :binary.at(mask, at) == 0, do: <<r, g, b, 0>>, else: rgba
    end
  end
end
