defmodule Cauldron2D.GameMaker.Texture do
  @moduledoc """
  A texture page (a `TXTR` entry): one packed image that sprites, tilesets and fonts cut
  their pictures from through `Cauldron2D.GameMaker.Region`.

  `encoding` names how the page's bytes are stored: `:png`, `:qoi` (GameMaker's QOI
  variant, `Cauldron2D.GameMaker.Qoi`), or `:bz2_qoi` (that, compressed with bzip2).
  `bytes` is the page as stored. `decode/1` turns a page in any of the three into a
  `FrenchCurve.Raster`.
  """

  alias Cauldron2D.GameMaker.Bytes
  alias Cauldron2D.GameMaker.Bzip2
  alias Cauldron2D.GameMaker.Qoi
  alias FrenchCurve.Raster

  @enforce_keys [:encoding, :bytes]
  defstruct [:encoding, :bytes]

  @type encoding :: :png | :qoi | :bz2_qoi
  @type t :: %__MODULE__{encoding: encoding(), bytes: binary()}

  @png <<137, 80, 78, 71, 13, 10, 26, 10>>

  @doc """
  Every texture page in the `TXTR` chunk at `at`, `size` bytes long, in order. A PNG
  page ends at its `IEND`; a page in another encoding runs to the next page's bytes or
  the chunk's end.
  """
  @spec read_all(binary(), non_neg_integer(), non_neg_integer()) :: [t()]
  def read_all(data, at, size) do
    blobs = data |> Bytes.pointers(at) |> Enum.map(&blob(data, &1))
    ends = blobs |> Enum.sort() |> Enum.drop(1) |> Enum.concat([at + size])
    limits = blobs |> Enum.sort() |> Enum.zip(ends) |> Map.new()
    Enum.map(blobs, &stored(data, &1, Map.fetch!(limits, &1)))
  end

  @doc "The page as a raster."
  @spec decode(t()) :: {:ok, Raster.t()} | {:error, term()}
  def decode(%__MODULE__{encoding: :png, bytes: bytes}), do: Linocut.Png.decode(bytes)
  def decode(%__MODULE__{encoding: :qoi, bytes: bytes}), do: Qoi.decode(bytes)

  def decode(%__MODULE__{encoding: :bz2_qoi, bytes: bytes}) do
    with {:ok, qoi} <- bytes |> bzip2_stream() |> Bzip2.decompress(), do: Qoi.decode(qoi)
  end

  defp bzip2_stream(<<_header::binary-8, "BZh", _::binary>> = bytes),
    do: binary_part(bytes, 8, byte_size(bytes) - 8)

  defp bzip2_stream(<<_header::binary-12, rest::binary>>), do: rest

  defp blob(data, entry), do: data |> Bytes.u32s(entry, 7) |> Enum.find(&stored?(data, &1))

  defp stored?(data, at) when at > 0 and at + 8 <= byte_size(data),
    do: encoding(binary_part(data, at, 8)) != nil

  defp stored?(_data, _at), do: false

  defp encoding(<<@png>>), do: :png
  defp encoding(<<"fioq", _::binary>>), do: :qoi
  defp encoding(<<"2zoq", _::binary>>), do: :bz2_qoi
  defp encoding(_), do: nil

  defp stored(data, at, limit) do
    case encoding(binary_part(data, at, 8)) do
      :png -> %__MODULE__{encoding: :png, bytes: binary_part(data, at, png_size(data, at + 8, 8))}
      other -> %__MODULE__{encoding: other, bytes: binary_part(data, at, limit - at)}
    end
  end

  defp png_size(data, at, size) do
    <<length::32, type::binary-4>> = binary_part(data, at, 8)
    size = size + 12 + length

    if type == "IEND", do: size, else: png_size(data, at + 12 + length, size)
  end
end
