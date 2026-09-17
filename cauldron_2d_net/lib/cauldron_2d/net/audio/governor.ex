defmodule Cauldron2D.Net.Audio.Governor do
  @moduledoc """
  Sets the sessions' rate from the node's load under `:dynamic` music: every five
  seconds it reads how busy the schedulers were, drops the rate to 22 050 Hz once they
  pass 60%, and brings it back to the policy's once they fall under 30%, holding each
  for thirty seconds at least. Under any other music policy it leaves the rate alone.
  """

  use GenServer

  alias Cauldron2D.Net.Audio

  @every_ms 5_000
  @hold_ms 30_000
  @down 0.6
  @up 0.3
  @low 22_050

  @doc false
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc false
  def policy_changed do
    if Process.whereis(__MODULE__), do: GenServer.cast(__MODULE__, :policy_changed)
    :ok
  end

  @doc "How busy the schedulers were over the last five seconds, 0.0 to 1.0."
  @spec busy() :: float()
  def busy, do: GenServer.call(__MODULE__, :busy)

  @impl GenServer
  def init(_opts) do
    :erlang.system_flag(:scheduler_wall_time, true)
    Process.send_after(self(), :sample, @every_ms)
    {:ok, %{last: :erlang.statistics(:scheduler_wall_time), busy: 0.0, changed_at: 0}}
  end

  @impl GenServer
  def handle_call(:busy, _from, state), do: {:reply, state.busy, state}

  @impl GenServer
  def handle_cast(:policy_changed, state), do: {:noreply, %{state | changed_at: 0}}

  @impl GenServer
  def handle_info(:sample, state) do
    Process.send_after(self(), :sample, @every_ms)
    now = :erlang.statistics(:scheduler_wall_time)
    {:noreply, govern(%{state | last: now, busy: share(state.last, now)})}
  end

  defp share(last, now) do
    {active, total} =
      Enum.zip(Enum.sort(last), Enum.sort(now))
      |> Enum.reduce({0, 0}, fn {{_, a0, t0}, {_, a1, t1}}, {a, t} ->
        {a + (a1 - a0), t + (t1 - t0)}
      end)

    if total > 0, do: active / total, else: 0.0
  end

  defp govern(state) do
    policy = Audio.policy()
    held? = System.monotonic_time(:millisecond) - state.changed_at < @hold_ms

    cond do
      policy.music != :dynamic -> state
      held? -> state
      state.busy > @down and Audio.rate() > @low -> lowered(state, min(@low, policy.rate))
      state.busy < @up and Audio.rate() < policy.rate -> lowered(state, policy.rate)
      true -> state
    end
  end

  defp lowered(state, rate) do
    Audio.lower_rate(rate)
    %{state | changed_at: System.monotonic_time(:millisecond)}
  end
end
