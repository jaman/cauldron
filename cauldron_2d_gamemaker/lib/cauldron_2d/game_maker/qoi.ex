defmodule Cauldron2D.GameMaker.Qoi do
  @moduledoc """
  GameMaker's variant of the QOI image format, as texture pages store it: a 12-byte
  header (`fioq`, width and height as 16-bit numbers, the data's length as a 32-bit
  number, all little-endian) and then the pixel operations.

      {:ok, raster} = Cauldron2D.GameMaker.Qoi.decode(bytes)
  """

  import Bitwise

  alias FrenchCurve.Raster

  @doc "The image in `bytes` as a raster, or `{:error, :not_qoi}`."
  @spec decode(binary()) :: {:ok, Raster.t()} | {:error, :not_qoi}
  def decode(<<"fioq", width::little-16, height::little-16, length::little-32, rest::binary>>)
      when byte_size(rest) >= length do
    pixels =
      rest
      |> binary_part(0, length)
      |> pixels(width * height, {0, 0, 0, 255}, :erlang.make_tuple(64, {0, 0, 0, 0}), [])

    {:ok, Raster.from_rgba(width, height, pixels)}
  end

  def decode(_bytes), do: {:error, :not_qoi}

  defp pixels(_data, 0, _pixel, _index, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp pixels(<<>>, left, {r, g, b, a}, _index, acc),
    do: pixels(<<>>, 0, nil, nil, [:binary.copy(<<r, g, b, a>>, left) | acc])

  defp pixels(<<0b00::2, slot::6, rest::binary>>, left, _pixel, index, acc),
    do: emit(rest, left, elem(index, slot), index, 1, acc)

  defp pixels(<<0b010::3, run::5, rest::binary>>, left, pixel, index, acc),
    do: emit(rest, left, pixel, index, run + 1, acc)

  defp pixels(<<0b011::3, high::5, low, rest::binary>>, left, pixel, index, acc),
    do: emit(rest, left, pixel, index, (high <<< 8 ||| low) + 33, acc)

  defp pixels(
         <<0b10::2, dr::signed-2, dg::signed-2, db::signed-2, rest::binary>>,
         left,
         pixel,
         index,
         acc
       ),
       do: emit(rest, left, shift(pixel, dr, dg, db, 0), index, 1, acc)

  defp pixels(
         <<0b110::3, dr::signed-5, dg::signed-4, db::signed-4, rest::binary>>,
         left,
         pixel,
         index,
         acc
       ),
       do: emit(rest, left, shift(pixel, dr, dg, db, 0), index, 1, acc)

  defp pixels(
         <<0b1110::4, dr::signed-5, dg::signed-5, db::signed-5, da::signed-5, rest::binary>>,
         left,
         pixel,
         index,
         acc
       ),
       do: emit(rest, left, shift(pixel, dr, dg, db, da), index, 1, acc)

  defp pixels(
         <<0b1111::4, has_r::1, has_g::1, has_b::1, has_a::1, rest::binary>>,
         left,
         {r, g, b, a},
         index,
         acc
       ) do
    {r, rest} = channel(has_r, r, rest)
    {g, rest} = channel(has_g, g, rest)
    {b, rest} = channel(has_b, b, rest)
    {a, rest} = channel(has_a, a, rest)
    emit(rest, left, {r, g, b, a}, index, 1, acc)
  end

  defp channel(1, _old, <<value, rest::binary>>), do: {value, rest}
  defp channel(0, old, rest), do: {old, rest}

  defp shift({r, g, b, a}, dr, dg, db, da),
    do: {r + dr &&& 255, g + dg &&& 255, b + db &&& 255, a + da &&& 255}

  defp emit(rest, left, {r, g, b, a} = pixel, index, count, acc) do
    count = min(count, left)
    index = put_elem(index, bxor(bxor(r, g), bxor(b, a)) &&& 63, pixel)
    pixels(rest, left - count, pixel, index, [:binary.copy(<<r, g, b, a>>, count) | acc])
  end
end
