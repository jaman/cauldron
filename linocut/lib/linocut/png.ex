defmodule Linocut.Png do
  @moduledoc """
  Reads a PNG into a `FrenchCurve.Raster`.

      {:ok, raster} = Linocut.Png.decode(File.read!("ship.png"))

  Greyscale, greyscale with alpha, truecolour, truecolour with alpha and palette images
  are read, at every bit depth; sixteen-bit channels keep their high byte. A `tRNS`
  chunk gives palette entries and colour keys their alpha. Interlaced images are
  refused with `{:error, :interlaced}`; anything that is not a PNG with
  `{:error, :not_png}`.
  """

  alias FrenchCurve.Raster

  @signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  @doc "The raster in `bytes`, or why it could not be read."
  @spec decode(binary()) :: {:ok, Raster.t()} | {:error, term()}
  def decode(<<@signature, chunks::binary>>) do
    with {:ok, png} <- chunks(chunks, %{idat: []}),
         :ok <- supported(png),
         {:ok, raw} <- inflate(png.idat) do
      rows = unfilter(raw, stride(png), bytes_per_pixel(png), png.height)
      {:ok, Raster.from_rgba(png.width, png.height, rgba(rows, png))}
    end
  end

  def decode(_bytes), do: {:error, :not_png}

  defp chunks(
         <<size::32, type::binary-size(4), data::binary-size(size), _crc::32, rest::binary>>,
         png
       ) do
    case type do
      "IHDR" -> chunks(rest, header(png, data))
      "PLTE" -> chunks(rest, Map.put(png, :palette, for(<<r, g, b <- data>>, do: {r, g, b})))
      "tRNS" -> chunks(rest, Map.put(png, :trns, data))
      "IDAT" -> chunks(rest, %{png | idat: [png.idat, data]})
      "IEND" -> {:ok, png}
      _other -> chunks(rest, png)
    end
  end

  defp chunks(_short, _png), do: {:error, :truncated}

  defp header(png, <<width::32, height::32, depth, colour_type, 0, 0, interlace>>) do
    Map.merge(png, %{
      width: width,
      height: height,
      depth: depth,
      colour_type: colour_type,
      interlace: interlace
    })
  end

  defp supported(%{interlace: 1}), do: {:error, :interlaced}
  defp supported(%{width: width, height: height}) when width > 0 and height > 0, do: :ok
  defp supported(_png), do: {:error, :not_png}

  defp inflate(idat) do
    {:ok, :zlib.uncompress(IO.iodata_to_binary(idat))}
  rescue
    ErlangError -> {:error, :corrupt}
  end

  defp channels(0), do: 1
  defp channels(2), do: 3
  defp channels(3), do: 1
  defp channels(4), do: 2
  defp channels(6), do: 4

  defp bits_per_pixel(png), do: channels(png.colour_type) * png.depth
  defp bytes_per_pixel(png), do: max(1, div(bits_per_pixel(png), 8))
  defp stride(png), do: div(png.width * bits_per_pixel(png) + 7, 8)

  defp unfilter(raw, stride, bpp, height) do
    prior = :binary.copy(<<0>>, stride)

    {rows, _prior} =
      Enum.map_reduce(1..height//1, {raw, prior}, fn _,
                                                     {<<filter, line::binary-size(^stride),
                                                        rest::binary>>, prior} ->
        row = reconstruct(filter, line, prior, bpp)
        {row, {rest, row}}
      end)

    rows
  end

  defp reconstruct(0, line, _prior, _bpp), do: line

  defp reconstruct(1, line, _prior, bpp),
    do: bytes(line, <<>>, bpp, fn raw, a, _b, _c -> raw + a end)

  defp reconstruct(2, line, prior, bpp),
    do: bytes(line, prior, bpp, fn raw, _a, b, _c -> raw + b end)

  defp reconstruct(3, line, prior, bpp),
    do: bytes(line, prior, bpp, fn raw, a, b, _c -> raw + div(a + b, 2) end)

  defp reconstruct(4, line, prior, bpp),
    do: bytes(line, prior, bpp, fn raw, a, b, c -> raw + paeth(a, b, c) end)

  defp bytes(line, prior, bpp, predict) do
    {out, _} =
      for <<raw <- line>>, reduce: {<<>>, 0} do
        {out, index} ->
          a = neighbour(out, index - bpp)
          b = neighbour(prior, index)
          c = neighbour(prior, index - bpp)
          {<<out::binary, rem(predict.(raw, a, b, c), 256)>>, index + 1}
      end

    out
  end

  defp neighbour(_binary, index) when index < 0, do: 0
  defp neighbour(binary, index) when index >= byte_size(binary), do: 0
  defp neighbour(binary, index), do: :binary.at(binary, index)

  defp paeth(a, b, c) do
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)

    cond do
      pa <= pb and pa <= pc -> a
      pb <= pc -> b
      true -> c
    end
  end

  defp rgba(rows, png) do
    rows
    |> Enum.map(&row_rgba(&1, png))
    |> IO.iodata_to_binary()
  end

  defp row_rgba(row, %{colour_type: 6, depth: 8}), do: row

  defp row_rgba(row, %{colour_type: 6, depth: 16}),
    do: for(<<r, _, g, _, b, _, a, _ <- row>>, into: <<>>, do: <<r, g, b, a>>)

  defp row_rgba(row, %{colour_type: 2, depth: 8} = png),
    do: for(<<r, g, b <- row>>, into: <<>>, do: <<r, g, b, key_alpha(png, {r, g, b})>>)

  defp row_rgba(row, %{colour_type: 2, depth: 16} = png),
    do: for(<<r, _, g, _, b, _ <- row>>, into: <<>>, do: <<r, g, b, key_alpha(png, {r, g, b})>>)

  defp row_rgba(row, %{colour_type: 4, depth: 8}),
    do: for(<<v, a <- row>>, into: <<>>, do: <<v, v, v, a>>)

  defp row_rgba(row, %{colour_type: 4, depth: 16}),
    do: for(<<v, _, a, _ <- row>>, into: <<>>, do: <<v, v, v, a>>)

  defp row_rgba(row, %{colour_type: 0, depth: 16} = png),
    do: for(<<v, _ <- row>>, into: <<>>, do: <<v, v, v, key_alpha(png, v)>>)

  defp row_rgba(row, %{colour_type: 0, depth: depth} = png) do
    top = Bitwise.bsl(1, depth) - 1

    for(<<value::size(^depth) <- row>>,
      into: <<>>,
      do: <<grey(value, top), grey(value, top), grey(value, top), key_alpha(png, value)>>
    )
    |> take_pixels(png.width)
  end

  defp row_rgba(row, %{colour_type: 3, depth: depth} = png) do
    palette = List.to_tuple(Map.get(png, :palette, []))
    alphas = Map.get(png, :trns, <<>>)

    for(<<index::size(^depth) <- row>>, into: <<>>, do: palette_pixel(palette, alphas, index))
    |> take_pixels(png.width)
  end

  defp palette_pixel(palette, alphas, index) do
    {r, g, b} = elem(palette, index)
    alpha = if index < byte_size(alphas), do: :binary.at(alphas, index), else: 255
    <<r, g, b, alpha>>
  end

  defp grey(value, top), do: div(value * 255, top)

  defp take_pixels(binary, width), do: binary_part(binary, 0, width * 4)

  defp key_alpha(%{trns: <<r::16, g::16, b::16>>, depth: 8}, {r, g, b}), do: 0
  defp key_alpha(%{trns: <<r, _, g, _, b, _>>, depth: 16}, {r, g, b}), do: 0
  defp key_alpha(%{trns: <<v::16>>, colour_type: 0, depth: depth}, v) when depth <= 8, do: 0
  defp key_alpha(%{trns: <<v, _>>, colour_type: 0, depth: 16}, v), do: 0
  defp key_alpha(_png, _pixel), do: 255
end
