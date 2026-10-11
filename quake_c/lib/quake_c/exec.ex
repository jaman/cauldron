defmodule QuakeC.Exec do
  @moduledoc """
  Runs QuakeC functions, compiled to Elixir (`QuakeC.Compiler`) the first time a program
  runs on this node.

  The host is any map with the program memory under `:qc`; builtins are called as
  `builtins.call(host, builtin, argument_count)` and return the host, `builtin` being the
  builtin's number, or its name for a function the program declares as builtin `#0`
  (bound by name). A builtin may run QuakeC itself (a touch during a move, say) by
  calling `call/4` again, or stop every running function with `abort/1`.

      host = QuakeC.Exec.call(host, function_index, MyGame.Builtins)
      host = QuakeC.Exec.call(host, function_index, MyGame.Builtins, budget: 10_000_000)

  ## Options

    * `:budget` — how many statements one call may run before it is taken for a runaway
      loop, default 100 000
    * `:trace` — a function given the name of every QuakeC function entered, default none
    * `:before` — a function of the host returning the host, run before each call starts
      (nested calls from builtins included), default none

  A program that runs past its budget, calls a null function or an unknown builtin, or
  uses an instruction this machine lacks raises `QuakeC.Exec.Error`.
  """

  alias QuakeC.Compiler.Runtime

  @parameter_slots Enum.to_list(4..27)
  @depth {__MODULE__, :depth}
  @abort {__MODULE__, :abort}

  defmodule Error do
    @moduledoc "A QuakeC program went wrong while running."
    defexception [:message]
  end

  @doc "Run function `index` to its end and return the host."
  @spec call(map(), non_neg_integer(), module(), keyword()) :: map()
  def call(host, index, builtins, opts \\ [])

  def call(_host, index, _builtins, _opts) when index in [0, nil],
    do: raise(Error, "a null function was called")

  def call(%{qc: _} = host, index, builtins, opts) do
    depth = Process.get(@depth, 0)
    Process.put(@depth, depth + 1)

    try do
      run(host, index, builtins, opts)
    catch
      :throw, {@abort, aborted} when depth == 0 -> aborted
    after
      Process.put(@depth, depth)
    end
  end

  @doc """
  Stop every QuakeC function running in this process, as FTE's `AbortStack`: the
  outermost `call/4` returns `host` as it stands. Called from a builtin.
  """
  @spec abort(map()) :: no_return()
  def abort(host), do: throw({@abort, host})

  defp run(host, index, builtins, opts) do
    %{qc: qc} = host = prepare(host, Keyword.get(opts, :before))
    dispatch = QuakeC.Compiler.load(qc.progs)
    context = {builtins, Keyword.get(opts, :trace)}
    budget = Keyword.get(opts, :budget, 100_000)
    args = Runtime.args(qc, 8)

    {host, _budget, returned, handed} =
      dispatch.call_with_args(index, 8, host, context, budget, args, @parameter_slots)

    qc = Runtime.put_returned(host.qc, returned)
    %{host | qc: if(handed == args, do: qc, else: Runtime.put_args(qc, handed))}
  end

  @doc "Run function `name`; a name the program lacks does nothing."
  @spec call_named(map(), String.t(), module(), keyword()) :: map()
  def call_named(%{qc: qc} = host, name, builtins, opts \\ []) do
    case QuakeC.Progs.function(qc.progs, name) do
      nil -> host
      index -> call(host, index, builtins, opts)
    end
  end

  defp prepare(host, nil), do: host
  defp prepare(host, before), do: before.(host)
end
