defmodule Cauldron.Net.Voice.Calls do
  @moduledoc """
  Who has asked whom to talk, who is talking, and whose microphone is off, for the players whose
  browsers are on the voice channel (`Cauldron.Net.Voice.Channel`).

  Players are known by name. A player is present while at least one of their channel processes
  lives; the newest one carries their sound and the offers and answers that set a call up. Every
  change is sent to the channel processes of the players it concerns as
  `{:cauldron_voice, event, payload}`, an event the channel pushes to its browser as it is:

    * `"state"` — the player's `state/1`
    * `"connect"` — `%{with: name, offer: boolean}`: both have agreed, and the browser that has
      `offer: true` starts the call
    * `"ended"` — `%{with: name}`
    * `"declined"` — `%{by: name}`
    * `"unavailable"` — `%{name: name}`: the player asked is not present
    * `"mute"` — `%{muted: boolean}`

  The talking pairs and each player's state are kept in a table any process reads, so a channel
  checks a pair (`talking?/2`) and finds a player's sound process (`carrier/1`) without asking this
  process. The rules are those of `Cauldron.Net.Voice`.
  """

  use GenServer

  @table __MODULE__

  @type name :: String.t()
  @type state :: %{
          incoming: [name()],
          outgoing: [name()],
          talking: [name()],
          muted: boolean(),
          present: boolean()
        }

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_options), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Marks `name` present through the channel process `pid`, which becomes the one carrying their sound."
  @spec present(name(), pid()) :: :ok
  def present(name, pid), do: GenServer.call(__MODULE__, {:present, name, pid})

  @doc "Asks for a call from `from` to `to`."
  @spec call(name(), name()) :: :ok | {:error, :unavailable | :self}
  def call(from, to), do: GenServer.call(__MODULE__, {:call, from, to})

  @doc "`name` agrees to the call `caller` asked for."
  @spec accept(name(), name()) :: :ok | {:error, :not_asked}
  def accept(name, caller), do: GenServer.call(__MODULE__, {:accept, name, caller})

  @doc "`name` refuses the call `caller` asked for."
  @spec decline(name(), name()) :: :ok
  def decline(name, caller), do: GenServer.call(__MODULE__, {:decline, name, caller})

  @doc "Ends `name`'s call with `other`, or withdraws or refuses an unanswered one between them."
  @spec hang_up(name(), name()) :: :ok
  def hang_up(name, other), do: GenServer.call(__MODULE__, {:hang_up, name, other})

  @doc "Turns `name`'s microphone off (`true`) or on (`false`)."
  @spec mute(name(), boolean()) :: :ok
  def mute(name, muted), do: GenServer.call(__MODULE__, {:mute, name, muted})

  @doc "`name`'s calls: who is asking them, whom they are asking, whom they talk to, and whether their microphone is off."
  @spec state(name()) :: state()
  def state(name) do
    case :ets.lookup(@table, {:state, name}) do
      [{_key, state}] -> state
      [] -> blank()
    end
  end

  @doc "Whether `a` and `b` are talking."
  @spec talking?(name(), name()) :: boolean()
  def talking?(a, b), do: :ets.member(@table, {:pair, pair(a, b)})

  @doc "The channel process carrying `name`'s sound, or `nil` when they are not present."
  @spec carrier(name()) :: pid() | nil
  def carrier(name) do
    case :ets.lookup(@table, {:carrier, name}) do
      [{_key, pid}] -> pid
      [] -> nil
    end
  end

  @impl GenServer
  def init(:ok) do
    :ets.new(@table, [:named_table, :protected, read_concurrency: true])
    {:ok, %{asked: MapSet.new(), talking: MapSet.new(), muted: MapSet.new(), present: %{}}}
  end

  @impl GenServer
  def handle_call({:present, name, pid}, _from, calls) do
    Process.monitor(pid)
    calls = %{calls | present: Map.update(calls.present, name, [pid], &[pid | &1])}
    :ets.insert(@table, {{:carrier, name}, pid})
    {:reply, :ok, publish(calls, [name])}
  end

  def handle_call({:call, name, name}, _from, calls), do: {:reply, {:error, :self}, calls}

  def handle_call({:call, from, to}, _from, calls) do
    cond do
      not Map.has_key?(calls.present, to) ->
        tell(calls, from, "unavailable", %{name: to})
        {:reply, {:error, :unavailable}, calls}

      MapSet.member?(calls.talking, pair(from, to)) ->
        {:reply, :ok, calls}

      MapSet.member?(calls.asked, {to, from}) ->
        {:reply, :ok, connect(calls, from, to)}

      true ->
        {:reply, :ok, publish(%{calls | asked: MapSet.put(calls.asked, {from, to})}, [from, to])}
    end
  end

  def handle_call({:accept, name, caller}, _from, calls) do
    if MapSet.member?(calls.asked, {caller, name}),
      do: {:reply, :ok, connect(calls, name, caller)},
      else: {:reply, {:error, :not_asked}, calls}
  end

  def handle_call({:decline, name, caller}, _from, calls) do
    if MapSet.member?(calls.asked, {caller, name}) do
      tell(calls, caller, "declined", %{by: name})

      {:reply, :ok,
       publish(%{calls | asked: MapSet.delete(calls.asked, {caller, name})}, [name, caller])}
    else
      {:reply, :ok, calls}
    end
  end

  def handle_call({:hang_up, name, other}, _from, calls),
    do: {:reply, :ok, part(calls, name, other)}

  def handle_call({:mute, name, muted}, _from, calls) do
    muted_set =
      if muted, do: MapSet.put(calls.muted, name), else: MapSet.delete(calls.muted, name)

    tell(calls, name, "mute", %{muted: muted})
    {:reply, :ok, publish(%{calls | muted: muted_set}, [name])}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, calls) do
    case Enum.find(calls.present, fn {_name, pids} -> pid in pids end) do
      {name, [^pid]} -> {:noreply, gone(calls, name)}
      {name, pids} -> {:noreply, still_present(calls, name, List.delete(pids, pid))}
      nil -> {:noreply, calls}
    end
  end

  defp still_present(calls, name, [newest | _older] = pids) do
    :ets.insert(@table, {{:carrier, name}, newest})
    %{calls | present: Map.put(calls.present, name, pids)}
  end

  defp gone(calls, name) do
    others =
      for {a, b} <- MapSet.to_list(calls.talking) ++ MapSet.to_list(calls.asked),
          name in [a, b],
          do: if(a == name, do: b, else: a)

    calls = Enum.reduce(Enum.uniq(others), calls, &part(&2, name, &1))
    :ets.delete(@table, {:carrier, name})
    :ets.delete(@table, {:state, name})
    %{calls | present: Map.delete(calls.present, name), muted: MapSet.delete(calls.muted, name)}
  end

  defp connect(calls, name, caller) do
    asked = calls.asked |> MapSet.delete({caller, name}) |> MapSet.delete({name, caller})
    :ets.insert(@table, {{:pair, pair(name, caller)}})
    calls = %{calls | asked: asked, talking: MapSet.put(calls.talking, pair(name, caller))}
    calls = publish(calls, [name, caller])
    tell_carrier(caller, "connect", %{with: name, offer: true})
    tell_carrier(name, "connect", %{with: caller, offer: false})
    calls
  end

  defp part(calls, name, other) do
    was_talking = MapSet.member?(calls.talking, pair(name, other))
    :ets.delete(@table, {:pair, pair(name, other)})

    calls = %{
      calls
      | talking: MapSet.delete(calls.talking, pair(name, other)),
        asked: calls.asked |> MapSet.delete({name, other}) |> MapSet.delete({other, name})
    }

    if was_talking do
      tell_carrier(name, "ended", %{with: other})
      tell_carrier(other, "ended", %{with: name})
    end

    publish(calls, [name, other])
  end

  defp publish(calls, names) do
    for name <- Enum.uniq(names), Map.has_key?(calls.present, name) do
      state = state_of(calls, name)
      :ets.insert(@table, {{:state, name}, state})
      tell(calls, name, "state", state)
    end

    calls
  end

  defp state_of(calls, name) do
    %{
      incoming: for({from, ^name} <- MapSet.to_list(calls.asked), do: from) |> Enum.sort(),
      outgoing: for({^name, to} <- MapSet.to_list(calls.asked), do: to) |> Enum.sort(),
      talking:
        for(
          {a, b} <- MapSet.to_list(calls.talking),
          name in [a, b],
          do: if(a == name, do: b, else: a)
        )
        |> Enum.sort(),
      muted: MapSet.member?(calls.muted, name),
      present: true
    }
  end

  defp blank, do: %{incoming: [], outgoing: [], talking: [], muted: false, present: false}

  defp tell(calls, name, event, payload) do
    for pid <- Map.get(calls.present, name, []), do: send(pid, {:cauldron_voice, event, payload})
    :ok
  end

  defp tell_carrier(name, event, payload) do
    if pid = carrier(name), do: send(pid, {:cauldron_voice, event, payload})
    :ok
  end

  defp pair(a, b) when a <= b, do: {a, b}
  defp pair(a, b), do: {b, a}
end
