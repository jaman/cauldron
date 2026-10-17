if Code.ensure_loaded?(Cauldron2D.Sectors.Map) do
  defmodule CauldronGPU.Sectors.Live.LightTable do
    @moduledoc """
    Sector light falling with distance, as an `CauldronGPU.Environment` `light_table`:
    column `n` of 256 is light level `n` (as `CauldronGPU.Sectors.Live.Lightmap` writes
    it), row `r` the distance `r / (rows - 1)` of the table's reach, and each texel the
    share of a colour's display value left by the light table
    `Cauldron2D.Sectors.Light.table/3` picks for that level and distance, as
    `(maps - table) / maps`. It is meant for `light_space: :display`.

        {texture, reach} = CauldronGPU.Sectors.Live.LightTable.texture(1 / 32, [])

    `scale` is metres per map unit; `reach` comes back in metres. `light` is the options
    `Cauldron2D.Sectors.Light` takes (`:maps`, `:levels`, `:fade`). Options: `:rows`
    (default 1024) and `:reach` in map units (default 2048).
    """

    alias Cauldron2D.Sectors.Light
    alias CauldronGPU.Texture

    @levels 256

    @doc "The light table texture and its reach in metres."
    @spec texture(number(), keyword(), keyword()) :: {Texture.t(), float()}
    def texture(scale, light, opts \\ []) do
      rows = Keyword.get(opts, :rows, 1024)
      reach = Keyword.get(opts, :reach, 2048)
      maps = Keyword.get(light, :maps, 32)

      pixels =
        for row <- 0..(rows - 1), level <- 0..(@levels - 1), into: <<>> do
          distance = row / (rows - 1) * reach
          value = (maps - Light.table(level, distance, light)) / maps

          <<value::little-float-16, value::little-float-16, value::little-float-16,
            1.0::little-float-16>>
        end

      texture = %Texture{
        width: @levels,
        height: rows,
        pixels: pixels,
        format: :rgba16f,
        filter: :linear,
        wrap: :clamp,
        mipmaps: false
      }

      {texture, reach * scale}
    end
  end
end
