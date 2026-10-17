defmodule CauldronGPU.PNG do
  @moduledoc """
  RGBA pixels as a PNG file, for saving what `CauldronGPU.capture/2` returns.

      {:ok, frame} = CauldronGPU.capture(gpu)
      File.write!("frame.png", CauldronGPU.PNG.encode(frame))
  """

  @doc "PNG bytes for `%{width: w, height: h, pixels: rgba}`, rows from the top."
  @spec encode(%{width: pos_integer(), height: pos_integer(), pixels: binary()}) :: binary()
  def encode(%{width: width, height: height, pixels: pixels}) do
    stride = width * 4

    rows =
      for row <- 0..(height - 1),
          into: <<>>,
          do: <<0, binary_part(pixels, row * stride, stride)::binary>>

    IO.iodata_to_binary([
      <<137, 80, 78, 71, 13, 10, 26, 10>>,
      chunk("IHDR", <<width::32, height::32, 8, 6, 0, 0, 0>>),
      chunk("IDAT", :zlib.compress(rows)),
      chunk("IEND", <<>>)
    ])
  end

  defp chunk(type, data) do
    [<<byte_size(data)::32>>, type, data, <<:erlang.crc32([type, data])::32>>]
  end
end
