defmodule Linocut.Slices do
  @moduledoc """
  A picture grown to another size by cutting it in nine: the four corners kept as they
  are, the four edges repeated along their length, and the middle repeated both ways.
  Frames, panels, buttons and speech balloons drawn once at any size they are needed.

      Linocut.Slices.nine(frame, 4, {120, 32})
  """

  alias FrenchCurve.Raster

  @doc """
  `raster` at `{width, height}`, its corners `border` pixels square. The size must be
  at least two borders each way; a smaller one is raised to that.
  """
  @spec nine(Raster.t(), pos_integer(), {pos_integer(), pos_integer()}) :: Raster.t()
  def nine(%Raster{width: source_width, height: source_height} = raster, border, {width, height})
      when border > 0 and 2 * border < source_width and 2 * border < source_height do
    width = max(width, 2 * border)
    height = max(height, 2 * border)
    rows = rows(raster)

    rows
    |> Enum.map(&stretch(&1, source_width, border, width))
    |> stretch_rows(source_height, border, height)
    |> IO.iodata_to_binary()
    |> then(&Raster.from_rgba(width, height, &1))
  end

  defp rows(%Raster{width: width} = raster),
    do: for(<<row::binary-size(^width * 4) <- Raster.to_rgba_binary(raster)>>, do: row)

  defp stretch(row, source_width, border, width) do
    first = binary_part(row, 0, border * 4)
    middle = binary_part(row, border * 4, (source_width - 2 * border) * 4)
    last = binary_part(row, (source_width - border) * 4, border * 4)
    [first, repeat(middle, (width - 2 * border) * 4), last]
  end

  defp stretch_rows(rows, source_height, border, height) do
    {top, rest} = Enum.split(rows, border)
    {middle, bottom} = Enum.split(rest, source_height - 2 * border)
    top ++ cycle(middle, height - 2 * border) ++ bottom
  end

  defp repeat(_pattern, 0), do: <<>>

  defp repeat(pattern, bytes) do
    copies = div(bytes, byte_size(pattern)) + 1
    binary_part(:binary.copy(pattern, copies), 0, bytes)
  end

  defp cycle(rows, count), do: rows |> Stream.cycle() |> Enum.take(count)
end
