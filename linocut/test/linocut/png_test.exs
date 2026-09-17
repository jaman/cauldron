defmodule Linocut.PngTest do
  use ExUnit.Case, async: true

  alias FrenchCurve.Raster
  alias Linocut.Png

  @signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  defp chunk(type, data),
    do: <<byte_size(data)::32>> <> type <> data <> <<:erlang.crc32(type <> data)::32>>

  defp png(width, height, colour_type, depth, scanlines, extra \\ []) do
    deflated = :zlib.compress(IO.iodata_to_binary(scanlines))

    @signature <>
      chunk("IHDR", <<width::32, height::32, depth, colour_type, 0, 0, 0>>) <>
      IO.iodata_to_binary(extra) <> chunk("IDAT", deflated) <> chunk("IEND", <<>>)
  end

  test "an RGBA png written by french_curve reads back pixel for pixel" do
    raster =
      Raster.new(3, 2)
      |> Raster.put_pixel(0, 0, {255, 0, 0, 255})
      |> Raster.put_pixel(2, 1, {0, 0, 255, 128})

    bytes = FrenchCurve.Png.encode(3, 2, Raster.to_rgba_binary(raster))
    assert {:ok, read} = Png.decode(bytes)
    assert Raster.dimensions(read) == {3, 2}
    assert Raster.get_pixel(read, 0, 0) == {255, 0, 0, 255}
    assert Raster.get_pixel(read, 2, 1) == {0, 0, 255, 128}
    assert Raster.get_pixel(read, 1, 0) == {0, 0, 0, 0}
  end

  test "rgb, grey and grey-with-alpha pixels are widened to rgba" do
    assert {:ok, rgb} = Png.decode(png(2, 1, 2, 8, [<<0, 10, 20, 30, 40, 50, 60>>]))
    assert Raster.get_pixel(rgb, 1, 0) == {40, 50, 60, 255}

    assert {:ok, grey} = Png.decode(png(2, 1, 0, 8, [<<0, 7, 200>>]))
    assert Raster.get_pixel(grey, 1, 0) == {200, 200, 200, 255}

    assert {:ok, grey_alpha} = Png.decode(png(1, 1, 4, 8, [<<0, 9, 99>>]))
    assert Raster.get_pixel(grey_alpha, 0, 0) == {9, 9, 9, 99}
  end

  test "a palette png reads its colours, with tRNS alpha where given" do
    plte = chunk("PLTE", <<255, 0, 0, 0, 255, 0, 0, 0, 255>>)
    trns = chunk("tRNS", <<255, 128>>)
    assert {:ok, raster} = Png.decode(png(3, 1, 3, 8, [<<0, 0, 1, 2>>], [plte, trns]))
    assert Raster.get_pixel(raster, 0, 0) == {255, 0, 0, 255}
    assert Raster.get_pixel(raster, 1, 0) == {0, 255, 0, 128}
    assert Raster.get_pixel(raster, 2, 0) == {0, 0, 255, 255}

    assert {:ok, packed} = Png.decode(png(4, 1, 3, 2, [<<0, 0b00011010>>], [plte]))
    assert Raster.get_pixel(packed, 3, 0) == {0, 0, 255, 255}
    assert Raster.get_pixel(packed, 1, 0) == {0, 255, 0, 255}
  end

  test "every filter type is undone" do
    sub = [<<1, 10, 20, 30, 255, 5, 5, 5, 0>>]
    assert {:ok, r} = Png.decode(png(2, 1, 6, 8, sub))
    assert Raster.get_pixel(r, 1, 0) == {15, 25, 35, 255}

    up = [<<0, 10, 20, 30, 255>>, <<2, 1, 1, 1, 0>>]
    assert {:ok, r} = Png.decode(png(1, 2, 6, 8, up))
    assert Raster.get_pixel(r, 0, 1) == {11, 21, 31, 255}

    average = [<<0, 10, 20, 30, 255>>, <<3, 5, 10, 15, 0>>]
    assert {:ok, r} = Png.decode(png(1, 2, 6, 8, average))
    assert Raster.get_pixel(r, 0, 1) == {10, 20, 30, 127}

    paeth = [<<0, 10, 20, 30, 255, 50, 60, 70, 255>>, <<4, 0, 0, 0, 0, 1, 2, 3, 0>>]
    assert {:ok, r} = Png.decode(png(2, 2, 6, 8, paeth))
    assert Raster.get_pixel(r, 0, 1) == {10, 20, 30, 255}
    assert Raster.get_pixel(r, 1, 1) == {51, 62, 73, 255}
  end

  test "sixteen-bit channels keep their high byte" do
    assert {:ok, r} = Png.decode(png(1, 1, 2, 16, [<<0, 255, 255, 128, 0, 1, 2>>]))
    assert Raster.get_pixel(r, 0, 0) == {255, 128, 1, 255}
  end

  test "what is not a png, or is interlaced, is refused" do
    assert {:error, :not_png} = Png.decode("hello")

    interlaced =
      @signature <>
        chunk("IHDR", <<1::32, 1::32, 8, 6, 0, 0, 1>>) <>
        chunk("IDAT", :zlib.compress(<<0, 0, 0, 0, 0>>)) <> chunk("IEND", <<>>)

    assert {:error, :interlaced} = Png.decode(interlaced)
  end
end
