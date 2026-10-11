defmodule Cauldron3D.Render do
  @moduledoc """
  Draws polygons seen through a view into a `Cauldron3D.Frame`.

      view = Cauldron3D.View.new(camera, {320, 200})
      frame = Cauldron3D.Render.draw(view, polygons, light_table: colormap)

  The picture is cut into bands of rows drawn at the same time, one per scheduler by
  default.

  ## Options

    * `:palette` — 768 bytes of red, green and blue: draws the picture in full colour,
      four bytes a pixel (`Cauldron3D.Paint.Rgba`), indexed textures without their own
      palette taking their colours from this one
    * `:light_table` — rows of 256 colours, brightest first, for lit paints
    * `:light_rows` — how many rows the table has, default its size over 256
    * `:background` — the colour where no polygon is, default 0 (in full colour, a
      palette index or `{r, g, b}`, default black)
    * `:backdrop` — in full colour, a `Cauldron3D.Frame` of RGBA pixels the size of the
      picture, shown where no polygon is and blended under the see-through ones,
      instead of `:background`
    * `:bands` — how many bands to draw at once, default `System.schedulers_online/0`
    * anything else is passed on in the paint context (see `Cauldron3D.Paint`)
  """

  alias Cauldron3D.{Frame, Polygon, Raster, Setup, View}

  @doc "The polygons drawn as `view` sees them."
  @spec draw(View.t(), [Polygon.t()], keyword()) :: Frame.t()
  def draw(%View{} = view, polygons, opts \\ []) do
    setups = setups(view, polygons, opts)
    draw_setups(view, setups, opts)
  end

  @doc "Polygons prepared for `view`, those that cannot be seen left out, set up in parallel."
  @spec setups(View.t(), [Polygon.t()], keyword()) :: [Setup.t()]
  def setups(%View{} = view, polygons, opts \\ []) do
    bands = Keyword.get(opts, :bands, System.schedulers_online())

    polygons
    |> Enum.chunk_every(max(div(length(polygons), bands) + 1, 64))
    |> Task.async_stream(
      fn chunk -> chunk |> Enum.map(&Setup.new(view, &1)) |> Enum.reject(&is_nil/1) end,
      timeout: :infinity
    )
    |> Enum.flat_map(fn {:ok, setups} -> setups end)
  end

  @doc "Prepared polygons drawn into a frame the size of `view`. Takes `draw/3`'s options."
  @spec draw_setups(View.t(), [Setup.t()], keyword()) :: Frame.t()
  def draw_setups(%View{width: width, height: height} = view, setups, opts \\ []) do
    context = context(view, opts)
    bands = min(Keyword.get(opts, :bands, System.schedulers_online()), height)
    per_band = div(height + bands - 1, bands)

    pixels =
      0..(height - 1)//per_band
      |> Task.async_stream(
        fn first ->
          Raster.rows(setups, first..min(first + per_band - 1, height - 1), width, context)
        end,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, rows} -> rows end)
      |> IO.iodata_to_binary()

    format = if Map.has_key?(context, :rgba), do: :rgba, else: :indexed
    %Frame{width: width, height: height, pixels: pixels, format: format}
  end

  defp context(view, opts) do
    {known, rest} =
      Keyword.split(opts, [:light_table, :light_rows, :background, :bands, :palette, :backdrop])

    table = Keyword.get(known, :light_table)
    palette = Keyword.get(known, :palette)

    context =
      rest
      |> Map.new()
      |> Map.merge(%{
        view: view,
        light_table: table,
        light_rows:
          Keyword.get(known, :light_rows) || if(table, do: div(byte_size(table), 256), else: 1),
        background: Keyword.get(known, :background, if(palette, do: {0, 0, 0}, else: 0))
      })

    context =
      if palette, do: Map.put(context, :rgba, Cauldron3D.Texture.colours(palette)), else: context

    case Keyword.get(known, :backdrop) do
      %Frame{width: width, pixels: pixels} -> Map.put(context, :backdrop, {width, pixels})
      nil -> context
    end
  end
end
