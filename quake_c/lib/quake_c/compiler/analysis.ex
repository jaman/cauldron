defmodule QuakeC.Compiler.Analysis do
  @moduledoc """
  What compiling a QuakeC program needs to know about it.

  For the whole program (`program/1`):

    * `constants` — slots no instruction or call writes and nothing addresses, unnamed,
      named `IMMEDIATE` or `::…`, or holding a field or a function, by their fixed value
    * `escaped` — slots that may be reached through an address: from each
      `GLOBALADDRESS` and array-load base up to the next defined global, and the slots
      constant pointers point at

  For one function (`function/3`):

    * `statements` — the reachable statements, `{index, {op, a, b, c}}` in order
    * `leaders` — the indexes where a basic block starts
    * `vars` — slots held in variables: the function's own locals, the unnamed slots it
      writes that no function reads before writing, and its call slots; when any of its
      own locals may be reached through an address, `mode` is `:memory` and `vars` holds
      only the call slots
    * `calls` — the return and parameter slots (1 to 27) the function uses that nothing
      addresses, held in variables: a call passes its arguments and takes its return
      value as values; a function that hands values back uses every parameter slot
    * `live` — the slots the function may read before writing them
    * `params` — `{slot, size}` for each parameter, in order
    * `hands_back` — whether a parameter slot it writes reaches a return with no call
      between (`hands_back?/2`)
    * `kept` — `%{index => slots}`: for each call after which some of its argument slots
      are read before being written, those slots
  """

  import Bitwise

  alias QuakeC.Progs

  @returns [0, 43]
  @conditions [49, 50, 136, 137, 217, 218]
  @switches [98, 99, 100, 101, 102, 215]
  @most_vars 230

  @typedoc "Facts about a whole program."
  @type program :: %{
          constants: %{non_neg_integer() => term()},
          escaped: MapSet.t(),
          unnamed: MapSet.t()
        }

  @typedoc "Facts about one function."
  @type function_facts :: %{
          index: non_neg_integer(),
          name: String.t(),
          statements: [{non_neg_integer(), tuple()}],
          leaders: MapSet.t(),
          vars: [non_neg_integer()],
          calls: [non_neg_integer()],
          live: MapSet.t(),
          params: [{non_neg_integer(), pos_integer()}],
          hands_back: boolean(),
          kept: %{non_neg_integer() => [non_neg_integer()]},
          mode: :vars | :memory,
          parm_start: non_neg_integer(),
          locals: non_neg_integer()
        }

  @doc "The facts about `progs` every function's compilation shares."
  @spec program(Progs.t()) :: program()
  def program(%Progs{} = progs) do
    defined = progs.global_defs |> Map.new(fn {name, {_type, offset}} -> {offset, name} end)
    starts = defined |> Map.keys() |> Enum.sort()
    count = tuple_size(progs.globals)
    written = progs |> written() |> MapSet.union(locals(progs))
    escaped = escaped(progs, starts, count, written, defined)

    kinds =
      Enum.group_by(
        progs.global_defs,
        fn {_name, {_type, offset}} -> offset end,
        fn {name, {type, _offset}} -> {name, type} end
      )

    constants =
      for slot <- 28..(count - 1)//1,
          not MapSet.member?(written, slot),
          not MapSet.member?(escaped, slot),
          fixed?(Map.get(kinds, slot, [])),
          into: %{},
          do: {slot, elem(progs.globals, slot)}

    unnamed =
      for slot <- 28..(count - 1)//1,
          not Map.has_key?(defined, slot),
          into: MapSet.new(),
          do: slot

    shared =
      for index <- 0..(tuple_size(progs.functions) - 1)//1,
          fun = elem(progs.functions, index),
          fun.first > 0,
          slot <- entry_live(progs, fun.first),
          MapSet.member?(unnamed, slot),
          into: MapSet.new(),
          do: slot

    %{constants: constants, escaped: escaped, unnamed: MapSet.difference(unnamed, shared)}
  end

  @doc "The facts about function `index` of `progs`, given the program's (`program/1`)."
  @spec function(Progs.t(), non_neg_integer(), program()) :: function_facts()
  def function(%Progs{} = progs, index, program) do
    fun = elem(progs.functions, index)
    reachable = reach(progs, fun.first)
    statements = for at <- Enum.sort(reachable), do: {at, elem(progs.statements, at)}
    own = fun.parm_start..(fun.parm_start + fun.locals - 1)//1

    temps =
      for {_at, {op, a, b, c}} <- statements,
          slot <- writes(op, a, b, c),
          MapSet.member?(program.unnamed, slot),
          not MapSet.member?(program.escaped, slot),
          into: MapSet.new(),
          do: slot

    hands_back = hands_back?(progs, index)
    handed = if hands_back, do: Enum.to_list(4..27), else: []

    calls =
      for {_at, {op, a, b, c}} <- statements,
          slot <- writes(op, a, b, c) ++ reads(op, a, b, c) ++ passed(op) ++ handed,
          slot in 1..27,
          not MapSet.member?(program.escaped, slot),
          into: MapSet.new(),
          do: slot

    vars =
      own
      |> MapSet.new()
      |> MapSet.union(temps)
      |> MapSet.union(calls)
      |> MapSet.difference(Map.keys(program.constants) |> MapSet.new())

    lives = live_map(progs, fun.first)
    live = Map.get(lives, fun.first, MapSet.new())
    addressed? = Enum.any?(own, &MapSet.member?(program.escaped, &1))
    mode = if addressed? or MapSet.size(vars) > @most_vars, do: :memory, else: :vars

    %{
      index: index,
      name: fun.name,
      statements: statements,
      leaders: leaders(fun.first, statements),
      vars: if(mode == :vars, do: Enum.sort(vars), else: Enum.sort(calls)),
      calls: Enum.sort(calls),
      live: live,
      params: params(fun.parm_start, fun.parm_sizes),
      hands_back: hands_back,
      kept: kept(statements, lives),
      mode: mode,
      parm_start: fun.parm_start,
      locals: fun.locals
    }
  end

  @doc """
  Whether function `index` writes a parameter slot (4 to 27) that reaches one of its
  returns with no call between: it hands a value back to its caller in a parameter slot,
  as an `__out` parameter does.
  """
  @spec hands_back?(Progs.t(), non_neg_integer()) :: boolean()
  def hands_back?(%Progs{} = progs, index) do
    fun = elem(progs.functions, index)

    fun.first > 0 and
      progs
      |> reach(fun.first)
      |> Enum.any?(fn at ->
        {op, a, b, c} = elem(progs.statements, at)

        not call?(op) and Enum.any?(writes(op, a, b, c), &(&1 in 4..27)) and
          returns_before_call?(progs, next(at, {op, a, b, c}), MapSet.new())
      end)
  end

  @doc "Whether instruction `op` is a call."
  @spec call?(non_neg_integer()) :: boolean()
  def call?(op), do: op in 51..59 or op in 105..112

  @doc "The global slots instruction `{op, a, b, c}` writes directly (not through an address)."
  @spec writes(non_neg_integer(), integer(), integer(), integer()) :: [integer()]
  def writes(op, _a, b, _c) when op in [31, 33, 34, 35, 36, 113, 152, 114, 115], do: [b]
  def writes(32, _a, b, _c), do: [b, b + 1, b + 2]
  def writes(246, _a, b, _c), do: [b, b + 1]
  def writes(op, _a, b, _c) when op in [66, 70, 72, 76, 88, 90], do: [b]
  def writes(op, _a, b, _c) when op in [67, 73, 77], do: [b, b + 1, b + 2]
  def writes(op, _a, _b, c) when op in [68, 71, 74, 78], do: [c]
  def writes(op, _a, _b, c) when op in [69, 75, 79], do: [c, c + 1, c + 2]

  def writes(op, _a, _b, _c) when op in 51..59, do: [1, 2, 3]

  def writes(op, _a, _b, _c) when op in 105..112,
    do: [1, 2, 3] ++ Enum.to_list(4..if(op > 105, do: 9, else: 6))

  def writes(op, _a, _b, _c)
      when op in [0, 43, 37, 38, 39, 40, 41, 42, 127, 128, 129, 89, 91, 219, 220, 221, 222] or
             op in 49..61 or op in 98..104 or op in [136, 137, 211, 215, 217, 218, 87, 177],
      do: []

  def writes(op, _a, _b, c) when op in [3, 4, 7, 9, 25, 95, 96, 97, 139, 146, 155, 181, 182],
    do: [c, c + 1, c + 2]

  def writes(_op, _a, _b, c), do: [c]

  @doc """
  The global slots instruction `{op, a, b, c}` reads as values or as the parts of an
  address. A return, and a call's copy of its arguments, count as reading the first slot
  of each value they copy: the other two are read only for a vector, which the function
  wrote first. A call reads the first parameter slot of every argument it passes.
  """
  @spec reads(non_neg_integer(), integer(), integer(), integer()) :: [integer()]
  def reads(op, a, _b, _c) when op in [0, 43], do: [a]
  def reads(105, a, b, _c), do: [a, b | first_slots(1)]
  def reads(op, a, b, c) when op in 106..112, do: [a, b, c | first_slots(op - 104)]
  def reads(op, a, _b, _c) when op in 51..59, do: [a | first_slots(op - 51)]
  def reads(61, _a, _b, _c), do: []
  def reads(op, _a, _b, _c) when op in [92, 95, 177], do: []
  def reads(op, a, _b, _c) when op in [31, 33, 34, 35, 36, 113, 152, 114, 115], do: [a]
  def reads(op, a, _b, _c) when op in [44, 46, 47, 48, 93, 122, 123, 124, 125, 138, 211], do: [a]

  def reads(op, a, _b, _c) when op in [49, 50, 136, 137, 217, 218, 98, 100, 101, 102, 215],
    do: [a]

  def reads(op, a, _b, _c) when op in [32, 45, 96, 99, 103], do: triple(a)
  def reads(246, a, _b, _c), do: [a, a + 1]
  def reads(op, a, b, _c) when op in [2, 7, 9, 11, 16, 73, 77, 97], do: triple(a) ++ triple(b)
  def reads(op, a, b, _c) when op in [3, 67, 182], do: [a | triple(b)]
  def reads(op, a, b, _c) when op in [4, 139, 181, 75, 79], do: triple(a) ++ [b]
  def reads(38, a, b, c), do: triple(a) ++ [b, c]
  def reads(219, a, b, c), do: [a, b | triple(c)]

  def reads(op, a, b, c) when op in [37, 39, 40, 41, 42, 127, 128, 129, 220, 221, 222],
    do: [a, b, c]

  def reads(op, _a, b, _c) when op in 143..151 and op != 144, do: [b]
  def reads(_op, a, b, _c), do: [a, b]

  @doc "The statements a jump at `at` can go to next, and whether it can fall through."
  @spec next(non_neg_integer(), tuple()) :: [non_neg_integer()]
  def next(_at, {op, _, _, _}) when op in @returns, do: []
  def next(at, {61, a, _, _}), do: [at + a]
  def next(at, {op, _, b, _}) when op in @conditions, do: [at + 1, at + b]
  def next(at, {op, _, b, _}) when op in @switches, do: [at + b]
  def next(at, {103, _, b, _}), do: [at + 1, at + b]
  def next(at, {104, _, _, c}), do: [at + 1, at + c]
  def next(at, _statement), do: [at + 1]

  @doc "Whether statement `{op, _, _, _}` ends a basic block."
  @spec ends_block?(tuple()) :: boolean()
  def ends_block?({op, _, _, _}),
    do: op in @returns or op == 61 or op in @conditions or op in @switches or op in [103, 104]

  defp triple(slot), do: [slot, slot + 1, slot + 2]

  defp arguments(count), do: Enum.to_list(4..(3 + 3 * count)//1)

  defp first_slots(count), do: Enum.to_list(4..(1 + 3 * count)//3)

  defp entry_live(progs, first), do: progs |> live_map(first) |> Map.get(first, MapSet.new())

  defp live_map(progs, first) do
    statements = progs |> reach(first) |> Map.new(&{&1, elem(progs.statements, &1)})
    settle(statements, Map.new(statements, fn {at, _} -> {at, MapSet.new()} end))
  end

  defp kept(statements, lives) do
    for {at, {op, a, b, c} = statement} <- statements,
        call?(op),
        after_it =
          at
          |> next(statement)
          |> Enum.reduce(MapSet.new(), &MapSet.union(&2, Map.get(lives, &1, MapSet.new()))),
        slots = Enum.filter(call_arguments(op, a, b, c), &MapSet.member?(after_it, &1)),
        slots != [],
        into: %{},
        do: {at, slots}
  end

  defp call_arguments(op, _a, _b, _c) when op in 51..59, do: arguments(op - 51)
  defp call_arguments(op, _a, _b, _c), do: arguments(op - 104)

  defp passed(op) when op in 51..59, do: arguments(op - 51)
  defp passed(op) when op in 105..112, do: arguments(op - 104)
  defp passed(_op), do: []

  defp returns_before_call?(_progs, [], _seen), do: false

  defp returns_before_call?(progs, [at | rest], seen) do
    if MapSet.member?(seen, at) or at < 0 or at >= tuple_size(progs.statements),
      do: returns_before_call?(progs, rest, seen),
      else: returns_at?(progs, at, rest, MapSet.put(seen, at))
  end

  defp returns_at?(progs, at, rest, seen) do
    {op, _, _, _} = statement = elem(progs.statements, at)

    cond do
      op in @returns -> true
      call?(op) -> returns_before_call?(progs, rest, seen)
      true -> returns_before_call?(progs, next(at, statement) ++ rest, seen)
    end
  end

  defp settle(statements, live) do
    next_live =
      Map.new(statements, fn {at, {op, a, b, c} = statement} ->
        after_it =
          statement
          |> then(&next(at, &1))
          |> Enum.reduce(MapSet.new(), &MapSet.union(&2, Map.get(live, &1, MapSet.new())))

        reads = MapSet.new(reads(op, a, b, c))
        {at, MapSet.union(reads, MapSet.difference(after_it, MapSet.new(writes(op, a, b, c))))}
      end)

    if next_live == live, do: live, else: settle(statements, next_live)
  end

  defp reach(progs, first), do: reach(progs, [first], MapSet.new())

  defp reach(_progs, [], seen), do: seen

  defp reach(progs, [at | rest], seen) do
    if MapSet.member?(seen, at) or at < 0 or at >= tuple_size(progs.statements),
      do: reach(progs, rest, seen),
      else: reach(progs, next(at, elem(progs.statements, at)) ++ rest, MapSet.put(seen, at))
  end

  defp leaders(first, statements) do
    Enum.reduce(statements, MapSet.new([first]), fn {at, statement}, acc ->
      if ends_block?(statement),
        do: Enum.reduce(next(at, statement), acc, &MapSet.put(&2, &1)) |> MapSet.put(at + 1),
        else: acc
    end)
  end

  defp params(start, sizes) do
    {params, _} =
      Enum.map_reduce(sizes, start, fn size, at -> {{at, size}, at + size} end)

    params
  end

  defp fixed?(defs),
    do: Enum.all?(defs, fn {name, type} -> anonymous?(name) or type in [:field, :function] end)

  defp anonymous?(nil), do: true
  defp anonymous?("IMMEDIATE"), do: true
  defp anonymous?("::" <> _), do: true
  defp anonymous?(_name), do: false

  defp locals(progs) do
    for index <- 0..(tuple_size(progs.functions) - 1)//1,
        fun = elem(progs.functions, index),
        slot <- fun.parm_start..(fun.parm_start + fun.locals - 1)//1,
        into: MapSet.new(),
        do: slot
  end

  defp written(progs) do
    for at <- 0..(tuple_size(progs.statements) - 1)//1,
        {op, a, b, c} = elem(progs.statements, at),
        slot <- writes(op, a, b, c),
        into: MapSet.new(),
        do: slot
  end

  defp escaped(progs, starts, count, written, defined) do
    bases =
      for at <- 0..(tuple_size(progs.statements) - 1)//1,
          {op, a, _b, _c} = elem(progs.statements, at),
          op == 143 or op in 145..151,
          into: MapSet.new(),
          do: a

    regions = for base <- bases, slot <- base..(region_end(starts, base, count) - 1)//1, do: slot

    pointed =
      for at <- 0..(tuple_size(progs.statements) - 1)//1,
          {op, a, b, _c} = elem(progs.statements, at),
          operand <- pointer_operands(op, a, b),
          not MapSet.member?(written, operand),
          not Map.has_key?(defined, operand) or anonymous?(Map.get(defined, operand)),
          target = pointer_target(elem(progs.globals, operand), count),
          target != nil,
          slot <- target..(target + 2),
          do: slot

    MapSet.new(regions ++ pointed)
  end

  defp region_end(starts, base, count), do: Enum.find(starts, count, &(&1 > base))

  defp pointer_operands(op, _a, b)
       when op in [37, 38, 39, 40, 41, 42, 127, 128, 129, 68, 69, 71, 74, 75, 78, 79, 89, 91],
       do: [b]

  defp pointer_operands(op, a, _b) when op in 154..160 or op in [124, 125], do: [a]
  defp pointer_operands(_op, _a, _b), do: []

  defp pointer_target(value, count)
       when is_integer(value) and value > 0 and (value &&& 3) == 0 and div(value, 4) < count,
       do: div(value, 4)

  defp pointer_target(_value, _count), do: nil
end
