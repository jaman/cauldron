defmodule Cauldron2D.Parallax.Preview do
  @moduledoc """
  A camera moved across a set of layers, as a list of pictures.

      Cauldron2D.Parallax.Preview.frames(:beast, layers,
        focus: {0.0, 11.0},
        size: {44, 22},
        travel: {60.0, 0.0},
        frames: 90
      )

  Each picture is the layers behind the world with those in front laid over them and
  nothing of the world between, so a set of layers can be looked at before a game is built.
  """

  alias Cauldron2D.{Atlas, Parallax, Surface}
  alias FrenchCurve.Raster

  @doc """
  The pictures a camera sees as it travels.

  ## Options

    * `:focus` — the world point the camera starts on, required
    * `:size` — `{columns, rows}` of the picture in tiles, required
    * `:travel` — how far the camera moves over the whole run, in tiles.
      Default `{40.0, 0.0}`
    * `:frames` — how many pictures. Default `60`
    * `:ms` — milliseconds between pictures, for drift and animation. Default `33`
    * `:scale` — a positive integer dividing the tile size. Default `1`
  """
  @spec frames(Atlas.name() | Atlas.t(), [Parallax.Layer.t()], keyword()) :: [Raster.t()]
  def frames(atlas, layers, opts) do
    atlas = Atlas.fetch(atlas)
    {fx, fy} = Keyword.fetch!(opts, :focus)
    {dx, dy} = Keyword.get(opts, :travel, {40.0, 0.0})
    size = Keyword.fetch!(opts, :size)
    count = Keyword.get(opts, :frames, 60)
    scale = Keyword.get(opts, :scale, 1)
    ms = Keyword.get(opts, :ms, 33)

    for index <- 0..(count - 1)//1 do
      share = index / count

      picture(atlas, layers, {fx + dx * share, fy + dy * share}, size, index * ms, scale)
    end
  end

  defp picture(atlas, layers, focus, size, at, scale) do
    opts = [focus: focus, size: size, at: at, scale: scale]

    atlas
    |> Parallax.compose(layers, opts)
    |> over(Parallax.compose(atlas, layers, [{:front, true} | opts]), atlas, size, scale)
  end

  defp over(nil, nil, atlas, size, scale), do: blank(atlas, size, scale)
  defp over(behind, nil, _atlas, _size, _scale), do: behind
  defp over(nil, front, _atlas, _size, _scale), do: front
  defp over(behind, front, _atlas, _size, _scale), do: Surface.stack(behind, front)

  defp blank(atlas, {columns, rows}, scale) do
    tile = max(1, div(atlas.tile, scale))
    {r, g, b} = atlas.void

    Raster.new(round(columns * tile), round(rows * tile), background: {r, g, b, 255})
  end
end
