defmodule Cauldron2D.GameMaker.Chunks do
  @moduledoc """
  The chunks of a GameMaker data file: a `FORM` holding four-letter named chunks, each
  a length and its bytes.

      {:ok, chunks} = Cauldron2D.GameMaker.Chunks.index(bytes)
      {offset, size} = chunks["SPRT"]

  Offsets are absolute and point past the chunk's eight-byte header.
  """

  @type t :: %{String.t() => {non_neg_integer(), non_neg_integer()}}

  @doc "Every chunk's offset and size, by name."
  @spec index(binary()) :: {:ok, t()} | {:error, :not_a_data_file}
  def index(<<"FORM", size::little-32, body::binary>>) when byte_size(body) >= size,
    do: {:ok, walk(binary_part(body, 0, size), 16, %{})}

  def index(_bytes), do: {:error, :not_a_data_file}

  @doc "Whether the file has a chunk called `name` with anything in it."
  @spec filled?(t(), String.t()) :: boolean()
  def filled?(chunks, name), do: match?({_, size} when size > 0, Map.get(chunks, name))

  defp walk(<<name::binary-4, size::little-32, _::binary-size(size), rest::binary>>, at, found),
    do: walk(rest, at + 8 + size, Map.put(found, name, {at, size}))

  defp walk(_rest, _at, found), do: found
end
