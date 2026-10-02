defmodule Cauldron2D.Blend do
  @moduledoc """
  Source-over compositing of two equal-sized RGBA rectangles.

      Cauldron2D.Blend.over(beneath, above)

  Both binaries are four bytes per pixel and must be the same length. The result is the
  same length: `above` laid over `beneath`, premultiplied by `above`'s alpha.

  `available?/0` says whether the C library loaded. Where it did not the same picture is
  produced in Elixir, some fifty times slower.
  """

  @on_load :load_nif

  @doc false
  def load_nif do
    :cauldron_2d
    |> :code.priv_dir()
    |> Path.join("blend_nif")
    |> to_charlist()
    |> :erlang.load_nif(0)
    |> case do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end

  @doc "Whether the library is loaded and compositing is done in C."
  @spec available?() :: boolean()
  def available?, do: false

  @doc "`above` laid over `beneath`, both RGBA of the same length."
  @spec over(binary(), binary()) :: binary()
  def over(beneath, above) when byte_size(beneath) == byte_size(above),
    do: elixir_over(beneath, above, [])

  @doc false
  @spec elixir_over(binary(), binary(), iodata()) :: binary()
  def elixir_over(<<>>, <<>>, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  def elixir_over(<<br, bg, bb, ba, beneath::binary>>, <<_r, _g, _b, 0, above::binary>>, acc),
    do: elixir_over(beneath, above, [<<br, bg, bb, ba>> | acc])

  def elixir_over(<<_r, _g, _b, _a, beneath::binary>>, <<tr, tg, tb, 255, above::binary>>, acc),
    do: elixir_over(beneath, above, [<<tr, tg, tb, 255>> | acc])

  def elixir_over(<<br, bg, bb, ba, beneath::binary>>, <<tr, tg, tb, ta, above::binary>>, acc) do
    top_alpha = ta / 255
    base_alpha = ba / 255 * (1 - top_alpha)
    alpha = top_alpha + base_alpha

    pixel =
      <<mix(tr, br, top_alpha, base_alpha, alpha), mix(tg, bg, top_alpha, base_alpha, alpha),
        mix(tb, bb, top_alpha, base_alpha, alpha), round(alpha * 255)>>

    elixir_over(beneath, above, [pixel | acc])
  end

  defp mix(above, beneath, top_alpha, base_alpha, alpha),
    do: round((above * top_alpha + beneath * base_alpha) / alpha)
end
