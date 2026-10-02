defmodule Cauldron2D.Easel.Kino do
  @moduledoc """
  Cauldron2D art in a Livebook cell: a picture, an art directory as a sheet, or an
  animation, each as an image Livebook shows.

      Cauldron2D.Easel.Kino.image("priv/art/ship.pic", scale: 8)
      Cauldron2D.Easel.Kino.sheet("priv/art", tile: 16, scale: 4)
      Cauldron2D.Easel.Kino.animate("priv/art/flame.pic", scale: 8)

  A picture is a `Cauldron2D.Easel`, a `FrenchCurve.Raster`, or the path of a `.pic` or
  `.png`; frames of an easel show side by side in `image/2` and in turn in `animate/2`,
  at the easel's rate. `:scale` enlarges every pixel that many times (default `4`).
  """

  alias Cauldron2D.{Atlas, Easel, Sheet}
  alias Cauldron2D.Parallax.Preview
  alias FrenchCurve.{Png, Raster}

  @type picture :: Easel.t() | Raster.t() | Path.t()

  @doc "One picture as a PNG image."
  @spec image(picture(), keyword()) :: Kino.Image.t()
  def image(picture, opts \\ []) do
    picture |> raster_of(opts) |> to_image(Keyword.get(opts, :scale, 4))
  end

  @doc "Every art of a directory on one sheet, as `Cauldron2D.Sheet` packs it; `:tile` is required."
  @spec sheet(Path.t() | Atlas.t(), keyword()) :: Kino.Image.t()
  def sheet(%Atlas{} = atlas, opts),
    do: atlas |> Sheet.pack() |> Map.fetch!(:raster) |> to_image(Keyword.get(opts, :scale, 4))

  def sheet(dir, opts) when is_binary(dir) do
    {:ok, atlas} = Atlas.load(:easel_kino_sheet, dir, tile: Keyword.fetch!(opts, :tile))
    sheet(atlas, opts)
  end

  @doc "An easel's frames shown in turn in a `Kino.Frame`, at its rate; `:fps` overrides the rate. One frame is just its image."
  @spec animate(Easel.t() | Path.t(), keyword()) :: Kino.Frame.t() | Kino.Image.t()
  def animate(picture, opts \\ []) do
    easel = easel_of(picture, opts)
    scale = Keyword.get(opts, :scale, 4)
    images = easel |> Easel.rasters() |> Enum.map(&to_image(&1, scale))

    loop(images, Keyword.get(opts, :fps, easel.fps))
  end

  defp loop([only], _fps), do: only

  defp loop(images, fps) do
    frame = Kino.Frame.new()

    Kino.listen(div(1000, fps), fn index ->
      Kino.Frame.render(frame, Enum.at(images, rem(index, length(images))))
    end)

    frame
  end

  @doc """
  A camera moved across parallax layers, shown in turn in a `Kino.Frame`.

  Takes `Cauldron2D.Parallax.Preview.frames/3`'s options, with `:zoom` (default `2`)
  enlarging every pixel and `:fps` (default `20`) setting the rate.
  """
  @spec parallax(Atlas.name() | Atlas.t(), [Cauldron2D.Parallax.Layer.t()], keyword()) ::
          Kino.Frame.t() | Kino.Image.t()
  def parallax(atlas, layers, opts \\ []) do
    zoom = Keyword.get(opts, :zoom, 2)

    atlas
    |> Preview.frames(layers, opts)
    |> Enum.map(&to_image(&1, zoom))
    |> loop(Keyword.get(opts, :fps, 20))
  end

  @doc "The PNG bytes of a picture at a scale, for anything that takes bytes."
  @spec png(picture(), keyword()) :: binary()
  def png(picture, opts \\ []),
    do: picture |> raster_of(opts) |> scaled(Keyword.get(opts, :scale, 4)) |> encode()

  defp raster_of(%Easel{} = easel, _opts), do: Easel.strip(easel)
  defp raster_of(%Raster{} = raster, _opts), do: raster
  defp raster_of(path, opts) when is_binary(path), do: path |> easel_of(opts) |> Easel.strip()

  defp easel_of(%Easel{} = easel, _opts), do: easel

  defp easel_of(path, opts) when is_binary(path) do
    {:ok, easel} = Easel.load(path, Keyword.take(opts, [:frame]))
    easel
  end

  defp to_image(raster, scale), do: raster |> scaled(scale) |> encode() |> Kino.Image.new(:png)

  defp scaled(raster, 1), do: raster
  defp scaled(raster, scale), do: Linocut.scale(raster, scale)

  defp encode(%Raster{} = raster),
    do: Png.encode(raster.width, raster.height, Raster.to_rgba_binary(raster))
end
