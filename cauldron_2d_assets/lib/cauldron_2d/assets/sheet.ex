defmodule Cauldron2D.Assets.Sheet do
  @moduledoc """
  The candidates for one asset side by side on a dark ground, each drawn large enough to
  judge and numbered from `0` above it, as a PNG to look at before choosing.
  """

  alias FrenchCurve.Raster

  @height 160
  @gap 12
  @label 12
  @ground {24, 20, 32, 255}

  @doc "Write the sheet of `pictures` to `path`."
  @spec write(Path.t(), [Raster.t()]) :: :ok
  def write(path, pictures) do
    sheet = compose(pictures)
    File.mkdir_p!(Path.dirname(path))

    File.write!(
      path,
      FrenchCurve.Png.encode(sheet.width, sheet.height, Raster.to_rgba_binary(sheet))
    )
  end

  @doc "The sheet of `pictures`, as a raster."
  @spec compose([Raster.t()]) :: Raster.t()
  def compose(pictures) do
    shown = Enum.map(pictures, &large/1)
    width = Enum.reduce(shown, @gap, fn picture, acc -> acc + picture.width + @gap end)
    height = @height + @label + 2 * @gap
    canvas = solid(width, height)

    shown
    |> Enum.with_index()
    |> Enum.reduce({canvas, @gap}, fn {picture, index}, {acc, x} ->
      number = Linocut.Font.render(Integer.to_string(index), {240, 230, 200}, scale: 2)
      placed = acc |> over(number, {x, @gap}) |> over(picture, {x, @gap + @label})
      {placed, x + picture.width + @gap}
    end)
    |> elem(0)
  end

  defp large(%Raster{height: height} = picture) do
    times = max(1, div(@height, max(height, 1)))
    Linocut.scale(picture, times)
  end

  defp solid(width, height) do
    {r, g, b, a} = @ground
    Raster.from_rgba(width, height, :binary.copy(<<r, g, b, a>>, width * height))
  end

  defp over(canvas, picture, {left, top}) do
    rgba = Raster.to_rgba_binary(picture)

    for y <- 0..(picture.height - 1), x <- 0..(picture.width - 1), reduce: canvas do
      acc ->
        case binary_part(rgba, (y * picture.width + x) * 4, 4) do
          <<_r, _g, _b, 0>> -> acc
          <<r, g, b, a>> -> Raster.put_pixel(acc, left + x, top + y, {r, g, b, a})
        end
    end
  end
end
