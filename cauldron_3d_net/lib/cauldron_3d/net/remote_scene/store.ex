defmodule Cauldron3D.Net.RemoteScene.Store do
  @moduledoc """
  What a client has received of a server's 3D scene (`Cauldron3D.Net.RemoteScene`), kept
  in one process so a view carries only the store and a batch number: the scene so far
  (`Cauldron3D.Scene.Host.Record`) and the latest batches, each numbered.

  `since/2` answers a renderer with the batches after the last one it drew, or, for a
  renderer that drew none or is further behind than the batches kept, the whole scene.
  """

  use GenServer

  alias Cauldron3D.Scene.Host.Record
  alias Cauldron3D.Scene.Stream

  @kept 240

  @doc "Start a store linked to the caller."
  @spec start_link() :: {:ok, pid()}
  def start_link, do: GenServer.start_link(__MODULE__, nil)

  @doc "Keep one more batch of changes; it is numbered one above the last."
  @spec add(pid(), [Stream.change()]) :: :ok
  def add(store, changes), do: GenServer.cast(store, {:add, changes})

  @doc """
  The changes a renderer that drew up to batch `seen` (`nil` for none) needs, and the
  batch they bring it to: `{:newer, changes, seq}` to apply on top of what it has, or
  `{:whole, changes, seq}` for a renderer starting again from nothing.
  """
  @spec since(pid(), non_neg_integer() | nil) ::
          {:newer | :whole, [Stream.change()], non_neg_integer()}
  def since(store, seen), do: GenServer.call(store, {:since, seen})

  @impl GenServer
  def init(nil), do: {:ok, %{record: Record.new(), log: :queue.new(), size: 0, seq: 0, base: 0}}

  @impl GenServer
  def handle_cast({:add, changes}, state) do
    seq = state.seq + 1

    {:noreply,
     compacted(%{
       state
       | log: :queue.in({seq, changes}, state.log),
         size: state.size + 1,
         seq: seq
     })}
  end

  @impl GenServer
  def handle_call({:since, seen}, _from, state) when is_integer(seen) and seen >= state.base do
    newer =
      for {batch, changes} <- :queue.to_list(state.log),
          batch > seen,
          change <- changes,
          do: change

    {:reply, {:newer, newer, state.seq}, state}
  end

  def handle_call({:since, _seen}, _from, state) do
    logged = for {_batch, changes} <- :queue.to_list(state.log), change <- changes, do: change
    {:reply, {:whole, Record.replay(state.record) ++ logged, state.seq}, state}
  end

  defp compacted(%{size: size} = state) when size <= @kept, do: state

  defp compacted(state) do
    {{:value, {batch, changes}}, log} = :queue.out(state.log)

    compacted(%{
      state
      | record: Record.apply_changes(state.record, changes),
        log: log,
        size: state.size - 1,
        base: batch
    })
  end
end
