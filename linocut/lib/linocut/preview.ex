defmodule Linocut.Preview do
  @moduledoc """
  Looking at rasters: on a sheet, in a terminal, or as a PNG.

      Linocut.Preview.sheet(headings, columns: 8, gap: 1)
      |> Linocut.Preview.to_terminal()
      |> IO.write()

  `to_terminal/2` picks the terminal's graphics protocol, or braille where it has none;
  `protocol:` forces one.
  """

  alias FrenchCurve.{Draw, Raster}

  @doc """
  One raster with `rasters` laid out in rows of `columns`.

  ## Options

    * `:columns` — rasters per row. Default `8`
    * `:gap` — pixels between rasters. Default `1`
    * `:background` — the sheet's colour. Default transparent
  """
  @spec sheet([Raster.t()], keyword()) :: Raster.t()
  def sheet(rasters, opts \\ []) do
    columns = Keyword.get(opts, :columns, 8)
    gap = Keyword.get(opts, :gap, 1)
    cell_w = rasters |> Enum.map(&elem(Raster.dimensions(&1), 0)) |> Enum.max(fn -> 1 end)
    cell_h = rasters |> Enum.map(&elem(Raster.dimensions(&1), 1)) |> Enum.max(fn -> 1 end)
    rows = div(length(rasters) + columns - 1, columns)
    width = max(1, columns * cell_w + (columns - 1) * gap)
    height = max(1, rows * cell_h + (rows - 1) * gap)
    sheet = Raster.new(width, height, background: Keyword.get(opts, :background, {0, 0, 0, 0}))

    rasters
    |> Enum.with_index()
    |> Enum.reduce(sheet, fn {raster, index}, acc ->
      left = rem(index, columns) * (cell_w + gap)
      top = div(index, columns) * (cell_h + gap)
      blit(acc, raster, left, top)
    end)
  end

  defp blit(sheet, raster, left, top) do
    {width, height} = Raster.dimensions(raster)

    for y <- 0..(height - 1)//1, x <- 0..(width - 1)//1, reduce: sheet do
      acc -> Raster.put_pixel(acc, left + x, top + y, Raster.get_pixel(raster, x, y))
    end
  end

  @doc """
  The bytes that show `raster` in a terminal.

  ## Options

    * `:protocol` — `:kitty`, `:iterm2`, `:sixel` or `:braille`. Default: detected
    * `:fit` — `{columns, rows}` for pixel protocols
  """
  @spec to_terminal(Raster.t(), keyword()) :: iodata()
  def to_terminal(%Raster{} = raster, opts \\ []) do
    protocol = Keyword.get_lazy(opts, :protocol, &FrenchCurve.Capability.detect/0)
    FrenchCurve.to_terminal(raster, protocol, Keyword.take(opts, [:fit]))
  end

  @doc "The raster as PNG bytes."
  @spec png(Raster.t()) :: binary()
  def png(%Raster{} = raster) do
    {width, height} = Raster.dimensions(raster)
    FrenchCurve.Png.encode(width, height, Raster.to_rgba_binary(raster))
  end

  @doc "A raster with a one-pixel frame drawn around it, to see its edges."
  @spec framed(Raster.t(), Linocut.Palette.spec()) :: Raster.t()
  def framed(%Raster{} = raster, colour \\ :gray) do
    {width, height} = Raster.dimensions(raster)
    Draw.rect(raster, {0, 0}, {width - 1, height - 1}, Linocut.Palette.color(colour))
  end
end
