defmodule QuakeC.Compiler.Runtime do
  @moduledoc """
  The value rules compiled QuakeC code runs by: how a slot's value reads as a float, an
  integer, a truth or a string; the arithmetic that needs care (division by zero, 32-bit
  integer wrapping, random numbers); and reads and writes of globals, entity fields and
  pointers in the program memory (`QuakeC`).

  Values are floats, integers, or binaries for strings made while running. A value of the
  wrong kind reads as `0`.
  """

  import Bitwise

  alias QuakeC.Memory

  @doc "A value as a number."
  @spec num(term()) :: number()
  def num(value) when is_number(value), do: value
  def num(_value), do: 0

  @doc "A value as an integer, a float truncated."
  @spec int(term()) :: integer()
  def int(value) when is_integer(value), do: value
  def int(value) when is_float(value), do: trunc(value)
  def int(_value), do: 0

  @doc "A value as a float."
  @spec float(term()) :: float()
  def float(value), do: num(value) / 1

  @doc "Whether a string value is set and not empty."
  @spec text?(QuakeC.t(), term()) :: boolean()
  def text?(qc, value), do: QuakeC.string(qc, value) != ""

  @doc "A string value as text."
  @spec text(QuakeC.t(), term()) :: String.t()
  def text(qc, value), do: QuakeC.string(qc, value)

  @doc "`a / b`, 0.0 when `b` is zero."
  @spec divide(number(), number()) :: float()
  def divide(_a, b) when b == 0, do: 0.0
  def divide(a, b), do: a / b

  @doc "Integer `a / b` rounded toward zero, 0 when `b` is zero."
  @spec int_divide(integer(), integer()) :: integer()
  def int_divide(_a, 0), do: 0
  def int_divide(a, b), do: div(a, b)

  @doc "An integer wrapped into 32 signed bits."
  @spec wrap(integer()) :: integer()
  def wrap(value), do: (value + 0x80000000 &&& 0xFFFFFFFF) - 0x80000000

  @doc "A random number from 0 up to but not including 1, in steps of 1/32768."
  @spec below_one() :: float()
  def below_one, do: (:rand.uniform(0x8000) - 1) / 0x8000

  @doc "A random number from 0 to 1 inclusive, in steps of 1/32767."
  @spec up_to_one() :: float()
  def up_to_one, do: (:rand.uniform(0x8000) - 1) / 0x7FFF

  @doc "Global slot `offset`."
  @spec global(QuakeC.t(), non_neg_integer()) :: term()
  def global(qc, offset), do: Memory.get(qc.globals, offset)

  @doc "The memory with global slot `offset` set to `value`."
  @spec put(QuakeC.t(), non_neg_integer(), term()) :: QuakeC.t()
  def put(qc, offset, value), do: QuakeC.put_slot(qc, offset, value)

  @doc "The parameter slots of `count` arguments, from slot 4, as call arguments."
  @spec args(QuakeC.t(), non_neg_integer()) :: tuple()
  def args(qc, count), do: List.to_tuple(for slot <- 4..(3 + 3 * count)//1, do: global(qc, slot))

  @doc "Global slots `slots`, as a tuple."
  @spec slots(QuakeC.t(), [non_neg_integer()]) :: tuple()
  def slots(qc, slots), do: List.to_tuple(for slot <- slots, do: global(qc, slot))

  @doc "The words of parameter slots `slots` from the 24 slots `handed`, as a tuple."
  @spec pick(tuple(), [non_neg_integer()]) :: tuple()
  def pick(handed, slots), do: List.to_tuple(for slot <- slots, do: elem(handed, slot - 4))

  @doc "The memory with call arguments `args` in the parameter slots from slot 4."
  @spec put_args(QuakeC.t(), tuple()) :: QuakeC.t()
  def put_args(qc, args) do
    args
    |> Tuple.to_list()
    |> Enum.with_index(4)
    |> Enum.reduce(qc, fn {value, slot}, acc -> QuakeC.put_slot(acc, slot, value) end)
  end

  @doc "The return slots 1 to 3."
  @spec returned(QuakeC.t()) :: {term(), term(), term()}
  def returned(qc), do: {global(qc, 1), global(qc, 2), global(qc, 3)}

  @doc "The memory with `returned` in the return slots 1 to 3."
  @spec put_returned(QuakeC.t(), {term(), term(), term()}) :: QuakeC.t()
  def put_returned(qc, {x, y, z}),
    do: qc |> QuakeC.put_slot(1, x) |> QuakeC.put_slot(2, y) |> QuakeC.put_slot(3, z)

  @doc "Field slot `field` of `entity`, both as values."
  @spec field(QuakeC.t(), term(), term()) :: term()
  def field(qc, entity, field), do: Memory.get(qc.fields, int(entity) * qc.size + int(field))

  @doc "The address of field slot `field` of `entity`."
  @spec field_address(QuakeC.t(), term(), term()) :: integer()
  def field_address(qc, entity, field), do: QuakeC.field_address(qc, int(entity), int(field))

  @doc "The value at address `address` plus `4 * index`."
  @spec load(QuakeC.t(), term(), term()) :: term()
  def load(qc, address, index), do: QuakeC.load(qc, int(address) + 4 * int(index))

  @doc "The float at address `address`."
  @spec load_float(QuakeC.t(), integer()) :: float()
  def load_float(qc, address), do: float(QuakeC.load(qc, address))

  @doc "Write `value` at address `address` plus `4 * index`."
  @spec store(QuakeC.t(), term(), term(), term()) :: QuakeC.t()
  def store(qc, address, index, value), do: QuakeC.store(qc, int(address) + 4 * int(index), value)

  @doc "Write the three values of `vector` from address `address`."
  @spec store_vector(QuakeC.t(), integer(), tuple()) :: QuakeC.t()
  def store_vector(qc, address, {x, y, z}),
    do:
      qc
      |> QuakeC.store(address, x)
      |> QuakeC.store(address + 4, y)
      |> QuakeC.store(address + 8, z)

  @doc "The float at address `address`, changed by `change`, written back; the new value and memory."
  @spec through(QuakeC.t(), term(), (float() -> float())) :: {float(), QuakeC.t()}
  def through(qc, address, change) do
    at = int(address)
    value = change.(load_float(qc, at))
    {value, QuakeC.store(qc, at, value)}
  end

  @doc "The vector at address `address`, changed by `change`, written back; the new vector and memory."
  @spec through_vector(QuakeC.t(), term(), (tuple() -> tuple())) :: {tuple(), QuakeC.t()}
  def through_vector(qc, address, change) do
    at = int(address)
    value = change.({load_float(qc, at), load_float(qc, at + 4), load_float(qc, at + 8)})
    {value, store_vector(qc, at, value)}
  end

  @doc "A string value moved on by `n` characters: an offset plus `n`, or the rest of a made string."
  @spec string_offset(term(), integer()) :: term()
  def string_offset(value, n) when is_integer(value), do: value + n

  def string_offset(value, n) when is_binary(value) and n >= 0 and n <= byte_size(value),
    do: binary_part(value, n, byte_size(value) - n)

  def string_offset(_value, _n), do: 0

  @doc "How many characters string value `b` lies past `a`."
  @spec string_distance(term(), term()) :: integer()
  def string_distance(a, b) when is_integer(a) and is_integer(b), do: a - b
  def string_distance(a, b) when is_binary(a) and is_binary(b), do: byte_size(b) - byte_size(a)
  def string_distance(_a, _b), do: 0

  @doc "Character `index` of string value `value` as a float, 0.0 past either end."
  @spec string_at(QuakeC.t(), term(), term()) :: float()
  def string_at(qc, value, index) do
    text = QuakeC.string(qc, value)
    at = trunc(num(index))
    if at >= 0 and at < byte_size(text), do: :binary.at(text, at) / 1, else: 0.0
  end

  @doc "A `switch` value: how later `case` instructions compare against it."
  @spec switch(QuakeC.t(), non_neg_integer(), term(), term(), term()) :: tuple()
  def switch(_qc, 99, x, y, z), do: {:vector, {x, y, z}}
  def switch(qc, 100, value, _y, _z), do: {:string, QuakeC.string(qc, value)}
  def switch(_qc, 98, value, _y, _z), do: {:number, QuakeC.float(value)}
  def switch(_qc, _op, value, _y, _z), do: {:number, value}

  @doc "Whether a `case` matches the `switch` value."
  @spec case?(QuakeC.t(), tuple() | nil, term(), term(), term()) :: boolean()
  def case?(_qc, {:vector, value}, x, y, z), do: value == {x, y, z}
  def case?(qc, {:string, value}, label, _y, _z), do: value == QuakeC.string(qc, label)
  def case?(_qc, {:number, value}, label, _y, _z), do: value == label
  def case?(_qc, _switch, _label, _y, _z), do: false

  @doc "Whether a `case` range from `low` to `high` holds the `switch` value."
  @spec case_range?(tuple() | nil, term(), term()) :: boolean()
  def case_range?({:number, value}, low, high),
    do: is_number(value) and value >= QuakeC.float(low) and value <= QuakeC.float(high)

  def case_range?(_switch, _low, _high), do: false

  @doc "The `state` instruction: `self` thinks `think` at frame `frame` a tenth of a second on."
  @spec state(QuakeC.t(), term(), term()) :: QuakeC.t()
  def state(qc, frame, think) do
    self = QuakeC.global(qc, "self")
    time = QuakeC.float(QuakeC.global(qc, "time"))

    qc
    |> QuakeC.put_field(self, "nextthink", time + 0.1)
    |> QuakeC.put_field(self, "frame", frame)
    |> QuakeC.put_field(self, "think", think)
  end

  @doc "The `thinktime` instruction: `entity` thinks `seconds` from now."
  @spec think_time(QuakeC.t(), term(), term()) :: QuakeC.t()
  def think_time(qc, entity, seconds) do
    time = QuakeC.float(QuakeC.global(qc, "time"))
    QuakeC.put_field(qc, trunc(QuakeC.float(entity)), "nextthink", time + QuakeC.float(seconds))
  end
end
