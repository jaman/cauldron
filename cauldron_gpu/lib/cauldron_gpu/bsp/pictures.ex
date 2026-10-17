if Code.ensure_loaded?(Cauldron3D.Bsp) do
  defmodule CauldronGPU.Bsp.Pictures do
    @moduledoc """
    A BSP world's textures uploaded as RGBA: the base picture of each, and for a `:quake`
    world a glow picture holding only its full-bright colours (palette 224 and up) when it
    has any. Colour 255 of a `:masked` texture is see-through.
    """

    alias Cauldron3D.Bsp, as: World
    alias CauldronGPU.{Handle, Texture}

    @type entry :: %{base: Handle.t(), glow: Handle.t() | nil, kind: World.kind()}
    @type t :: tuple()

    @doc "Uploads every texture of `bsp`; `palette` serves textures without their own."
    @spec upload(CauldronGPU.Target.t(), World.t(), binary(), :linear | :nearest) :: t()
    def upload(gpu, %World{textures: textures, game: game}, palette, filter) do
      textures
      |> Tuple.to_list()
      |> Enum.map(&entry(gpu, &1, palette, filter, game))
      |> List.to_tuple()
    end

    @doc "The uploaded pictures of texture `index`."
    @spec get(t(), non_neg_integer()) :: entry()
    def get(pictures, index), do: elem(pictures, index)

    @doc "Every handle held."
    @spec handles(t()) :: [Handle.t()]
    def handles(pictures),
      do:
        pictures
        |> Tuple.to_list()
        |> Enum.flat_map(&Enum.reject([&1.base, &1.glow], fn handle -> is_nil(handle) end))

    defp entry(gpu, %{kind: kind, mips: [first | _]}, palette, filter, game) do
      colours = colours(first.palette || palette, kind)
      base = picture(first, colours, filter)
      glow = if game == :quake and first.format == :indexed, do: glow(first, colours, filter)

      %{
        base: CauldronGPU.Target.texture(gpu, base),
        glow: glow && CauldronGPU.Target.texture(gpu, glow),
        kind: kind
      }
    end

    defp colours(palette, kind) do
      for(<<r, g, b <- palette>>, do: <<r, g, b, 255>>)
      |> List.to_tuple()
      |> then(fn table ->
        if kind == :masked, do: put_elem(table, 255, <<0, 0, 0, 0>>), else: table
      end)
    end

    defp picture(%{format: :rgba} = texture, _colours, filter),
      do: %Texture{
        width: texture.width,
        height: texture.height,
        pixels: texture.pixels,
        filter: filter
      }

    defp picture(texture, colours, filter) do
      pixels = for <<index <- texture.pixels>>, into: <<>>, do: elem(colours, index)
      %Texture{width: texture.width, height: texture.height, pixels: pixels, filter: filter}
    end

    defp glow(texture, colours, filter) do
      if :binary.bin_to_list(texture.pixels) |> Enum.any?(&(&1 >= 224 and &1 < 255)) do
        pixels =
          for <<index <- texture.pixels>>,
            into: <<>>,
            do: if(index >= 224 and index < 255, do: elem(colours, index), else: <<0, 0, 0, 255>>)

        %Texture{width: texture.width, height: texture.height, pixels: pixels, filter: filter}
      end
    end
  end
end
