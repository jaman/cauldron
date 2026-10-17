defmodule Cauldron2D.GameMaker.Bytes do
  @moduledoc """
  Values read at absolute offsets of a GameMaker data file.

  Every number is little-endian. A string field holds the offset of the string's first
  byte inside the `STRG` chunk, with its length in the four bytes before it; `0` is no
  string. A pointer list is a count followed by that many absolute offsets, one per
  item; a simple list is a count followed by the items themselves.
  """

  @doc "The unsigned 32-bit number at `at`."
  @spec u32(binary(), non_neg_integer()) :: non_neg_integer()
  def u32(data, at) do
    <<value::little-32>> = binary_part(data, at, 4)
    value
  end

  @doc "The byte at `at`."
  @spec u8(binary(), non_neg_integer()) :: byte()
  def u8(data, at), do: :binary.at(data, at)

  @doc "The unsigned 16-bit number at `at`."
  @spec u16(binary(), non_neg_integer()) :: non_neg_integer()
  def u16(data, at) do
    <<value::little-16>> = binary_part(data, at, 2)
    value
  end

  @doc "The signed 32-bit number at `at`."
  @spec i32(binary(), non_neg_integer()) :: integer()
  def i32(data, at) do
    <<value::little-signed-32>> = binary_part(data, at, 4)
    value
  end

  @doc "The string a string field holds, `nil` for `0`."
  @spec string(binary(), non_neg_integer()) :: String.t() | nil
  def string(_data, 0), do: nil
  def string(data, pointer), do: binary_part(data, pointer, u32(data, pointer - 4))

  @doc "The string whose field is at `at`."
  @spec string_at(binary(), non_neg_integer()) :: String.t() | nil
  def string_at(data, at), do: string(data, u32(data, at))

  @doc "The item offsets of the pointer list at `at`."
  @spec pointers(binary(), non_neg_integer()) :: [non_neg_integer()]
  def pointers(data, at) do
    count = u32(data, at)
    for <<pointer::little-32 <- binary_part(data, at + 4, count * 4)>>, do: pointer
  end

  @doc "The `count` unsigned 32-bit numbers starting at `at`."
  @spec u32s(binary(), non_neg_integer(), non_neg_integer()) :: [non_neg_integer()]
  def u32s(data, at, count) do
    for <<value::little-32 <- binary_part(data, at, count * 4)>>, do: value
  end

  @doc """
  A 32-bit float, read from its bits. Infinities and NaN, which Erlang has no float for,
  are `:infinity`, `:neg_infinity` and `:nan`.
  """
  @spec float(<<_::32>>) :: float() | :infinity | :neg_infinity | :nan
  def float(<<value::little-float-32>>), do: value
  def float(<<0, 0, 128, 127>>), do: :infinity
  def float(<<0, 0, 128, 255>>), do: :neg_infinity
  def float(<<_::binary-4>>), do: :nan

  @doc "The 32-bit float at `at`."
  @spec f32(binary(), non_neg_integer()) :: float() | :infinity | :neg_infinity | :nan
  def f32(data, at), do: float(binary_part(data, at, 4))

  @doc "A colour field as `{r, g, b, a}`: GameMaker stores the red byte first."
  @spec colour(non_neg_integer()) :: {byte(), byte(), byte(), byte()}
  def colour(value) do
    <<red, green, blue, alpha>> = <<value::little-32>>
    {red, green, blue, alpha}
  end
end
