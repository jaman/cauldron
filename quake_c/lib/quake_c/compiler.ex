defmodule QuakeC.Compiler do
  @moduledoc """
  Compiles a QuakeC program to Elixir: every function becomes a function of a generated
  module, and a dispatch module calls one by its index.

      dispatch = QuakeC.Compiler.load(progs)
      {host, budget, returned} =
        dispatch.call(function_index, argc, host, {builtins, trace}, budget, args)

  `args` is a tuple of the words of the arguments, three a parameter, and `returned` the
  three words of the return value. A builtin is called with the arguments in the
  parameter slots from 4, and its return value is read from the return slots 1 to 3.
  `dispatch.call_with_args/7` takes the same and a list of parameter slots, and returns
  `{host, budget, returned, kept}`, `kept` a tuple of those slots as the call left them:
  a builtin's parameter slots, the parameter slots of a function that hands values back,
  and otherwise the arguments as given.

  The generated modules are compiled in parallel, loaded, and their code kept in the cache
  directory (the application setting `:quake_c, :cache_dir`, by default the user cache
  directory's `quake_c`), named by the program's digest and the compiler's own code (older
  code for the same program is removed), so a program is compiled once. A program loaded
  once stays loaded for the life of the node.
  """

  alias QuakeC.Compiler.{Analysis, Emit, Ops, Runtime}
  alias QuakeC.Progs

  @chunk 120

  @doc "The dispatch module of `progs`, compiling and loading it when this node has not yet."
  @spec load(Progs.t()) :: module()
  def load(%Progs{} = progs) do
    key = key(progs)

    case :persistent_term.get({__MODULE__, key}, nil) do
      nil -> :global.trans({{__MODULE__, key}, self()}, fn -> load_locked(progs, key) end)
      dispatch -> dispatch
    end
  end

  defp load_locked(progs, key) do
    case :persistent_term.get({__MODULE__, key}, nil) do
      nil ->
        dispatch = dispatch_name(key)
        load_cached(key) || compile(progs, dispatch, key)
        :persistent_term.put({__MODULE__, key}, dispatch)
        dispatch

      dispatch ->
        dispatch
    end
  end

  defp key(progs) do
    digest =
      progs.digest ||
        :crypto.hash(
          :sha256,
          :erlang.term_to_binary({progs.statements, progs.functions, progs.globals})
        )

    code =
      for module <- [__MODULE__, Analysis, Emit, Ops, Runtime, QuakeC.Memory],
          do: module.module_info(:md5)

    hex(digest) <> "_" <> hex(:crypto.hash(:sha256, code))
  end

  defp hex(bytes), do: bytes |> Base.encode16(case: :lower) |> binary_part(0, 16)

  defp dispatch_name(key), do: Module.concat([QuakeC.Compiled, "P" <> key])

  defp cache_path(key) do
    dir = Application.get_env(:quake_c, :cache_dir) || :filename.basedir(:user_cache, "quake_c")
    Path.join(to_string(dir), key <> ".beams")
  end

  defp load_cached(key) do
    with {:ok, data} <- File.read(cache_path(key)),
         modules when is_list(modules) <- :erlang.binary_to_term(data) do
      Enum.each(modules, fn {module, beam} ->
        {:module, _} = :code.load_binary(module, ~c"quake_c", beam)
      end)

      true
    else
      _ -> nil
    end
  end

  defp compile(progs, dispatch, key) do
    program = Analysis.program(progs)

    functions =
      for index <- 0..(tuple_size(progs.functions) - 1)//1,
          elem(progs.functions, index).first > 0,
          do: index

    chunks = functions |> Enum.chunk_every(@chunk) |> Enum.with_index()

    homes =
      for {indexes, k} <- chunks,
          index <- indexes,
          into: %{},
          do: {index, Module.concat(dispatch, "C#{k}")}

    modules =
      [
        {dispatch, dispatcher(progs, homes)}
        | Enum.map(chunks, &chunk(progs, program, dispatch, &1))
      ]
      |> Task.async_stream(fn {module, ast} -> compile_module(module, ast) end,
        timeout: :infinity,
        ordered: false
      )
      |> Enum.flat_map(fn {:ok, compiled} -> compiled end)

    path = cache_path(key)
    File.mkdir_p!(Path.dirname(path))
    [program | _] = String.split(key, "_")

    path
    |> Path.dirname()
    |> Path.join(program <> "_*.beams")
    |> Path.wildcard()
    |> Enum.each(&File.rm/1)

    File.write!(path, :erlang.term_to_binary(modules))
  end

  defp chunk(progs, program, dispatch, {indexes, k}) do
    module = Module.concat(dispatch, "C#{k}")

    definitions =
      Enum.flat_map(indexes, fn index ->
        progs
        |> Analysis.function(index, program)
        |> Emit.function(dispatch, program.constants, progs.entity_fields)
      end)

    {module, quote(do: (unquote_splicing(definitions)))}
  end

  defp dispatcher(progs, homes) do
    functions =
      for index <- 1..(tuple_size(progs.functions) - 1)//1 do
        home = Map.get(homes, index)
        handed? = home != nil and Analysis.hands_back?(progs, index)
        {index, elem(progs.functions, index), home, handed?}
      end

    calls = Enum.map(functions, &call_clause/1)
    with_args = Enum.map(functions, &with_args_clause/1)

    quote(
      do: (unquote_splicing(calls ++ [fallback(:call)] ++ with_args ++ [with_args_fallback()]))
    )
  end

  defp fallback(name) do
    quote generated: true do
      def unquote(name)(index, _argc, _host, _ctx, _budget, _args),
        do: raise(QuakeC.Exec.Error, "there is no function #{inspect(index)}")
    end
  end

  defp with_args_fallback do
    quote generated: true do
      def call_with_args(index, _argc, _host, _ctx, _budget, _args, _slots),
        do: raise(QuakeC.Exec.Error, "there is no function #{inspect(index)}")
    end
  end

  defp call_clause({index, fun, nil, _handed?}) do
    quote generated: true do
      def call(unquote(index), argc, host, ctx, budget, args) do
        {host, budget} = unquote(builtin_call(fun))
        {host, budget, Runtime.returned(host.qc)}
      end
    end
  end

  defp call_clause({index, fun, home, true}) do
    quote generated: true do
      def call(unquote(index), _argc, host, ctx, budget, args) do
        {host, budget, returned, _handed} = unquote(compiled_call(index, fun, home))
        {host, budget, returned}
      end
    end
  end

  defp call_clause({index, fun, home, false}) do
    quote generated: true do
      def call(unquote(index), _argc, host, ctx, budget, args),
        do: unquote(compiled_call(index, fun, home))
    end
  end

  defp with_args_clause({index, fun, nil, _handed?}) do
    quote generated: true do
      def call_with_args(unquote(index), argc, host, ctx, budget, args, slots) do
        {host, budget} = unquote(builtin_call(fun))
        {host, budget, Runtime.returned(host.qc), Runtime.slots(host.qc, slots)}
      end
    end
  end

  defp with_args_clause({index, fun, home, true}) do
    quote generated: true do
      def call_with_args(unquote(index), _argc, host, ctx, budget, args, slots) do
        {host, budget, returned, handed} = unquote(compiled_call(index, fun, home))
        {host, budget, returned, Runtime.pick(handed, slots)}
      end
    end
  end

  defp with_args_clause({index, fun, home, false}) do
    quote generated: true do
      def call_with_args(unquote(index), _argc, host, ctx, budget, args, slots) do
        {host, budget, returned} = unquote(compiled_call(index, fun, home))
        {host, budget, returned, Runtime.pick(args, slots)}
      end
    end
  end

  defp builtin_call(fun) do
    name = fun.name
    builtin = if fun.first == 0, do: name, else: -fun.first

    quote generated: true do
      {builtins, trace} = ctx
      if trace, do: trace.(unquote(name))
      host = %{host | qc: Runtime.put_args(host.qc, args)}
      {builtins.call(host, unquote(builtin), argc), budget}
    end
  end

  defp compiled_call(index, fun, home) do
    name = fun.name
    entry = :"f#{index}"

    quote generated: true do
      {_builtins, trace} = ctx
      if trace, do: trace.(unquote(name))
      unquote(home).unquote(entry)(host, ctx, budget, args)
    end
  end

  defp compile_module(module, body) do
    ast =
      quote do
        defmodule unquote(module) do
          @moduledoc false
          unquote(body)
        end
      end

    Code.compile_quoted(ast, "quake_c")
  end
end
