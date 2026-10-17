if Code.ensure_loaded?(Cauldron2D.Sectors.Map) do
  defmodule CauldronGPU.Sectors.Live.Lightmap do
    @moduledoc """
    Every sector's light level as a lightmap, for a `CauldronGPU.Sectors.Live.LightTable`
    to turn into light: a texture three texels wide and one row per sector, the row's
    texels the sector's light level with `-16`, `0` and `16` added (a wall's contrast),
    each written as `(level + 0.5) / 256` with the level clamped to `0..255`, the column of
    the light table that level reads.

        texture = CauldronGPU.Sectors.Live.Lightmap.texture([160, 255], 0, nil)
        CauldronGPU.Sectors.Live.Lightmap.uv({1, 16}, 2)

    `extra` is light added to every level; a `fixed` light table other than `nil` writes
    every texel as full light, `1.0`.
    """

    alias CauldronGPU.Texture

    @contrasts [-16, 0, 16]
    @levels 256

    @doc "The lightmap of sectors whose light levels are `levels`, in sector order."
    @spec texture([integer()], integer(), non_neg_integer() | nil) :: Texture.t()
    def texture(levels, extra, fixed) do
      pixels =
        for level <- levels, contrast <- @contrasts, into: <<>> do
          value = code(level + contrast + extra, fixed)

          <<value::little-float-16, value::little-float-16, value::little-float-16,
            1.0::little-float-16>>
        end

      %Texture{
        width: length(@contrasts),
        height: max(length(levels), 1),
        pixels: pixels,
        format: :rgba16f,
        filter: :nearest,
        wrap: :clamp,
        mipmaps: false
      }
    end

    @doc "The lightmap coordinates of `{sector, contrast}` in a lightmap of `count` sectors."
    @spec uv({non_neg_integer(), integer()}, pos_integer()) :: {float(), float()}
    def uv({sector, contrast}, count) do
      column = Enum.find_index(@contrasts, &(&1 == contrast)) || 1
      {(column + 0.5) / length(@contrasts), (sector + 0.5) / count}
    end

    @doc "The value light `level` is written as: the light table column it reads."
    @spec code(integer(), non_neg_integer() | nil) :: float()
    def code(_level, fixed) when fixed != nil, do: 1.0
    def code(level, nil), do: ((level |> max(0) |> min(@levels - 1)) + 0.5) / @levels
  end
end
