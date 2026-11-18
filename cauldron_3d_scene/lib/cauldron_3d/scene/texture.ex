defmodule Cauldron3D.Scene.Texture do
  @moduledoc """
  A picture to upload. `pixels` is `width * height` pixels, rows from the top: four bytes
  RGBA for `:srgb` (colour pictures) and `:linear` (data such as roughness), eight bytes
  (four little-endian half floats) for `:rgba16f`, and one byte for `:r8` (a single data channel,
  read as the red channel; only the browser renderer supports it).

  A texture may instead hold a PNG or JPEG file as it is (`encoding` `:png` or `:jpeg`,
  the file in `pixels`), made with `encoded/2`. A browser decodes it itself; the native
  renderer decodes it to RGBA before uploading (`CauldronGPU.decode/1`).

      Cauldron3D.Scene.Texture.checker(64, 8, {255, 255, 255, 255}, {40, 40, 40, 255})
      {:ok, texture} = Cauldron3D.Scene.Texture.encoded(File.read!("bricks.jpg"))
  """

  @type format :: :srgb | :linear | :rgba16f | :r8
  @type encoding :: :raw | :png | :jpeg
  @type t :: %__MODULE__{
          width: pos_integer(),
          height: pos_integer(),
          pixels: binary(),
          format: format(),
          filter: :nearest | :linear,
          wrap: :repeat | :clamp,
          mipmaps: boolean(),
          encoding: encoding()
        }

  @enforce_keys [:width, :height, :pixels]
  defstruct [
    :width,
    :height,
    :pixels,
    format: :srgb,
    filter: :linear,
    wrap: :repeat,
    mipmaps: true,
    encoding: :raw
  ]

  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>
  @jpeg_frames [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF]

  @doc "A `size`×`size` checkerboard of `squares` squares a side, in two RGBA colours."
  @spec checker(pos_integer(), pos_integer(), tuple(), tuple(), keyword()) :: t()
  def checker(size, squares, {r1, g1, b1, a1}, {r2, g2, b2, a2}, fields \\ []) do
    square = max(div(size, squares), 1)

    pixels =
      for y <- 0..(size - 1), x <- 0..(size - 1), into: <<>> do
        if rem(div(x, square) + div(y, square), 2) == 0,
          do: <<r1, g1, b1, a1>>,
          else: <<r2, g2, b2, a2>>
      end

    struct!(__MODULE__, [width: size, height: size, pixels: pixels] ++ fields)
  end

  @doc """
  A texture holding the PNG or JPEG file `bytes`, its size read from the file's header.
  `fields` sets the other fields (`:format`, `:filter`, `:wrap`, `:mipmaps`).
  `{:error, :unknown_image}` for a file that is neither.
  """
  @spec encoded(binary(), keyword()) :: {:ok, t()} | {:error, :unknown_image}
  def encoded(bytes, fields \\ []) do
    with {:ok, encoding, width, height} <- header(bytes) do
      {:ok,
       struct!(
         __MODULE__,
         [width: width, height: height, pixels: bytes, encoding: encoding] ++ fields
       )}
    end
  end

  @doc "Whether `texture` holds an encoded file rather than pixels."
  @spec encoded?(t()) :: boolean()
  def encoded?(%__MODULE__{encoding: encoding}), do: encoding != :raw

  defp header(<<@png_signature, _length::32, "IHDR", width::32, height::32, _rest::binary>>),
    do: {:ok, :png, width, height}

  defp header(<<0xFF, 0xD8, rest::binary>>), do: jpeg_size(rest)
  defp header(_bytes), do: {:error, :unknown_image}

  defp jpeg_size(<<0xFF, marker, _length::16, _precision, height::16, width::16, _::binary>>)
       when marker in @jpeg_frames,
       do: {:ok, :jpeg, width, height}

  defp jpeg_size(<<0xFF, 0xFF, rest::binary>>), do: jpeg_size(<<0xFF, rest::binary>>)

  defp jpeg_size(<<0xFF, marker, rest::binary>>) when marker in 0xD0..0xD9,
    do: jpeg_size(rest)

  defp jpeg_size(<<0xFF, _marker, length::16, rest::binary>>) when byte_size(rest) >= length - 2,
    do: rest |> binary_part(length - 2, byte_size(rest) - length + 2) |> jpeg_size()

  defp jpeg_size(_bytes), do: {:error, :unknown_image}
end
