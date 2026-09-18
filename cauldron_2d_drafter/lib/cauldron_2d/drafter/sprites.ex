defmodule Cauldron2D.Drafter.Sprites do
  @moduledoc """
  An atlas's art as stored kitty images, transmitted once and placed many times.

      Drafter.Compositor.write_raw(Cauldron2D.Drafter.Sprites.transmit(:my_game))

  Every frame of every art in the atlas gets a stable image id from `image_id/3`, so a
  surface can place it by id on any later frame without sending pixels again. Transmit
  once per session, and again after anything that empties the terminal's image store or
  changes the atlas.
  """

  alias Cauldron2D.Atlas
  alias FrenchCurve.Backend.Kitty
  alias FrenchCurve.Raster

  @span 4096

  @doc """
  The bytes that store every frame of every art of `atlas` in the terminal, without
  displaying any.

  ## Options

    * `:size` — `{width, height}` in pixels to store each sprite at, resampled
      nearest-neighbour once here, so a placement of that size is drawn pixel for pixel
      and the terminal scales nothing. Default: the sprite's own size
    * `:compress` — zlib each transmit. Default `true`
  """
  @spec transmit(Atlas.name() | Atlas.t(), keyword()) :: iodata()
  def transmit(atlas, opts \\ []) do
    atlas = Atlas.fetch(atlas)
    compress? = Keyword.get(opts, :compress, true)
    size = Keyword.get(opts, :size)

    for {art, frame_index, sprite} <- frames(atlas) do
      Kitty.transmit(resampled(sprite.raster, size), image_id(atlas, art) + frame_index,
        compress: compress?
      )
    end
  end

  @doc """
  `raster` at `{width, height}` pixels, each output pixel the nearest source pixel; the
  raster itself at its own size or with `nil`.
  """
  @spec resampled(Raster.t(), {pos_integer(), pos_integer()} | nil) :: Raster.t()
  def resampled(%Raster{} = raster, nil), do: raster
  def resampled(%Raster{width: w, height: h} = raster, {w, h}), do: raster

  def resampled(%Raster{width: sw, height: sh} = raster, {width, height}) do
    source = Raster.to_rgba_binary(raster)

    rows =
      for oy <- 0..(height - 1)//1 do
        sy = div(oy * sh, height)

        for ox <- 0..(width - 1)//1, into: <<>> do
          binary_part(source, (sy * sw + div(ox * sw, width)) * 4, 4)
        end
      end

    Raster.from_rgba(width, height, IO.iodata_to_binary(rows))
  end

  @doc "The kitty image id under which the first frame of `art` of `atlas` is stored; the same on every call."
  @spec image_id(Atlas.name() | Atlas.t(), Atlas.art()) :: pos_integer()
  def image_id(atlas, art) do
    atlas = Atlas.fetch(atlas)
    base = :erlang.phash2(atlas.name, 500_000) * @span + 1

    case Map.fetch(first_ids(atlas), art) do
      :error -> raise ArgumentError, "atlas #{inspect(atlas.name)} has no art #{inspect(art)}"
      {:ok, offset} -> base + offset
    end
  end

  @doc "The kitty image id of the frame of `art` showing at `at_ms`."
  @spec image_id(Atlas.name() | Atlas.t(), Atlas.art(), integer()) :: pos_integer()
  def image_id(atlas, art, at_ms) do
    atlas = Atlas.fetch(atlas)
    image_id(atlas, art) + Atlas.frame_index(atlas, art, at_ms)
  end

  @label_base 2_100_000_000
  @label_span 40_000_000

  @doc "The kitty image id of `text` drawn in `colour` at `scale` by `Linocut.Font`, the same on every call."
  @spec label_id(Atlas.name() | Atlas.t(), String.t(), Atlas.rgb(), pos_integer()) ::
          pos_integer()
  def label_id(atlas, text, colour, scale) do
    atlas = Atlas.fetch(atlas)
    @label_base + :erlang.phash2({atlas.name, text, colour, scale}, @label_span)
  end

  @doc "The bytes that store `text` drawn in `colour` at `scale` under its `label_id/4`."
  @spec label_transmit(
          Atlas.name() | Atlas.t(),
          String.t(),
          Atlas.rgb(),
          pos_integer(),
          keyword()
        ) :: iodata()
  def label_transmit(atlas, text, colour, scale, opts \\ []) do
    Kitty.transmit(
      Linocut.Font.render(text, colour, scale: scale),
      label_id(atlas, text, colour, scale),
      compress: Keyword.get(opts, :compress, true)
    )
  end

  defp first_ids(atlas) do
    {ids, _next} =
      Enum.map_reduce(ordered(atlas), 0, fn art, next ->
        {{art, next}, next + length(Atlas.entry(atlas, art).frames)}
      end)

    Map.new(ids)
  end

  defp frames(atlas) do
    for art <- ordered(atlas),
        {sprite, index} <- Enum.with_index(Atlas.entry(atlas, art).frames),
        do: {art, index, sprite}
  end

  defp ordered(atlas), do: atlas |> Atlas.arts() |> Enum.sort()
end
