defmodule QuakeC.Compiler.Emit do
  @moduledoc """
  One QuakeC function (`QuakeC.Compiler.Analysis.function/3`) as quoted Elixir: a public
  `f<index>(host, ctx, budget, args)` returning `{host, budget, {x, y, z}}`, and a private
  function per basic block that the function's jumps call. `args` is a tuple of the
  words of the call's arguments, three a parameter, as the parameter slots from 4 hold
  them; `{x, y, z}` is the returned value, as the return slots 1 to 3 hold it. A function
  that hands values back (`hands_back`) returns `{host, budget, {x, y, z}, handed}`,
  `handed` the 24 parameter slots as it left them. A call after which argument slots are
  read goes through `dispatch.call_with_args/7`, which also gives those argument slots as
  the call left them.

  `host` is the caller's map holding the program memory under `:qc`; `ctx` is
  `{builtins, trace}`; `budget` is how many more statements may run before the call is
  taken for a runaway loop. Slots the analysis gave to variables live in variables named
  `v<slot>`; constants are written in as literals; every other slot is read and written in
  the memory. A function in `:memory` mode saves its locals on entry and restores them on
  return, as a QuakeC machine does. Calls go through the dispatch
  module, `dispatch.call(index, argc, host, ctx, budget, args)`, which returns the same.
  """

  alias QuakeC.Compiler.{Analysis, Ops, Runtime}

  @runtime Runtime

  @doc "The quoted definitions of function `facts`, calling through `dispatch`, with the program's `constants` and entity size `size` (fields per entity)."
  @spec function(Analysis.function_facts(), module(), map(), pos_integer()) :: [Macro.t()]
  def function(facts, dispatch, constants, size) do
    blocks = blocks(facts)

    env = %{
      vars: MapSet.new(facts.vars),
      constants: constants,
      dispatch: dispatch,
      facts: facts,
      memory?: facts.mode == :memory,
      starts: MapSet.new(blocks, fn [{at, _} | _] -> at end),
      size: size
    }

    [entry(facts, env) | Enum.map(blocks, &block(&1, env))]
  end

  defp blocks(facts) do
    facts.statements
    |> Enum.chunk_while(
      [],
      fn {at, _} = statement, acc ->
        cond do
          acc == [] -> {:cont, [statement]}
          MapSet.member?(facts.leaders, at) -> {:cont, Enum.reverse(acc), [statement]}
          true -> {:cont, [statement | acc]}
        end
      end,
      fn
        [] -> {:cont, []}
        acc -> {:cont, Enum.reverse(acc), []}
      end
    )
    |> Enum.flat_map(&split_at_ends/1)
  end

  defp split_at_ends(statements) do
    statements
    |> Enum.chunk_while(
      [],
      fn {_at, statement} = item, acc ->
        if Analysis.ends_block?(statement),
          do: {:cont, Enum.reverse([item | acc]), []},
          else: {:cont, [item | acc]}
      end,
      fn
        [] -> {:cont, []}
        acc -> {:cont, Enum.reverse(acc), []}
      end
    )
  end

  defp entry(facts, env) do
    name = :"f#{facts.index}"
    first = block_name(facts.index, facts.statements |> hd() |> elem(0))

    setup =
      if env.memory?,
        do: call_entry(facts) ++ memory_entry(facts),
        else: var_entry(facts)

    quote generated: true do
      def unquote(name)(host, ctx, budget, args) do
        qc = host.qc
        sw = nil
        unquote_splicing(setup)
        unquote(first)(unquote_splicing(args(env)))
      end
    end
  end

  defp var_entry(facts) do
    from_parms =
      for {{slot, size}, n} <- Enum.with_index(facts.params),
          i <- 0..(size - 1),
          into: %{},
          do: {slot + i, 4 + 3 * n + i}

    for slot <- facts.vars do
      cond do
        slot in 1..27 ->
          call_slot(slot, facts)

        Map.has_key?(from_parms, slot) ->
          quote generated: true,
                do: unquote(var(slot)) = unquote(arg(Map.fetch!(from_parms, slot) - 4))

        MapSet.member?(facts.live, slot) ->
          quote generated: true,
                do: unquote(var(slot)) = unquote(@runtime).global(qc, unquote(slot))

        true ->
          quote generated: true, do: unquote(var(slot)) = 0
      end
    end
  end

  defp call_entry(facts), do: Enum.map(facts.calls, &call_slot(&1, facts))

  defp call_slot(slot, facts) do
    if slot >= 4 and (facts.hands_back or MapSet.member?(facts.live, slot)),
      do: quote(generated: true, do: unquote(var(slot)) = unquote(arg(slot - 4))),
      else: quote(generated: true, do: unquote(var(slot)) = 0)
  end

  defp arg(index) do
    quote generated: true do
      if tuple_size(args) > unquote(index), do: elem(args, unquote(index)), else: 0
    end
  end

  defp memory_entry(facts) do
    start = facts.parm_start
    count = facts.locals

    copies =
      for {{slot, size}, n} <- Enum.with_index(facts.params), i <- 0..(size - 1) do
        quote generated: true,
              do:
                qc =
                  unquote(@runtime).put(
                    qc,
                    unquote(slot + i),
                    unquote(arg(3 * n + i))
                  )
      end

    [
      quote generated: true do
        saved =
          for i <- 0..unquote(count - 1)//1, do: unquote(@runtime).global(qc, unquote(start) + i)
      end
      | copies
    ]
  end

  defp args(env) do
    base = quote(generated: true, do: [host, qc, ctx, budget, sw])
    saved = if env.memory?, do: [quote(generated: true, do: saved)], else: []
    base ++ saved ++ Enum.map(Enum.sort(env.vars), &var/1)
  end

  defp block([{first, _} | _] = statements, env) do
    name = block_name(env.facts.index, first)
    count = length(statements)
    {last_at, last} = List.last(statements)
    body = statements |> Enum.drop(-1) |> Enum.flat_map(fn {at, s} -> statement(at, s, env) end)
    ending = ending(last_at, last, env)
    fname = env.facts.name

    quote generated: true do
      defp unquote(name)(unquote_splicing(args(env))) do
        if budget < unquote(count),
          do: raise(QuakeC.Exec.Error, "runaway loop in " <> unquote(fname))

        budget = budget - unquote(count)
        unquote_splicing(body)
        unquote(ending)
      end
    end
  end

  defp block_name(index, at), do: :"f#{index}_b#{at}"

  defp goto(at, env) do
    if MapSet.member?(env.starts, at) do
      quote(
        generated: true,
        do: unquote(block_name(env.facts.index, at))(unquote_splicing(args(env)))
      )
    else
      message = env.facts.name <> " ran past the end of the program"
      quote(generated: true, do: raise(QuakeC.Exec.Error, unquote(message)))
    end
  end

  defp ending(_at, {op, a, _, _}, env) when op in [0, 43] do
    restore = if env.memory?, do: [restore(env.facts.parm_start)], else: []

    handed =
      if env.facts.hands_back,
        do: [{:{}, [], for(slot <- 4..27, do: read(slot, env))}],
        else: []

    quote generated: true do
      returned = {unquote(read(a, env)), unquote(read(a + 1, env)), unquote(read(a + 2, env))}
      unquote_splicing(restore)
      {%{host | qc: qc}, budget, returned, unquote_splicing(handed)}
    end
  end

  defp ending(at, {61, a, _, _}, env), do: goto(at + a, env)

  defp ending(at, {op, a, b, _}, env) when op in [49, 50, 136, 137, 217, 218] do
    test = condition(op, read(a, env))

    quote generated: true do
      if unquote(test), do: unquote(goto(at + b, env)), else: unquote(goto(at + 1, env))
    end
  end

  defp ending(at, {op, a, b, _}, env) when op in [98, 99, 100, 101, 102, 215] do
    quote generated: true do
      sw =
        unquote(@runtime).switch(
          qc,
          unquote(op),
          unquote(read(a, env)),
          unquote(read(a + 1, env)),
          unquote(read(a + 2, env))
        )

      unquote(goto(at + b, env))
    end
  end

  defp ending(at, {103, a, b, _}, env) do
    quote generated: true do
      if unquote(@runtime).case?(
           qc,
           sw,
           unquote(read(a, env)),
           unquote(read(a + 1, env)),
           unquote(read(a + 2, env))
         ),
         do: unquote(goto(at + b, env)),
         else: unquote(goto(at + 1, env))
    end
  end

  defp ending(at, {104, a, b, c}, env) do
    quote generated: true do
      if unquote(@runtime).case_range?(sw, unquote(read(a, env)), unquote(read(b, env))),
        do: unquote(goto(at + c, env)),
        else: unquote(goto(at + 1, env))
    end
  end

  defp ending(at, statement, env) do
    quote generated: true do
      unquote_splicing(statement(at, statement, env))
      unquote(goto(at + 1, env))
    end
  end

  defp condition(49, value), do: truth(value)
  defp condition(50, value), do: quote(generated: true, do: not unquote(truth(value)))
  defp condition(217, value), do: truth(value)
  defp condition(218, value), do: quote(generated: true, do: not unquote(truth(value)))

  defp condition(136, value),
    do: quote(generated: true, do: not unquote(@runtime).text?(qc, unquote(value)))

  defp condition(137, value),
    do: quote(generated: true, do: unquote(@runtime).text?(qc, unquote(value)))

  defp restore(start) do
    quote generated: true do
      qc =
        saved
        |> Enum.with_index()
        |> Enum.reduce(qc, fn {value, i}, acc ->
          unquote(@runtime).put(acc, unquote(start) + i, value)
        end)
    end
  end

  defp statement(at, {op, a, _, _}, env) when op in 51..59, do: call(at, a, op - 51, [], env)

  defp statement(at, {op, a, b, c}, env) when op in 105..112 do
    copies = copy(b, 4, env) ++ if(op > 105, do: copy(c, 7, env), else: [])
    call(at, a, op - 104, copies, env)
  end

  defp statement(_at, {60, a, b, _}, env),
    do: [
      quote(
        generated: true,
        do: qc = unquote(@runtime).state(qc, unquote(read(a, env)), unquote(read(b, env)))
      )
    ]

  defp statement(_at, {87, a, b, _}, env),
    do: [
      quote(
        generated: true,
        do: qc = unquote(@runtime).think_time(qc, unquote(read(a, env)), unquote(read(b, env)))
      )
    ]

  defp statement(_at, {211, a, b, c}, env) do
    fname = env.facts.name

    [
      quote generated: true do
        value = unquote(read(a, env))
        index = if is_number(value), do: trunc(value), else: -1

        unless index >= unquote(c) and index < unquote(b) do
          require Logger

          Logger.warning(
            "QuakeC bounds check failed in " <>
              unquote(fname) <>
              ": " <> inspect(value) <> " is not in " <> unquote("#{c}..#{b - 1}")
          )
        end
      end
    ]
  end

  defp statement(_at, {op, a, b, c}, env), do: Ops.emit(op, a, b, c, env)

  defp copy(from, to, env), do: for(i <- 0..2, do: write(to + i, read(from + i, env), env))

  defp call(at, a, argc, copies, env) do
    dispatch = env.dispatch
    fname = env.facts.name
    kept = Map.get(env.facts.kept, at, [])
    arguments = {:{}, [], for(slot <- 4..(3 + 3 * argc)//1, do: read(slot, env))}

    invoke =
      if kept == [],
        do:
          quote(
            generated: true,
            do:
              {host, budget, {returned_x, returned_y, returned_z}} =
                unquote(dispatch).call(
                  callee,
                  unquote(argc),
                  %{host | qc: qc},
                  ctx,
                  budget,
                  unquote(arguments)
                )
          ),
        else:
          quote(
            generated: true,
            do:
              {host, budget, {returned_x, returned_y, returned_z}, handed} =
                unquote(dispatch).call_with_args(
                  callee,
                  unquote(argc),
                  %{host | qc: qc},
                  ctx,
                  budget,
                  unquote(arguments),
                  unquote(kept)
                )
          )

    handed_back =
      for {slot, at} <- Enum.with_index(kept),
          do: write(slot, quote(generated: true, do: elem(handed, unquote(at))), env)

    copies ++
      [
        quote generated: true do
          callee = unquote(convert(:int, read(a, env)))

          if callee == 0,
            do: raise(QuakeC.Exec.Error, unquote(fname) <> " called a null function")

          unquote(invoke)
          qc = host.qc
        end,
        write(1, quote(generated: true, do: returned_x), env),
        write(2, quote(generated: true, do: returned_y), env),
        write(3, quote(generated: true, do: returned_z), env)
      ] ++ handed_back
  end

  @doc "Code converting `value` by runtime rule `rule` (`:num`, `:int` or `:float`), done now when `value` is a number."
  @spec convert(:num | :int | :float, Macro.t()) :: Macro.t()
  def convert(rule, value) when is_number(value), do: apply(@runtime, rule, [value])

  def convert(:num, value) do
    quote generated: true do
      case unquote(value) do
        number when is_number(number) -> number
        _ -> 0
      end
    end
  end

  def convert(:int, value) do
    quote generated: true do
      case unquote(value) do
        integer when is_integer(integer) -> integer
        float when is_float(float) -> trunc(float)
        _ -> 0
      end
    end
  end

  def convert(:float, value) do
    quote generated: true do
      case unquote(value) do
        float when is_float(float) -> float
        integer when is_integer(integer) -> integer / 1
        _ -> 0.0
      end
    end
  end

  @doc "Code testing `value` as QuakeC tests a truth: any number but zero, any made string."
  @spec truth(Macro.t()) :: Macro.t()
  def truth(value) do
    quote generated: true do
      case unquote(value) do
        number when is_number(number) -> number != 0
        text when is_binary(text) -> true
        _ -> false
      end
    end
  end

  @doc "Code turning truth `value` into 1.0 or 0.0."
  @spec bool(Macro.t()) :: Macro.t()
  def bool(value), do: quote(generated: true, do: if(unquote(value), do: 1.0, else: 0.0))

  @doc "Code turning truth `value` into 1 or 0."
  @spec ibool(Macro.t()) :: Macro.t()
  def ibool(value), do: quote(generated: true, do: if(unquote(value), do: 1, else: 0))

  @doc "Code naming memory space `space` (`:globals` or `:fields`) of the program memory variable."
  @spec space(:globals | :fields) :: Macro.t()
  def space(space), do: {{:., [], [qc(), space]}, [no_parens: true, generated: true], []}

  @doc "The variable holding the program memory in compiled code."
  @spec qc() :: Macro.t()
  def qc, do: quote(generated: true, do: qc)

  @doc "The variable holding slot `slot`."
  @spec var(non_neg_integer()) :: Macro.t()
  def var(slot), do: {:"v#{slot}", [generated: true], nil}

  @doc "Code reading slot `slot`: its variable, its constant, or the memory."
  @spec read(integer(), map()) :: Macro.t()
  def read(slot, env) do
    cond do
      MapSet.member?(env.vars, slot) -> var(slot)
      Map.has_key?(env.constants, slot) -> Macro.escape(Map.fetch!(env.constants, slot))
      true -> QuakeC.Memory.get_code(space(:globals), slot)
    end
  end

  @doc "Code writing `value` to slot `slot`: into its variable, or into the memory."
  @spec write(integer(), Macro.t(), map()) :: Macro.t()
  def write(slot, value, env) do
    if MapSet.member?(env.vars, slot),
      do: quote(generated: true, do: unquote(var(slot)) = unquote(value)),
      else: quote(generated: true, do: qc = QuakeC.put_slot(qc, unquote(slot), unquote(value)))
  end
end
