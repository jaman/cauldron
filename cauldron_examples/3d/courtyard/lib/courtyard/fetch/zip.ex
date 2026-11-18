defmodule Courtyard.Fetch.Zip do
  @moduledoc """
  Single files out of a remote zip archive, read over byte ranges: the archive's central
  directory (`entries/1`), then one entry's local header and data (`extract/2`), inflated
  and checked against the CRC-32 the directory records.

      {:ok, entries} = Courtyard.Fetch.Zip.entries(directory_bytes)
      {:ok, bytes} = Courtyard.Fetch.Zip.extract(location, Map.fetch!(entries, "a/b.txt"))
  """

  alias Courtyard.Fetch.Http

  @type entry :: %{
          name: String.t(),
          method: 0 | 8,
          crc: non_neg_integer(),
          compressed: non_neg_integer(),
          size: non_neg_integer(),
          offset: non_neg_integer()
        }

  @doc "The entries a central directory lists, by name."
  @spec entries(binary()) :: {:ok, %{String.t() => entry()}} | {:error, term()}
  def entries(directory), do: listed(directory, %{})

  @doc "Entry `entry` of the archive at `location`, inflated and checked."
  @spec extract(charlist(), entry()) :: {:ok, binary()} | {:error, term()}
  def extract(location, entry) do
    with {:ok,
          <<0x50, 0x4B, 3, 4, _::binary-size(22), name_length::little-16,
            extra_length::little-16>>} <-
           Http.range(location, entry.offset, entry.offset + 29),
         start = entry.offset + 30 + name_length + extra_length,
         {:ok, data} <- Http.range(location, start, start + entry.compressed - 1),
         bytes = inflated(data, entry.method),
         true <- :erlang.crc32(bytes) == entry.crc || {:error, {:crc, entry.name}} do
      {:ok, bytes}
    else
      {:ok, _other} -> {:error, {:bad_local_header, entry.name}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp listed(
         <<0x50, 0x4B, 1, 2, _made::16, _needed::16, _flags::16, method::little-16, _time::16,
           _date::16, crc::little-32, compressed::little-32, size::little-32,
           name_length::little-16, extra_length::little-16, comment_length::little-16, _disk::16,
           _internal::16, _external::32, offset::little-32, name::binary-size(name_length),
           _extra::binary-size(extra_length), _comment::binary-size(comment_length),
           rest::binary>>,
         entries
       ) do
    entry = %{
      name: name,
      method: method,
      crc: crc,
      compressed: compressed,
      size: size,
      offset: offset
    }

    listed(rest, Map.put(entries, name, entry))
  end

  defp listed(<<>>, entries), do: {:ok, entries}
  defp listed(_rest, _entries), do: {:error, :bad_central_directory}

  defp inflated(data, 0), do: data

  defp inflated(data, 8) do
    stream = :zlib.open()
    :ok = :zlib.inflateInit(stream, -15)
    bytes = stream |> :zlib.inflate(data) |> IO.iodata_to_binary()
    :zlib.close(stream)
    bytes
  end
end
