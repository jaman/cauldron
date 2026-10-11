defmodule Cauldron2D.Render do
  @moduledoc """
  A frame drawn once from a list of operations.

      Cauldron2D.Render.render({320, 200}, [
        {:raster, backdrop, {0, 0}},
        {:sprite, knight, %{position: {120.5, 88}, origin: {9, 28}, scale: {-1, 1}}}
      ], background: {20, 20, 40, 255})

  Each operation is drawn by what its shape says it is:

    * `{:sprite, picture, placement}` — a picture placed as `Cauldron2D.Blend.draw/6`
      takes a placement: position, origin, scale, angle, blend, alpha
    * `{:raster, picture, {x, y}}` — a picture drawn as it is, its top-left corner at
      `{x, y}`

  A picture is a `FrenchCurve.Raster` or `{width, height, rgba}`. Operations draw in
  list order, each over what came before.

  The frame is made once and drawn in bands of rows, each band drawn by one call that
  lays every operation over it in place: four bands by default, fewer where there are
  fewer schedulers. Where the C library is loaded the bands are drawn in C; where it is not, or with `native: false`,
  in Elixir, to the same pixels. The number of bands never changes the result.

  Options:

    * `:background` — what the frame starts as: a colour `{r, g, b, a}`, or a picture
      the frame's size; default transparent
    * `:format` — `:rgba` (default) gives a `FrenchCurve.Raster`; `:rgb` gives the
      pixels as a binary of three bytes each, alpha dropped
    * `:bands` — how many bands to draw at once
    * `:native` — `false` draws in Elixir
  """

  alias Cauldron2D.Blend
  alias FrenchCurve.Raster

  @type picture :: Raster.t() | {pos_integer(), pos_integer(), binary()}
  @type operation ::
          {:sprite, picture(), map()}
          | {:raster, picture(), {integer(), integer()}}

  @doc "The frame `{width, height}` pixels in size with `operations` drawn on it."
  @spec render({pos_integer(), pos_integer()}, [operation()], keyword()) :: Raster.t() | binary()
  def render({width, height}, operations, opts \\ []) when width > 0 and height > 0 do
    background = background(Keyword.get(opts, :background, {0, 0, 0, 0}), {width, height})
    items = Enum.map(operations, &item/1)
    band = band(Keyword.get(opts, :native, true))

    rgba =
      height
      |> bands(Keyword.get_lazy(opts, :bands, fn -> min(4, System.schedulers_online()) end))
      |> Task.async_stream(
        fn {top, bottom} ->
          band.(width, top, bottom, rows(background, width, top, bottom), items)
        end,
        ordered: true,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, rows} -> rows end)
      |> IO.iodata_to_binary()

    output(rgba, {width, height}, Keyword.get(opts, :format, :rgba))
  end

  defp background({red, green, blue, alpha}, _size)
       when red in 0..255 and green in 0..255 and blue in 0..255 and alpha in 0..255,
       do: {:colour, <<red, green, blue, alpha>>}

  defp background(%Raster{} = picture, size), do: picture_background(picture, size)

  defp background({_width, _height, rgba} = picture, size) when is_binary(rgba),
    do: picture_background(picture, size)

  defp background(other, _size) do
    raise ArgumentError,
          "a background is a colour {r, g, b, a}, each 0..255, or a picture the frame's size, " <>
            "not #{inspect(other, limit: 3)}"
  end

  defp picture_background(picture, {width, height}) do
    case pixels(picture) do
      {^width, ^height, rgba} ->
        {:picture, rgba}

      {other_width, other_height, _rgba} ->
        raise ArgumentError,
              "a background picture must be the frame's size, #{width}x#{height}, " <>
                "not #{other_width}x#{other_height}"
    end
  end

  defp rows(
         {:colour, colour},
         _width,
         _top,
         _bottom
       ),
       do: colour

  defp rows({:picture, rgba}, width, top, bottom),
    do: binary_part(rgba, top * width * 4, (bottom - top) * width * 4)

  defp item({:sprite, picture, placement}) do
    {width, height, rgba} = pixels(picture)
    {rgba, width, height, Blend.transform(placement)}
  end

  defp item({:raster, picture, {x, y}}) when is_integer(x) and is_integer(y),
    do: item({:sprite, picture, %{position: {x, y}}})

  defp item(operation) do
    raise ArgumentError,
          "not an operation Cauldron2D.Render draws: #{inspect(operation, limit: 3)}; " <>
            "expected {:sprite, picture, placement} or {:raster, picture, {x, y}}"
  end

  defp pixels(%Raster{} = raster) do
    {width, height} = Raster.dimensions(raster)
    {width, height, Raster.to_rgba_binary(raster)}
  end

  defp pixels({width, height, rgba} = picture) do
    Blend.sized!(rgba, width, height, "picture")
    picture
  end

  defp pixels(other) do
    raise ArgumentError,
          "a picture is a FrenchCurve.Raster or {width, height, rgba}, not #{inspect(other, limit: 3)}"
  end

  defp band(true), do: &Blend.render_band/5
  defp band(false), do: &Blend.elixir_render_band/5

  defp bands(height, count) do
    per_band = div(height + max(count, 1) - 1, max(count, 1))
    for top <- 0..(height - 1)//per_band, do: {top, min(top + per_band, height)}
  end

  defp output(rgba, {width, height}, :rgba), do: Raster.from_rgba(width, height, rgba)

  defp output(rgba, _size, :rgb),
    do: for(<<red, green, blue, _alpha <- rgba>>, into: <<>>, do: <<red, green, blue>>)
end
