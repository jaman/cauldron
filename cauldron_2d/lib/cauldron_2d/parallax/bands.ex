defmodule Cauldron2D.Parallax.Bands do
  @moduledoc """
  Horizontal bands of one layer, each scrolling at its own factor.

      bands = Cauldron2D.Parallax.Bands.new([{0..5, 0.1}, {6..11, 0.45}, {12..23, 0.9}])
      Cauldron2D.Parallax.Bands.roll(raster, bands, {focus_x, focus_y}, tile)

  Ranges are tile rows from the top of the picture, read in order, the first range holding
  a row deciding it. A row no range covers does not move. A band reads the focus itself, so
  a layer that carries bands wants a factor of `0.0` on the axis they move along.
  """

  alias FrenchCurve.Raster

  @type t :: %__MODULE__{ranges: [{Range.t(), float()}]}

  defstruct ranges: []

  @doc "Bands from `[{tile_rows, factor}]`."
  @spec new([{Range.t(), number()}]) :: t()
  def new(ranges) do
    %__MODULE__{ranges: Enum.map(ranges, fn {rows, factor} -> {rows, factor / 1} end)}
  end

  @doc "The factor for tile row `row`, or `0.0` where no band covers it."
  @spec factor(t(), integer()) :: float()
  def factor(%__MODULE__{ranges: ranges}, row) do
    Enum.find_value(ranges, 0.0, fn {rows, factor} ->
      Enum.member?(rows, row) && factor
    end)
  end

  @doc "`raster` with every band's pixel rows rolled sideways by its own share of `focus`."
  @spec roll(Raster.t(), t() | nil, {number(), number()}, pos_integer()) :: Raster.t()
  def roll(raster, nil, _focus, _tile), do: raster

  def roll(raster, %__MODULE__{ranges: []}, _focus, _tile), do: raster

  def roll(%Raster{width: width, height: height} = raster, bands, {fx, _fy}, tile) do
    stride = width * 4
    rgba = Raster.to_rgba_binary(raster)

    shifts =
      Map.new(0..div(height - 1, tile), fn row ->
        {row, Integer.mod(round(-fx * factor(bands, row) * tile), width) * 4}
      end)

    rolled =
      for y <- 0..(height - 1)//1 do
        rgba
        |> binary_part(y * stride, stride)
        |> roll_row(Map.fetch!(shifts, div(y, tile)))
      end

    Raster.from_rgba(width, height, IO.iodata_to_binary(rolled))
  end

  defp roll_row(row, 0), do: row

  defp roll_row(row, cut) do
    <<head::binary-size(cut), tail::binary>> = row
    [tail, head]
  end
end
