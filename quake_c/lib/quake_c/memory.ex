defmodule QuakeC.Memory do
  @moduledoc """
  A QuakeC program's words: a value per index from 0. A word never written is `0`. Values
  are floats, integers from `-2^49` up to but not including `2^49`, and binaries.

      memory = QuakeC.Memory.from_list([1.0, 2.0])
      memory = QuakeC.Memory.set(memory, 70_000, 3.0)
      QuakeC.Memory.get(memory, 70_000)
      #=> 3.0

  The memory is written in place and every copy of it sees every write, whichever copy
  made it: the words are held in `:atomics` chunks of #{0x10000} words, and the chunks and
  the binaries in an ETS table. `set/3` and `put/3` may return a memory that reaches a new
  chunk without a table lookup; an older copy reaches it through the table.

  The table belongs to the process that made the memory: the memory works from any
  process while that process lives, and `delete/1` frees it sooner. `copy/1` makes a
  memory written apart from the original.

  `get_code/2` gives the same read as quoted code, for compiled programs to inline.
  """

  import Bitwise

  @enforce_keys [:chunks, :table]
  defstruct [:chunks, :table]

  @type t :: %__MODULE__{chunks: tuple(), table: :ets.tid()}

  @float_shift 1 <<< 50
  @string_word 1 <<< 49
  @chunk_bits 16
  @chunk_words 1 <<< @chunk_bits
  @chunk_mask @chunk_words - 1

  @doc "Memory with no words written."
  @spec new() :: t()
  def new do
    table = :ets.new(__MODULE__, [:set, :public, read_concurrency: true])
    %__MODULE__{chunks: {}, table: table}
  end

  @doc "Memory holding `values` from index 0."
  @spec from_list([term()]) :: t()
  def from_list(values) do
    values
    |> Enum.with_index()
    |> Enum.reduce(new(), fn {value, index}, memory -> set(memory, index, value) end)
  end

  @doc "A memory holding the same values whose words are written apart from `memory`'s."
  @spec copy(t()) :: t()
  def copy(%__MODULE__{} = memory) do
    copied = new()

    for {{:chunk, number}, words} <- :ets.tab2list(memory.table) do
      chunk = :atomics.new(@chunk_words, signed: true)
      for at <- 1..@chunk_words, do: :atomics.put(chunk, at, :atomics.get(words, at))
      :ets.insert(copied.table, {{:chunk, number}, chunk})
    end

    for {index, text} <- :ets.tab2list(memory.table),
        is_integer(index),
        do: :ets.insert(copied.table, {index, text})

    %{copied | chunks: known_chunks(copied.table)}
  end

  @doc "Free the memory's table; neither it nor any copy of it may be used after."
  @spec delete(t()) :: :ok
  def delete(%__MODULE__{table: table}) do
    :ets.delete(table)
    :ok
  end

  @doc "The word at `index`."
  @spec get(t(), non_neg_integer()) :: term()
  def get(%__MODULE__{chunks: chunks} = memory, index) do
    number = index >>> @chunk_bits

    if number < tuple_size(chunks),
      do: decode(:atomics.get(elem(chunks, number), (index &&& @chunk_mask) + 1), memory, index),
      else: get_far(memory, number, index)
  end

  @doc "Write `value` at `index`; the memory to use from then on."
  @spec set(t(), non_neg_integer(), term()) :: t()
  def set(%__MODULE__{} = memory, index, value) do
    case put(memory, index, value) do
      :ok -> memory
      reaching -> reaching
    end
  end

  @doc """
  Write `value` at `index`: `:ok`, or a memory that reaches the chunk the word is in when
  the write made it.
  """
  @spec put(t(), non_neg_integer(), term()) :: :ok | t()
  def put(%__MODULE__{chunks: chunks} = memory, index, value) do
    number = index >>> @chunk_bits

    if number < tuple_size(chunks) do
      write(elem(chunks, number), memory.table, index, value)
    else
      memory = reach(memory, number)
      :ok = write(elem(memory.chunks, number), memory.table, index, value)
      memory
    end
  end

  @doc """
  Copy `count` words of `source` from index `from` into `target` from index `to`, as they
  stood before the copy (the ranges may overlap, and `source` may be `target`); the target
  memory to use from then on.
  """
  @spec move(t(), non_neg_integer(), t(), non_neg_integer(), non_neg_integer()) :: t()
  def move(%__MODULE__{} = source, from, %__MODULE__{} = target, to, count) do
    words = for i <- 0..(count - 1)//1, do: get(source, from + i)

    words
    |> Enum.with_index(to)
    |> Enum.reduce(target, fn {word, at}, memory -> set(memory, at, word) end)
  end

  @doc "Write integer or float `value` into `count` words from `index`; the memory to use from then on."
  @spec fill(t(), non_neg_integer(), non_neg_integer(), number()) :: t()
  def fill(%__MODULE__{} = memory, index, count, value) when is_number(value) do
    Enum.reduce(index..(index + count - 1)//1, memory, &set(&2, &1, value))
  end

  @doc "Code reading word `index` of `memory`, both quoted."
  @spec get_code(Macro.t(), Macro.t()) :: Macro.t()
  def get_code(memory, index),
    do: quote(generated: true, do: QuakeC.Memory.get(unquote(memory), unquote(index)))

  defp get_far(memory, number, index) do
    case :ets.lookup(memory.table, {:chunk, number}) do
      [{_, chunk}] -> decode(:atomics.get(chunk, (index &&& @chunk_mask) + 1), memory, index)
      [] -> 0
    end
  end

  defp write(chunk, _table, index, value) when is_float(value),
    do: :atomics.put(chunk, (index &&& @chunk_mask) + 1, float_word(value))

  defp write(chunk, _table, index, value)
       when is_integer(value) and value >= -@string_word and value < @string_word,
       do: :atomics.put(chunk, (index &&& @chunk_mask) + 1, value)

  defp write(chunk, table, index, value) when is_binary(value) do
    :ets.insert(table, {index, value})
    :atomics.put(chunk, (index &&& @chunk_mask) + 1, @string_word)
  end

  defp write(_chunk, _table, _index, value),
    do: raise(ArgumentError, "QuakeC memory cannot hold #{inspect(value)}")

  defp reach(%__MODULE__{table: table} = memory, number) do
    for missing <- 0..number//1 do
      :ets.insert_new(table, {{:chunk, missing}, :atomics.new(@chunk_words, signed: true)})
    end

    %{memory | chunks: known_chunks(table)}
  end

  defp known_chunks(table), do: chunks_from(table, 0, [])

  defp chunks_from(table, number, acc) do
    case :ets.lookup(table, {:chunk, number}) do
      [{_, chunk}] -> chunks_from(table, number + 1, [chunk | acc])
      [] -> acc |> Enum.reverse() |> List.to_tuple()
    end
  end

  defp decode(word, _memory, _index) when word >= -@string_word and word < @string_word,
    do: word

  defp decode(@string_word, %__MODULE__{table: table}, index),
    do: :ets.lookup_element(table, index, 2)

  defp decode(word, _memory, _index) do
    <<value::float-64>> = <<word - @float_shift::signed-64>>
    value
  end

  defp float_word(value) do
    <<bits::signed-64>> = <<value::float-64>>
    bits + @float_shift
  end
end
