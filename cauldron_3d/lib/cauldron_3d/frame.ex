defmodule Cauldron3D.Frame do
  @moduledoc """
  A rendered picture, rows top to bottom: indexed colour, one byte per pixel, or RGBA,
  four.

      frame = Cauldron3D.Render.draw(view, polygons)
      Cauldron3D.Frame.rgba(frame, palette)
  """

  alias Cauldron3D.Frame.Pixels

  @enforce_keys [:width, :height, :pixels]
  defstruct [:width, :height, :pixels, format: :indexed]

  @type t :: %__MODULE__{
          width: pos_integer(),
          height: pos_integer(),
          pixels: binary(),
          format: :indexed | :rgba
        }

  @doc "A frame of one colour."
  @spec new(pos_integer(), pos_integer(), byte()) :: t()
  def new(width, height, colour \\ 0),
    do: %__MODULE__{
      width: width,
      height: height,
      pixels: :binary.copy(<<colour>>, width * height)
    }

  @doc "The frame as RGBA bytes: an indexed frame through `palette`, 768 bytes of red, green and blue."
  @spec rgba(t(), binary() | nil) :: binary()
  def rgba(%__MODULE__{format: :rgba, pixels: pixels}, _palette), do: pixels

  def rgba(%__MODULE__{pixels: pixels}, palette) when byte_size(palette) == 768 do
    colours = for <<r, g, b <- palette>>, do: <<r, g, b, 255>>
    table = List.to_tuple(colours)
    for <<index <- pixels>>, into: <<>>, do: elem(table, index)
  end

  @doc "The frame as RGB bytes: an indexed frame through `palette`."
  @spec rgb(t(), binary() | nil) :: binary()
  def rgb(%__MODULE__{format: :rgba, pixels: pixels}, _palette),
    do: for(<<r, g, b, _a <- pixels>>, into: <<>>, do: <<r, g, b>>)

  def rgb(%__MODULE__{pixels: pixels}, palette) when byte_size(palette) == 768 do
    table = List.to_tuple(for <<r, g, b <- palette>>, do: <<r, g, b>>)
    for <<index <- pixels>>, into: <<>>, do: elem(table, index)
  end

  @doc """
  `overlay` drawn over `frame` with its top left at `{x, y}`, its pixels of colour
  `clear` left out; the parts outside the frame are cut off. A `Cauldron3D.Texture`
  serves as an overlay too. On an RGBA frame the overlay is RGBA too, laid over by its
  alpha, and `clear` is not used.
  """
  @spec blit(t(), t() | Cauldron3D.Texture.t(), {integer(), integer()}, byte() | nil) :: t()
  def blit(frame, overlay, at, clear \\ nil)

  def blit(
        %__MODULE__{format: :rgba} = frame,
        %{width: ow, height: oh, pixels: over},
        {left, top},
        _clear
      ) do
    first_row = max(top, 0)
    last_row = min(top + oh, frame.height) - 1
    first_col = max(left, 0)
    last_col = min(left + ow, frame.width) - 1

    if first_row > last_row or first_col > last_col do
      frame
    else
      span = last_col - first_col + 1
      row_bytes = frame.width * 4
      before = binary_part(frame.pixels, 0, first_row * row_bytes)
      after_start = (last_row + 1) * row_bytes
      after_part = binary_part(frame.pixels, after_start, byte_size(frame.pixels) - after_start)

      rows =
        for y <- first_row..last_row do
          row = binary_part(frame.pixels, y * row_bytes, row_bytes)
          under = binary_part(row, first_col * 4, span * 4)
          above = binary_part(over, ((y - top) * ow + (first_col - left)) * 4, span * 4)

          [
            binary_part(row, 0, first_col * 4),
            Pixels.lay(under, above),
            binary_part(row, (last_col + 1) * 4, (frame.width - last_col - 1) * 4)
          ]
        end

      %{frame | pixels: IO.iodata_to_binary([before, rows, after_part])}
    end
  end

  def blit(
        %__MODULE__{} = frame,
        %{width: ow, height: oh, pixels: over},
        {left, top},
        clear
      ) do
    first_row = max(top, 0)
    last_row = min(top + oh, frame.height) - 1
    first_col = max(left, 0)
    last_col = min(left + ow, frame.width) - 1

    if first_row > last_row or first_col > last_col do
      frame
    else
      span = last_col - first_col + 1
      before = binary_part(frame.pixels, 0, first_row * frame.width)
      after_start = (last_row + 1) * frame.width
      after_part = binary_part(frame.pixels, after_start, byte_size(frame.pixels) - after_start)

      rows =
        for y <- first_row..last_row do
          row = binary_part(frame.pixels, y * frame.width, frame.width)
          under = binary_part(row, first_col, span)
          above = binary_part(over, (y - top) * ow + (first_col - left), span)

          [
            binary_part(row, 0, first_col),
            merge(under, above, clear),
            binary_part(row, last_col + 1, frame.width - last_col - 1)
          ]
        end

      %{frame | pixels: IO.iodata_to_binary([before, rows, after_part])}
    end
  end

  @doc "The frame scaled to `{width, height}` by taking the nearest pixel."
  @spec scale(t() | Cauldron3D.Texture.t(), pos_integer(), pos_integer()) :: t()
  def scale(%{format: :rgba, width: w, height: h, pixels: pixels}, width, height) do
    columns = runs(width, w)

    rows =
      for {row, count} <- runs(height, h) do
        source = binary_part(pixels, row * w * 4, w * 4)

        line =
          for {column, repeat} <- columns,
              into: <<>>,
              do: :binary.copy(binary_part(source, column * 4, 4), repeat)

        List.duplicate(line, count)
      end

    %__MODULE__{width: width, height: height, pixels: IO.iodata_to_binary(rows), format: :rgba}
  end

  def scale(%{width: w, height: h, pixels: pixels}, width, height) do
    columns = for x <- 0..(width - 1), do: min(div(x * w, width), w - 1)

    rows =
      for y <- 0..(height - 1) do
        source = binary_part(pixels, min(div(y * h, height), h - 1) * w, w)
        for x <- columns, into: <<>>, do: <<:binary.at(source, x)>>
      end

    %__MODULE__{width: width, height: height, pixels: IO.iodata_to_binary(rows)}
  end

  defp runs(size, source) do
    0..(size - 1)
    |> Enum.map(&min(div(&1 * source, size), source - 1))
    |> Enum.chunk_by(& &1)
    |> Enum.map(&{hd(&1), length(&1)})
  end

  defp merge(_under, above, nil), do: above

  defp merge(under, above, clear) do
    if :binary.match(above, <<clear>>) == :nomatch,
      do: above,
      else: see_through(under, above, clear)
  end

  defp see_through(under, above, clear) do
    for {a, b} <- Enum.zip(:binary.bin_to_list(under), :binary.bin_to_list(above)),
        into: <<>>,
        do: if(b == clear, do: <<a>>, else: <<b>>)
  end
end
