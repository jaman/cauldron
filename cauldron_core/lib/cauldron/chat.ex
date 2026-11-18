defmodule Cauldron.Chat do
  @moduledoc """
  Chat rooms for a served game: one process, any number of rooms, the last messages kept.
  The `:cauldron_core` application starts it; every client — terminal, desktop, browser —
  joins its rooms only for a game whose `chat?/0` is true.

      Cauldron.Chat.join(:lobby)
      Cauldron.Chat.say(:lobby, "alice", "hello")

  A process that joined a room receives `{:chat, room, %{from: name, text: text, at: ms}}`
  for every message said in it, and stops receiving when it leaves or exits.
  `history/1` is the last `100` messages, oldest first.

  Every client names the rooms alike: `:lobby` for the lobby, and `{:world, id}` for a
  world's players, `id` the world's id from `c:Cauldron.Client.Game.worlds/1` as a
  string, so a terminal, a desktop and a browser in one world talk in one room.
  """

  use GenServer

  @keep 100

  @type message :: %{from: String.t(), text: String.t(), at: integer()}

  @doc "Start the chat server registered under this module, linked, for a supervisor."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @doc "Receive `room`'s messages in the calling process."
  @spec join(term()) :: :ok
  def join(room), do: GenServer.call(__MODULE__, {:join, room, self()})

  @doc "Stop receiving `room`'s messages."
  @spec leave(term()) :: :ok
  def leave(room), do: GenServer.call(__MODULE__, {:leave, room, self()})

  @doc "Say `text` in `room` as `from`."
  @spec say(term(), String.t(), String.t()) :: :ok
  def say(room, from, text), do: GenServer.cast(__MODULE__, {:say, room, from, text})

  @doc "The last messages in `room`, oldest first."
  @spec history(term()) :: [message()]
  def history(room), do: GenServer.call(__MODULE__, {:history, room})

  @impl GenServer
  def init(_opts), do: {:ok, %{rooms: %{}, members: %{}}}

  @impl GenServer
  def handle_call({:join, room, pid}, _from, state) do
    Process.monitor(pid)
    members = Map.update(state.members, room, MapSet.new([pid]), &MapSet.put(&1, pid))
    {:reply, :ok, %{state | members: members}}
  end

  def handle_call({:leave, room, pid}, _from, state) do
    {:reply, :ok,
     %{state | members: Map.update(state.members, room, MapSet.new(), &MapSet.delete(&1, pid))}}
  end

  def handle_call({:history, room}, _from, state) do
    {:reply, state.rooms |> Map.get(room, []) |> Enum.reverse(), state}
  end

  @impl GenServer
  def handle_cast({:say, room, from, text}, state) do
    message = %{from: from, text: text, at: System.system_time(:millisecond)}
    kept = [message | Map.get(state.rooms, room, [])] |> Enum.take(@keep)

    for pid <- Map.get(state.members, room, []), do: send(pid, {:chat, room, message})

    {:noreply, %{state | rooms: Map.put(state.rooms, room, kept)}}
  end

  @impl GenServer
  def handle_info({:DOWN, _monitor, :process, pid, _reason}, state) do
    members = Map.new(state.members, fn {room, pids} -> {room, MapSet.delete(pids, pid)} end)
    {:noreply, %{state | members: members}}
  end
end
