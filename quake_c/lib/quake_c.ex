defmodule QuakeC do
  @moduledoc """
  A QuakeC program's memory: its globals, and every entity's fields laid end to end, as
  the program addresses them.

  Values are floats, integers (entity numbers, function indices, string offsets, field
  offsets and pointers), or binaries for strings made while running. A slot never written
  is `0`.

  A pointer is a byte address: global slot `n` is at `4 * n`, field slot `f` of entity
  `e` at `field_base() + 4 * (e * entity_fields + f)`, and memory from `alloc/2` at
  `heap_base()` and up. `load/2` and `store/3` read and write through one.

  Writes take effect in place (`QuakeC.Memory`): every copy of the struct sees them.
  `copy/1` gives memory written apart from the original. The memory belongs to the
  process that made it (`new/1`), works from any process while that process lives, and
  `release/1` frees it sooner.

      qc = QuakeC.new(progs)
      QuakeC.put_global(qc, "time", 1.5)
      QuakeC.field(qc, 1, "origin")
  """

  alias QuakeC.Progs

  @enforce_keys [:progs, :globals, :fields, :size, :global_offsets, :field_offsets]
  defstruct [
    :progs,
    :globals,
    :fields,
    :size,
    :global_offsets,
    :field_offsets,
    :heap,
    heap_top: 0,
    blocks: %{},
    spare: []
  ]

  @type value :: number() | binary()
  @type vector :: {float(), float(), float()}
  @type t :: %__MODULE__{}

  @field_base 0x10000000
  @heap_base 0x40000000

  @doc "The address of the first word `alloc/2` hands out."
  @spec heap_base() :: pos_integer()
  def heap_base, do: @heap_base

  @doc "`bytes` of fresh zeroed memory, rounded up to whole words: the memory and its address."
  @spec alloc(t(), non_neg_integer()) :: {t(), pos_integer()}
  def alloc(%__MODULE__{} = qc, bytes) do
    words = max(div(bytes + 3, 4), 1)

    {qc, word} =
      case first_fit(qc.spare, words, []) do
        {at, size, rest} -> {%{qc | spare: rest ++ spare_after(at, size, words)}, at}
        nil -> {%{qc | heap_top: qc.heap_top + words}, qc.heap_top}
      end

    heap = QuakeC.Memory.fill(qc.heap, word, words, 0)
    {%{qc | heap: heap, blocks: Map.put(qc.blocks, word, words)}, @heap_base + 4 * word}
  end

  @doc """
  Copy `words` words from address `from` to address `to`, as they stood before the copy;
  the ranges may overlap. Words from below address 0 read `0`; a copy to an address
  outside every space raises.
  """
  @spec move(t(), integer(), integer(), non_neg_integer()) :: t()
  def move(%__MODULE__{} = qc, _from, _to, 0), do: qc
  def move(%__MODULE__{} = qc, from, to, words) when from < 0, do: fill(qc, to, words, 0)

  def move(%__MODULE__{} = qc, from, to, words) do
    {source_space, source_index} = locate(from)
    {target_space, target_index} = locate!(to)
    source = Map.fetch!(qc, source_space)
    target = Map.fetch!(qc, target_space)
    moved = QuakeC.Memory.move(source, source_index, target, target_index, words)
    Map.put(qc, target_space, moved)
  end

  @doc "Write integer or float `value` into `words` words from address `address`."
  @spec fill(t(), integer(), non_neg_integer(), number()) :: t()
  def fill(%__MODULE__{} = qc, address, words, value) do
    {space, index} = locate!(address)
    Map.put(qc, space, QuakeC.Memory.fill(Map.fetch!(qc, space), index, words, value))
  end

  defp first_fit([], _words, _passed), do: nil

  defp first_fit([{at, size} | rest], words, passed) when size >= words,
    do: {at, size, Enum.reverse(passed, rest)}

  defp first_fit([block | rest], words, passed), do: first_fit(rest, words, [block | passed])

  defp locate(address) when address >= @heap_base, do: {:heap, div(address - @heap_base, 4)}
  defp locate(address) when address >= @field_base, do: {:fields, div(address - @field_base, 4)}
  defp locate(address), do: {:globals, div(address, 4)}

  defp locate!(address) when address > 0, do: locate(address)

  defp locate!(address),
    do: raise(ArgumentError, "a QuakeC program wrote through the bad pointer #{address}")

  @doc "Give back memory `alloc/2` handed out at `address`; any other address is left alone."
  @spec free(t(), integer()) :: t()
  def free(%__MODULE__{} = qc, address) do
    word = div(address - @heap_base, 4)

    case Map.pop(qc.blocks, word) do
      {nil, _} -> qc
      {words, blocks} -> %{qc | blocks: blocks, spare: [{word, words} | qc.spare]}
    end
  end

  defp spare_after(_at, size, words) when size == words, do: []
  defp spare_after(at, size, words), do: [{at + words, size - words}]

  @doc "The address of field slot 0 of entity 0."
  @spec field_base() :: pos_integer()
  def field_base, do: @field_base

  @doc "The address of field slot `offset` of `entity`."
  @spec field_address(t(), non_neg_integer(), non_neg_integer()) :: pos_integer()
  def field_address(%__MODULE__{size: size}, entity, offset),
    do: @field_base + 4 * (entity * size + offset)

  @doc "The value at address `address`; an address outside every space reads `0`."
  @spec load(t(), integer()) :: value()
  def load(%__MODULE__{} = qc, address) when address >= @heap_base,
    do: QuakeC.Memory.get(qc.heap, div(address - @heap_base, 4))

  def load(%__MODULE__{} = qc, address) when address >= @field_base,
    do: QuakeC.Memory.get(qc.fields, div(address - @field_base, 4))

  def load(%__MODULE__{} = qc, address) when address >= 0,
    do: QuakeC.Memory.get(qc.globals, div(address, 4))

  def load(_qc, _address), do: 0

  @doc "Write `value` at address `address`."
  @spec store(t(), integer(), value()) :: t()
  def store(%__MODULE__{} = qc, address, value) when address >= @heap_base,
    do: in_heap(qc, div(address - @heap_base, 4), value)

  def store(%__MODULE__{} = qc, address, value) when address >= @field_base,
    do: in_fields(qc, div(address - @field_base, 4), value)

  def store(%__MODULE__{} = qc, address, value) when address > 0,
    do: in_globals(qc, div(address, 4), value)

  def store(_qc, address, _value),
    do: raise(ArgumentError, "a QuakeC program wrote through the bad pointer #{address}")

  @doc "Fresh memory for `progs`: its initial globals, every entity field zero."
  @spec new(Progs.t()) :: t()
  def new(%Progs{} = progs) do
    %__MODULE__{
      progs: progs,
      globals: QuakeC.Memory.from_list(Tuple.to_list(progs.globals)),
      fields: QuakeC.Memory.new(),
      heap: QuakeC.Memory.new(),
      size: progs.entity_fields,
      global_offsets:
        Map.new(progs.global_defs, fn {name, {_type, offset}} -> {name, offset} end),
      field_offsets: Map.new(progs.field_defs, fn {name, {_type, offset}} -> {name, offset} end)
    }
  end

  @doc "Memory holding the same values as `qc`, written apart from it."
  @spec copy(t()) :: t()
  def copy(%__MODULE__{} = qc) do
    %{
      qc
      | globals: QuakeC.Memory.copy(qc.globals),
        fields: QuakeC.Memory.copy(qc.fields),
        heap: QuakeC.Memory.copy(qc.heap)
    }
  end

  @doc "Free `qc`'s memory (`QuakeC.Memory.delete/1`); neither it nor any copy may be used after."
  @spec release(t()) :: :ok
  def release(%__MODULE__{} = qc) do
    Enum.each([qc.globals, qc.fields, qc.heap], &QuakeC.Memory.delete/1)
  end

  @doc "The global slot `offset`."
  @spec slot(t(), non_neg_integer()) :: value()
  def slot(%__MODULE__{globals: globals}, offset), do: QuakeC.Memory.get(globals, offset)

  @doc "Set global slot `offset`."
  @spec put_slot(t(), non_neg_integer(), value()) :: t()
  def put_slot(%__MODULE__{} = qc, offset, value), do: in_globals(qc, offset, value)

  @doc """
  Set global slot `offset`: `:ok` when only the memory's words changed, or the memory to
  use from then on (`QuakeC.Memory.put/3`).
  """
  @spec update_slot(t(), non_neg_integer(), value()) :: :ok | t()
  def update_slot(%__MODULE__{} = qc, offset, value) do
    case QuakeC.Memory.put(qc.globals, offset, value) do
      :ok -> :ok
      globals -> %{qc | globals: globals}
    end
  end

  @doc "The three slots from `offset` as a vector."
  @spec slot_vector(t(), non_neg_integer()) :: vector()
  def slot_vector(%__MODULE__{globals: globals}, offset),
    do:
      {float(QuakeC.Memory.get(globals, offset)), float(QuakeC.Memory.get(globals, offset + 1)),
       float(QuakeC.Memory.get(globals, offset + 2))}

  @doc "Set the three slots from `offset`."
  @spec put_slot_vector(t(), non_neg_integer(), vector()) :: t()
  def put_slot_vector(%__MODULE__{} = qc, offset, {x, y, z}),
    do: qc |> in_globals(offset, x) |> in_globals(offset + 1, y) |> in_globals(offset + 2, z)

  @doc "The global named `name`."
  @spec global(t(), String.t()) :: value()
  def global(%__MODULE__{} = qc, name), do: slot(qc, Map.fetch!(qc.global_offsets, name))

  @doc "The vector global named `name`."
  @spec global_vector(t(), String.t()) :: vector()
  def global_vector(%__MODULE__{} = qc, name),
    do: slot_vector(qc, Map.fetch!(qc.global_offsets, name))

  @doc "Set the global named `name`; a vector sets three slots."
  @spec put_global(t(), String.t(), value() | vector()) :: t()
  def put_global(%__MODULE__{} = qc, name, {_, _, _} = vector),
    do: put_slot_vector(qc, Map.fetch!(qc.global_offsets, name), vector)

  def put_global(%__MODULE__{} = qc, name, value),
    do: put_slot(qc, Map.fetch!(qc.global_offsets, name), value)

  @doc "Set the global named `name` when the program declares one; otherwise leave the memory as it is."
  @spec put_declared(t(), String.t(), value() | vector()) :: t()
  def put_declared(%__MODULE__{} = qc, name, value) do
    if global?(qc, name), do: put_global(qc, name, value), else: qc
  end

  @doc "Whether the program has a global `name`."
  @spec global?(t(), String.t()) :: boolean()
  def global?(%__MODULE__{global_offsets: offsets}, name), do: Map.has_key?(offsets, name)

  @doc "Field slot `offset` of `entity`."
  @spec field_slot(t(), non_neg_integer(), non_neg_integer()) :: value()
  def field_slot(%__MODULE__{fields: fields, size: size}, entity, offset),
    do: QuakeC.Memory.get(fields, entity * size + offset)

  @doc "Set field slot `offset` of `entity`."
  @spec put_field_slot(t(), non_neg_integer(), non_neg_integer(), value()) :: t()
  def put_field_slot(%__MODULE__{} = qc, entity, offset, value),
    do: in_fields(qc, entity * qc.size + offset, value)

  @doc "The offset of field `name`, or `nil` when the program has none."
  @spec field_offset(t(), String.t()) :: non_neg_integer() | nil
  def field_offset(%__MODULE__{field_offsets: offsets}, name), do: Map.get(offsets, name)

  @doc "The type of field `name`, or `nil`."
  @spec field_type(t(), String.t()) :: atom() | nil
  def field_type(%__MODULE__{progs: progs}, name) do
    case Map.get(progs.field_defs, name) do
      {type, _offset} -> type
      nil -> nil
    end
  end

  @doc "Field `name` of `entity`; `0` when the program has no such field."
  @spec field(t(), non_neg_integer(), String.t()) :: value()
  def field(%__MODULE__{} = qc, entity, name) do
    case field_offset(qc, name) do
      nil -> 0
      offset -> field_slot(qc, entity, offset)
    end
  end

  @doc "Vector field `name` of `entity`."
  @spec field_vector(t(), non_neg_integer(), String.t()) :: vector()
  def field_vector(%__MODULE__{} = qc, entity, name) do
    case field_offset(qc, name) do
      nil ->
        {0.0, 0.0, 0.0}

      offset ->
        base = entity * qc.size + offset

        {float(QuakeC.Memory.get(qc.fields, base)), float(QuakeC.Memory.get(qc.fields, base + 1)),
         float(QuakeC.Memory.get(qc.fields, base + 2))}
    end
  end

  @doc "Set field `name` of `entity`; a vector sets three slots. A field the program lacks is left alone."
  @spec put_field(t(), non_neg_integer(), String.t(), value() | vector()) :: t()
  def put_field(%__MODULE__{} = qc, entity, name, value) do
    case field_offset(qc, name) do
      nil -> qc
      offset -> put_at(qc, entity * qc.size + offset, value)
    end
  end

  @doc "Every field of `entity` set back to zero."
  @spec clear_entity(t(), non_neg_integer()) :: t()
  def clear_entity(%__MODULE__{} = qc, entity) do
    base = entity * qc.size
    Enum.reduce(0..(qc.size - 1), qc, &in_fields(&2, base + &1, 0))
  end

  @doc "A string value as text: an offset into the program's strings, or a made string."
  @spec string(t(), value()) :: String.t()
  def string(_qc, value) when is_binary(value), do: value

  def string(%__MODULE__{progs: progs}, value) when is_integer(value),
    do: Progs.string(progs, value)

  def string(_qc, _value), do: ""

  @doc "A value as a float."
  @spec float(value()) :: float()
  def float(value) when is_float(value), do: value
  def float(value) when is_integer(value), do: value / 1
  def float(_value), do: 0.0

  defp put_at(qc, index, {x, y, z}),
    do: qc |> in_fields(index, x) |> in_fields(index + 1, y) |> in_fields(index + 2, z)

  defp put_at(qc, index, value), do: in_fields(qc, index, value)

  defp in_globals(qc, index, value) do
    case QuakeC.Memory.put(qc.globals, index, value) do
      :ok -> qc
      globals -> %{qc | globals: globals}
    end
  end

  defp in_fields(qc, index, value) do
    case QuakeC.Memory.put(qc.fields, index, value) do
      :ok -> qc
      fields -> %{qc | fields: fields}
    end
  end

  defp in_heap(qc, index, value) do
    case QuakeC.Memory.put(qc.heap, index, value) do
      :ok -> qc
      heap -> %{qc | heap: heap}
    end
  end
end
