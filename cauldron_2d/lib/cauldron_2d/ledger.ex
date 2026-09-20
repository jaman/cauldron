defmodule Cauldron2D.Ledger do
  @moduledoc """
  Every player's results, kept on disk, and the boards made from them.

      {:ok, ledger} = Cauldron2D.Ledger.start_link(path: Cauldron2D.Paths.data(:my_game, "ledger.dets"), metrics: [kills: {:sum, :kills}, ratio: {:ratio, :kills, :deaths}, wins: {:count, :won?}])
      Cauldron2D.Ledger.record(ledger, "Pit", %{id: "alice", name: "alice", kills: 3, deaths: 1, won?: true})
      Cauldron2D.Ledger.board(ledger, :week, :kills, arena: "Pit")

  A result is a map with the player's account as `:id` (their `:name` when there is no
  id), the name they played under as `:name`, and whatever fields the metrics read. A
  result whose id is `{:robot, n}` is not kept. `Cauldron2D.Ledger.Recorder` takes
  them from a world's events.

  ## Metrics

  The game declares its metrics as a keyword list, each one of:

    * `{:sum, field}` — the field summed over the rounds
    * `{:max, field}` — the field's largest value
    * `{:count, field}` — how many rounds had the field true
    * `{:ratio, field, by}` — the sum of `field` over the sum of `by`, to two places;
      the sum of `field` alone when `by` sums to zero
    * a function of the rounds returning a number

  A board is the accounts of a period — `:day` (since midnight UTC), `:week` (the last
  seven days) or `:all` — ranked by one metric, each with every metric's value, the
  rounds counted and the name last played under, twenty at most. Boards are computed from
  the table and kept for ten seconds.

  ## The file

  The file belongs to one operating system process at a time, held through
  `Cauldron2D.Ledger.Lock`. Starting a ledger on a held file fails with
  `{:error, {:held, pid}}`, or with `held: :idle` starts one that keeps nothing: its
  boards are empty, `record/4` and `forget/2` answer `{:error, {:held, pid}}`, and
  `access/1` says `{:held, pid}`. A DETS failure stops the ledger, and a restart reopens
  the file repaired.
  """

  use GenServer

  alias Cauldron2D.Ledger.Lock

  @type period :: :day | :week | :all
  @type metric :: atom()
  @type entry :: %{
          name: String.t(),
          account: term(),
          value: number(),
          rounds: pos_integer(),
          values: %{metric() => number()}
        }

  @top 20
  @keep_ms 10_000

  @doc """
  Start the ledger.

  ## Options

    * `:path` — the DETS file. Required
    * `:metrics` — the metrics, as the module documentation describes. Required
    * `:name` — the registered name; default the module, `nil` for none
    * `:held` — what to do when another process holds the file: `:stop` (default) or `:idle`
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  @doc "Keep a result from `arena`, taken `at` (default now)."
  @spec record(GenServer.server(), String.t(), map(), DateTime.t()) :: :ok | {:error, term()}
  def record(ledger, arena, row, at \\ DateTime.utc_now())
  def record(_ledger, _arena, %{id: {:robot, _}}, _at), do: :ok
  def record(ledger, arena, row, at), do: GenServer.call(ledger, {:record, arena, row, at})

  @doc "Drop every result `keep_out?` is true of — a function of the row as it was recorded, with its `:arena` and `:at` — and say how many went."
  @spec forget(GenServer.server(), (map() -> boolean())) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def forget(ledger, keep_out?) when is_function(keep_out?, 1),
    do: GenServer.call(ledger, {:forget, keep_out?})

  @doc "How many results are kept."
  @spec count(GenServer.server()) :: non_neg_integer()
  def count(ledger), do: GenServer.call(ledger, :count)

  @doc "The board of `period` by `metric`: the top #{@top}, or `top: n` of them, or every account with `top: :all`; `arena:` narrows it to one arena."
  @spec board(GenServer.server(), period(), metric(), keyword()) :: [entry()]
  def board(ledger, period, metric, opts \\ []) do
    GenServer.call(
      ledger,
      {:board, period, metric, Keyword.get(opts, :arena), Keyword.get(opts, :top, @top)}
    )
  end

  @doc "The metrics the ledger was started with, in order."
  @spec metrics(GenServer.server()) :: [metric()]
  def metrics(ledger), do: GenServer.call(ledger, :metrics)

  @doc "Whether the ledger holds its file: `:read_write`, or `{:held, pid}` naming the operating system process that does."
  @spec access(GenServer.server()) :: :read_write | {:held, pos_integer()}
  def access(ledger), do: GenServer.call(ledger, :access)

  @doc "The operating system process holding the file at `path`, or nil when it is free."
  @spec holder(Path.t()) :: pos_integer() | nil
  def holder(path), do: Lock.holder(path)

  @impl GenServer
  def init(opts) do
    path = Keyword.fetch!(opts, :path)
    File.mkdir_p!(Path.dirname(path))

    state = %{
      path: path,
      table: nil,
      held: nil,
      boards: %{},
      metrics: Keyword.fetch!(opts, :metrics)
    }

    case {Lock.take(path), Keyword.get(opts, :held, :stop)} do
      {:ok, _held} -> open(state)
      {{:error, held}, :idle} -> {:ok, %{state | held: held}}
      {{:error, held}, :stop} -> {:stop, held}
    end
  end

  @impl GenServer
  def handle_call(:metrics, _from, state), do: {:reply, Keyword.keys(state.metrics), state}

  def handle_call(request, _from, %{held: held} = state) when is_tuple(held) do
    {:reply, held_reply(request, held), state}
  end

  def handle_call({:record, arena, row, at}, _from, state) do
    key = {DateTime.to_unix(at, :microsecond), account(row)}
    entry = {key, Map.merge(row, %{arena: arena, at: DateTime.to_unix(at)})}

    with :ok <- :dets.insert(state.table, entry),
         :ok <- :dets.sync(state.table) do
      {:reply, :ok, %{state | boards: %{}}}
    else
      {:error, reason} -> {:stop, reason, {:error, reason}, state}
    end
  end

  def handle_call({:forget, keep_out?}, _from, state) do
    with {:ok, keys} <- keys_to_forget(state.table, keep_out?),
         :ok <- delete_all(state.table, keys),
         :ok <- :dets.sync(state.table) do
      {:reply, {:ok, length(keys)}, %{state | boards: %{}}}
    else
      {:error, reason} -> {:stop, reason, {:error, reason}, state}
    end
  end

  def handle_call(:count, _from, state), do: {:reply, :dets.info(state.table, :size), state}
  def handle_call(:access, _from, state), do: {:reply, :read_write, state}

  def handle_call({:board, period, metric, arena, top}, _from, state) do
    key = {period, metric, arena, top}
    now = System.monotonic_time(:millisecond)

    case Map.get(state.boards, key) do
      {board, since} when now - since < @keep_ms ->
        {:reply, board, state}

      _stale ->
        board = compute(state, period, metric, arena, top)
        {:reply, board, %{state | boards: Map.put(state.boards, key, {board, now})}}
    end
  end

  @impl GenServer
  def terminate(_reason, %{held: nil} = state) do
    :dets.close(state.table)
    Lock.release(state.path)
    :ok
  end

  def terminate(_reason, _idle), do: :ok

  defp open(state) do
    case :dets.open_file(:"cauldron_ledger_#{:erlang.unique_integer([:positive])}",
           file: String.to_charlist(state.path),
           type: :set
         ) do
      {:ok, table} -> {:ok, %{state | table: table}}
      {:error, reason} -> {:stop, reason}
    end
  end

  defp held_reply({:record, _arena, _row, _at}, held), do: {:error, held}
  defp held_reply({:forget, _keep_out?}, held), do: {:error, held}
  defp held_reply({:board, _period, _metric, _arena, _top}, _held), do: []
  defp held_reply(:count, _held), do: 0
  defp held_reply(:access, held), do: held

  defp keys_to_forget(table, keep_out?) do
    case :dets.foldl(&key_if(&1, &2, keep_out?), [], table) do
      {:error, reason} -> {:error, reason}
      keys -> {:ok, keys}
    end
  end

  defp key_if({key, row}, keys, keep_out?), do: if(keep_out?.(row), do: [key | keys], else: keys)

  defp delete_all(table, keys) do
    Enum.find_value(keys, :ok, fn key ->
      case :dets.delete(table, key) do
        :ok -> nil
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp compute(state, period, metric, arena, top) do
    since = since(period)

    fn {_key, row}, acc ->
      if row.at >= since and (arena == nil or row.arena == arena), do: [row | acc], else: acc
    end
    |> :dets.foldl([], state.table)
    |> Enum.group_by(&account/1)
    |> Enum.map(fn {account, rows} -> entry(account, rows, metric, state.metrics) end)
    |> Enum.sort_by(&{-&1.value, &1.name})
    |> cut(top)
  end

  defp cut(entries, :all), do: entries
  defp cut(entries, top), do: Enum.take(entries, top)

  defp account(%{id: id}), do: id
  defp account(%{name: name}), do: name

  defp entry(account, rows, metric, metrics) do
    values = Map.new(metrics, fn {name, spec} -> {name, measure(spec, rows)} end)

    %{
      name: rows |> Enum.max_by(& &1.at) |> Map.get(:name),
      account: account,
      value: Map.fetch!(values, metric),
      rounds: length(rows),
      values: values
    }
  end

  defp measure({:sum, field}, rows), do: rows |> Enum.map(&Map.get(&1, field, 0)) |> Enum.sum()
  defp measure({:max, field}, rows), do: rows |> Enum.map(&Map.get(&1, field, 0)) |> Enum.max()
  defp measure({:count, field}, rows), do: Enum.count(rows, &Map.get(&1, field, false))

  defp measure({:ratio, field, by}, rows) do
    total = measure({:sum, field}, rows)

    case measure({:sum, by}, rows) do
      0 -> total / 1
      divisor -> Float.round(total / divisor, 2)
    end
  end

  defp measure(fun, rows) when is_function(fun, 1), do: fun.(rows)

  defp since(:all), do: 0
  defp since(:week), do: System.os_time(:second) - 7 * 86_400

  defp since(:day),
    do:
      DateTime.utc_now()
      |> DateTime.to_date()
      |> DateTime.new!(~T[00:00:00])
      |> DateTime.to_unix()
end
