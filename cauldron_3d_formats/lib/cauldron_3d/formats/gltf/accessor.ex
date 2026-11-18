defmodule Cauldron3D.Formats.Gltf.Accessor do
  @moduledoc """
  Reads a glTF accessor out of the document's buffers as one packed binary, honouring the
  buffer view's offset and stride, normalized integer types and sparse substitutions.

    * `floats/3` — every component as a little-endian 32-bit float, elements back to back
      (`{width, binary}`, `width` components an element); normalized integers become
      `0.0..1.0` or `-1.0..1.0`, other integers their value
    * `integers/3` — every component as a little-endian unsigned 32-bit integer, for
      indices

      {3, positions} = Cauldron3D.Formats.Gltf.Accessor.floats(json, buffers, 0)
  """

  @component %{
    5120 => {:signed, 8},
    5121 => {:unsigned, 8},
    5122 => {:signed, 16},
    5123 => {:unsigned, 16},
    5125 => {:unsigned, 32},
    5126 => {:float, 32}
  }

  @width %{
    "SCALAR" => 1,
    "VEC2" => 2,
    "VEC3" => 3,
    "VEC4" => 4,
    "MAT2" => 4,
    "MAT3" => 9,
    "MAT4" => 16
  }

  @doc "Accessor `index` as packed 32-bit floats, with the number of components an element."
  @spec floats(map(), [binary()], non_neg_integer()) :: {pos_integer(), binary()}
  def floats(json, buffers, index) do
    accessor = Enum.at(json["accessors"], index)
    {width, type, raw} = raw(json, buffers, accessor)
    {width, convert(raw, type, Map.get(accessor, "normalized", false))}
  end

  @doc "Accessor `index` as packed unsigned 32-bit integers."
  @spec integers(map(), [binary()], non_neg_integer()) :: binary()
  def integers(json, buffers, index) do
    {_width, type, raw} = raw(json, buffers, Enum.at(json["accessors"], index))
    widen(raw, type)
  end

  defp raw(json, buffers, accessor) do
    width = Map.fetch!(@width, accessor["type"])
    type = Map.fetch!(@component, accessor["componentType"])
    size = width * div(elem(type, 1), 8)
    count = accessor["count"]

    packed =
      case accessor["bufferView"] do
        nil -> :binary.copy(<<0>>, size * count)
        view -> packed(json, buffers, view, Map.get(accessor, "byteOffset", 0), size, count)
      end

    {width, type, sparse(packed, json, buffers, accessor, size)}
  end

  defp packed(json, buffers, view_index, offset, size, count) do
    view = Enum.at(json["bufferViews"], view_index)
    buffer = Enum.at(buffers, view["buffer"])
    start = Map.get(view, "byteOffset", 0) + offset

    case Map.get(view, "byteStride") do
      stride when is_integer(stride) and stride != size ->
        for index <- 0..(count - 1)//1,
            into: <<>>,
            do: binary_part(buffer, start + index * stride, size)

      _tight ->
        binary_part(buffer, start, size * count)
    end
  end

  defp sparse(packed, json, buffers, %{"sparse" => sparse}, size) do
    count = sparse["count"]
    index_type = Map.fetch!(@component, sparse["indices"]["componentType"])
    index_offset = Map.get(sparse["indices"], "byteOffset", 0)
    value_offset = Map.get(sparse["values"], "byteOffset", 0)

    indices =
      json
      |> packed(
        buffers,
        sparse["indices"]["bufferView"],
        index_offset,
        div(elem(index_type, 1), 8),
        count
      )
      |> widen(index_type)
      |> then(&for(<<index::little-unsigned-32 <- &1>>, do: index))

    values =
      json
      |> packed(buffers, sparse["values"]["bufferView"], value_offset, size, count)
      |> then(&for(<<value::binary-size(^size) <- &1>>, do: value))

    replaced = Map.new(Enum.zip(indices, values))
    elements = for <<element::binary-size(^size) <- packed>>, do: element

    for {element, index} <- Enum.with_index(elements),
        into: <<>>,
        do: Map.get(replaced, index, element)
  end

  defp sparse(packed, _json, _buffers, _accessor, _size), do: packed

  defp convert(raw, {:float, 32}, _normalized?), do: raw

  defp convert(raw, {:unsigned, 8}, true),
    do: for(<<v <- raw>>, into: <<>>, do: <<v / 255::little-float-32>>)

  defp convert(raw, {:unsigned, 16}, true),
    do: for(<<v::little-16 <- raw>>, into: <<>>, do: <<v / 65_535::little-float-32>>)

  defp convert(raw, {:signed, 8}, true),
    do: for(<<v::signed <- raw>>, into: <<>>, do: <<max(v / 127, -1.0)::little-float-32>>)

  defp convert(raw, {:signed, 16}, true),
    do:
      for(<<v::little-signed-16 <- raw>>,
        into: <<>>,
        do: <<max(v / 32_767, -1.0)::little-float-32>>
      )

  defp convert(raw, {:unsigned, _bits} = type, _normalized?),
    do:
      for(<<v::little-unsigned-32 <- widen(raw, type)>>,
        into: <<>>,
        do: <<v / 1::little-float-32>>
      )

  defp convert(raw, type, _normalized?),
    do:
      for(<<v::little-signed-32 <- widen(raw, type)>>, into: <<>>, do: <<v / 1::little-float-32>>)

  defp widen(raw, {:unsigned, 32}), do: raw

  defp widen(raw, {:unsigned, 16}),
    do: for(<<v::little-16 <- raw>>, into: <<>>, do: <<v::little-32>>)

  defp widen(raw, {:unsigned, 8}), do: for(<<v <- raw>>, into: <<>>, do: <<v::little-32>>)

  defp widen(raw, {:signed, 16}),
    do: for(<<v::little-signed-16 <- raw>>, into: <<>>, do: <<v::little-signed-32>>)

  defp widen(raw, {:signed, 8}),
    do: for(<<v::signed <- raw>>, into: <<>>, do: <<v::little-signed-32>>)
end
