defmodule Cauldron3D.Frame.Pixels do
  @moduledoc """
  Whole runs of RGBA pixels, four bytes each.

      Cauldron3D.Frame.Pixels.lay(under, above)
      Cauldron3D.Frame.Pixels.through(pixels, table)

  `available?/0` says whether the C library loaded. Where it did not the same bytes are
  made in Elixir.
  """

  @on_load :load_nif

  @doc false
  def load_nif do
    "pixels_nif"
    |> Cauldron3D.Native.path()
    |> :erlang.load_nif(0)
    |> then(&:persistent_term.put({__MODULE__, :native}, &1 == :ok))
  end

  @doc "Whether the library is loaded and pixels are worked in C."
  @spec available?() :: boolean()
  def available?, do: :persistent_term.get({__MODULE__, :native}, false)

  @doc """
  `above` laid over `under`, both RGBA of the same length: where `above`'s alpha is 255
  its colour, where 0 `under`'s pixel, and otherwise each channel
  `div(above * a + under * (255 - a), 255)` with `under`'s alpha kept.
  """
  @spec lay(binary(), binary()) :: binary()
  def lay(under, above) when byte_size(under) == byte_size(above) do
    for {<<ur, ug, ub, ua>>, <<r, g, b, a>>} <- Enum.zip(words(under), words(above)),
        into: <<>> do
      case a do
        255 ->
          <<r, g, b, 255>>

        0 ->
          <<ur, ug, ub, ua>>

        _ ->
          <<div(r * a + ur * (255 - a), 255), div(g * a + ug * (255 - a), 255),
            div(b * a + ub * (255 - a), 255), ua>>
      end
    end
  end

  @doc "`pixels` with each red, green and blue byte `v` replaced by byte `v` of the 256-byte `table`; alpha kept."
  @spec through(binary(), binary()) :: binary()
  def through(pixels, table) when byte_size(table) == 256 do
    for <<r, g, b, a <- pixels>>,
      into: <<>>,
      do: <<:binary.at(table, r), :binary.at(table, g), :binary.at(table, b), a>>
  end

  defp words(binary), do: for(<<word::binary-4 <- binary>>, do: word)
end
