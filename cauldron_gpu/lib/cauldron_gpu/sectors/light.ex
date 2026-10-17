if Code.ensure_loaded?(Cauldron2D.Sectors.Map) do
  defmodule CauldronGPU.Sectors.Light do
    @moduledoc """
    Sector light levels as a lightmap: one 256×1 texture holding the brightness of every
    light level `0..255`, and the lightmap coordinates that read level `n` from it.

    Brightness follows `Cauldron2D.Sectors.Light`'s ramp at a fixed viewing `distance`:
    the share of full colour the light table at that distance keeps, turned from sRGB
    into linear light.

        CauldronGPU.Sectors.Light.texture(256.0)
        CauldronGPU.Sectors.Light.uv(160)
    """

    alias Cauldron2D.Sectors.Light, as: Ramp
    alias CauldronGPU.Texture

    @levels 256

    @doc "The lightmap texture of every light level seen from `distance` map units."
    @spec texture(number()) :: Texture.t()
    def texture(distance) do
      pixels =
        for level <- 0..(@levels - 1), into: <<>> do
          value = brightness(level, distance)

          <<value::little-float-16, value::little-float-16, value::little-float-16,
            1.0::little-float-16>>
        end

      %Texture{
        width: @levels,
        height: 1,
        pixels: pixels,
        format: :rgba16f,
        filter: :nearest,
        wrap: :clamp,
        mipmaps: false
      }
    end

    @doc "Linear brightness `0.0..1.0` of light `level` seen from `distance`."
    @spec brightness(integer(), number()) :: float()
    def brightness(level, distance) do
      maps = 32
      share = (maps - Ramp.table(level, distance, maps: maps)) / maps
      :math.pow(share, 2.2)
    end

    @doc "The lightmap coordinates of light `level`, clamped to `0..255`."
    @spec uv(integer()) :: {float(), float()}
    def uv(level), do: {((level |> max(0) |> min(@levels - 1)) + 0.5) / @levels, 0.5}
  end
end
