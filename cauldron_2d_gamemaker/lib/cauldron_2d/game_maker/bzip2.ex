defmodule Cauldron2D.GameMaker.Bzip2 do
  @moduledoc """
  A bzip2 decompressor, for texture pages stored as `:bz2_qoi`.

      {:ok, bytes} = Cauldron2D.GameMaker.Bzip2.decompress(compressed)

  `compressed` starts with bzip2's own `BZh` header. Bytes after the end-of-stream
  marker are ignored. Block checksums are not verified.
  """

  import Bitwise

  @block_magic 0x314159265359
  @end_magic 0x177245385090
  @group_size 50

  @doc "The bytes `compressed` holds, or `{:error, reason}` when it is not a bzip2 stream."
  @spec decompress(binary()) :: {:ok, binary()} | {:error, term()}
  def decompress(<<"BZh", level, rest::binary>>) when level in ?1..?9 do
    {:ok, blocks(rest, 0, []) |> IO.iodata_to_binary()}
  catch
    {:bzip2, reason} -> {:error, reason}
  end

  def decompress(_bytes), do: {:error, :not_bzip2}

  defp blocks(bin, pos, acc) do
    case bits(bin, pos, 48) do
      @block_magic -> block(bin, pos + 48, acc)
      @end_magic -> Enum.reverse(acc)
      _other -> throw({:bzip2, :bad_block_magic})
    end
  end

  defp block(bin, pos, acc) do
    pos = pos + 32

    if bits(bin, pos, 1) == 1, do: throw({:bzip2, :randomised_block})

    orig_ptr = bits(bin, pos + 1, 24)
    {symbols, pos} = used_symbols(bin, pos + 25)
    groups = bits(bin, pos, 3)
    selector_count = bits(bin, pos + 3, 15)
    {selectors, pos} = selectors(bin, pos + 18, groups, selector_count)
    alphabet = length(symbols) + 2
    {tables, pos} = tables(bin, pos, groups, alphabet)
    {mtf_output, pos} = decode_symbols(bin, pos, selectors, tables, symbols, alphabet - 1)
    bytes = mtf_output |> IO.iodata_to_binary() |> inverse_bwt(orig_ptr) |> unrle()
    blocks(bin, pos, [bytes | acc])
  end

  defp used_symbols(bin, pos) do
    map = bits(bin, pos, 16)

    {ranges, pos} =
      Enum.reduce(0..15, {[], pos + 16}, fn range, {acc, at} ->
        if (map >>> (15 - range) &&& 1) == 1,
          do: {[{range, bits(bin, at, 16)} | acc], at + 16},
          else: {acc, at}
      end)

    symbols =
      for {range, used} <- Enum.reverse(ranges),
          bit <- 0..15,
          (used >>> (15 - bit) &&& 1) == 1,
          do: range * 16 + bit

    {symbols, pos}
  end

  defp selectors(bin, pos, groups, count) do
    {indices, pos} =
      Enum.reduce(1..count//1, {[], pos}, fn _n, {acc, at} ->
        {index, at} = unary(bin, at, 0)
        {[index | acc], at}
      end)

    {unmtf_selectors(Enum.reverse(indices), Enum.to_list(0..(groups - 1)), []), pos}
  end

  defp unary(bin, pos, count) do
    if bits(bin, pos, 1) == 1, do: unary(bin, pos + 1, count + 1), else: {count, pos + 1}
  end

  defp unmtf_selectors([], _order, acc), do: acc |> Enum.reverse() |> List.to_tuple()

  defp unmtf_selectors([index | rest], order, acc) do
    {value, order} = List.pop_at(order, index)
    unmtf_selectors(rest, [value | order], [value | acc])
  end

  defp tables(bin, pos, groups, alphabet) do
    {tables, pos} =
      Enum.reduce(1..groups, {[], pos}, fn _group, {acc, at} ->
        {lengths, at} = code_lengths(bin, at + 5, bits(bin, at, 5), alphabet, [])
        {[decoder(lengths) | acc], at}
      end)

    {tables |> Enum.reverse() |> List.to_tuple(), pos}
  end

  defp code_lengths(_bin, pos, _length, 0, acc), do: {Enum.reverse(acc), pos}

  defp code_lengths(bin, pos, length, left, acc) do
    case bits(bin, pos, 2) do
      0b10 -> code_lengths(bin, pos + 2, length + 1, left, acc)
      0b11 -> code_lengths(bin, pos + 2, length - 1, left, acc)
      _ends -> code_lengths(bin, pos + 1, length, left - 1, [length | acc])
    end
  end

  defp decoder(lengths) do
    sorted =
      lengths
      |> Enum.with_index()
      |> Enum.sort()

    {min, max} = Enum.min_max(lengths)

    {limits, bases, _code} =
      Enum.reduce(min..max, {%{}, %{}, 0}, fn length, {limits, bases, code} ->
        count = Enum.count(lengths, &(&1 == length))
        first_rank = Enum.count(lengths, &(&1 < length))
        limits = Map.put(limits, length, code + count - 1)
        bases = Map.put(bases, length, code - first_rank)
        {limits, bases, (code + count) <<< 1}
      end)

    %{
      min: min,
      max: max,
      limits: List.to_tuple(for length <- 0..max, do: Map.get(limits, length, -1)),
      bases: List.to_tuple(for length <- 0..max, do: Map.get(bases, length, 0)),
      symbols: sorted |> Enum.map(&elem(&1, 1)) |> List.to_tuple()
    }
  end

  defp decode_symbols(bin, pos, selectors, tables, symbols, end_of_block) do
    state = %{
      bin: bin,
      selectors: selectors,
      tables: tables,
      end_of_block: end_of_block,
      mtf: symbols
    }

    symbols_loop(state, pos, 0, 0, 0, [])
  end

  defp symbols_loop(state, pos, decoded, run, run_bit, acc) do
    table = elem(state.tables, elem(state.selectors, div(decoded, @group_size)))
    {symbol, pos} = huffman(state.bin, pos, table)

    cond do
      symbol <= 1 ->
        symbols_loop(state, pos, decoded + 1, run + ((symbol + 1) <<< run_bit), run_bit + 1, acc)

      symbol == state.end_of_block ->
        {Enum.reverse(flush_run(acc, state.mtf, run)), pos}

      true ->
        acc = flush_run(acc, state.mtf, run)
        {value, rest} = List.pop_at(state.mtf, symbol - 1)
        symbols_loop(%{state | mtf: [value | rest]}, pos, decoded + 1, 0, 0, [value | acc])
    end
  end

  defp flush_run(acc, _mtf, 0), do: acc
  defp flush_run(acc, [front | _], run), do: [:binary.copy(<<front>>, run) | acc]

  defp huffman(bin, pos, table) do
    code = bits(bin, pos, table.min)
    huffman(bin, pos + table.min, table, table.min, code)
  end

  defp huffman(bin, pos, table, length, code) do
    cond do
      code <= elem(table.limits, length) ->
        {elem(table.symbols, code - elem(table.bases, length)), pos}

      length < table.max ->
        huffman(bin, pos + 1, table, length + 1, code <<< 1 ||| bits(bin, pos, 1))

      true ->
        throw({:bzip2, :bad_huffman_code})
    end
  end

  defp inverse_bwt(block, orig_ptr) do
    next = block |> starts() |> next_table(block)
    walk(block, next, :atomics.get(next, orig_ptr + 1), byte_size(block), [])
  end

  defp starts(block) do
    counts = :atomics.new(256, signed: false)
    for <<byte <- block>>, do: :atomics.add(counts, byte + 1, 1)
    totals = for byte <- 1..256, do: :atomics.get(counts, byte)
    starts = :atomics.new(256, signed: false)

    [0 | totals]
    |> Enum.scan(&+/2)
    |> Enum.take(256)
    |> Enum.with_index(1)
    |> Enum.each(fn {start, byte} -> :atomics.put(starts, byte, start) end)

    starts
  end

  defp next_table(starts, block) do
    next = :atomics.new(max(byte_size(block), 1), signed: false)

    block
    |> :binary.bin_to_list()
    |> Enum.with_index()
    |> Enum.each(fn {byte, index} ->
      :atomics.put(next, :atomics.add_get(starts, byte + 1, 1), index)
    end)

    next
  end

  defp walk(_block, _next, _at, 0, acc), do: acc |> Enum.reverse() |> :erlang.list_to_binary()

  defp walk(block, next, at, left, acc),
    do: walk(block, next, :atomics.get(next, at + 1), left - 1, [:binary.at(block, at) | acc])

  defp unrle(bytes), do: unrle(bytes, nil, 0, []) |> Enum.reverse() |> IO.iodata_to_binary()

  defp unrle(<<count, rest::binary>>, last, 4, acc),
    do: unrle(rest, last, 0, [:binary.copy(<<last>>, count) | acc])

  defp unrle(<<byte, rest::binary>>, byte, seen, acc),
    do: unrle(rest, byte, seen + 1, [byte | acc])

  defp unrle(<<byte, rest::binary>>, _last, _seen, acc), do: unrle(rest, byte, 1, [byte | acc])
  defp unrle(<<>>, _last, _seen, acc), do: acc

  defp bits(bin, pos, count) do
    case bin do
      <<_::bitstring-size(pos), value::size(count), _::bitstring>> -> value
      _short -> throw({:bzip2, :truncated})
    end
  end
end
