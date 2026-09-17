defmodule Cauldron2D.Arenas.Sweeper do
  @moduledoc """
  Stops arenas that have had no human in them for a while; they start again on the
  next use of their world's name. Each sweep also seats the children a running arena
  is short of (`Cauldron2D.Arenas.reseat/1`).

      Cauldron2D.Arenas.Sweeper.start_link(idle_after: 120, every: 30)

  ## Options

    * `:idle_after` — seconds without a human before an arena is stopped. Default `120`
    * `:every` — seconds between sweeps, or `:never` to sweep only on `sweep/1`. Default `30`
    * `:name` — the process name. Default the module, `nil` for none
  """

  use GenServer

  alias Cauldron2D.Arenas

  @doc "Start the sweeper."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    if name,
      do: GenServer.start_link(__MODULE__, opts, name: name),
      else: GenServer.start_link(__MODULE__, opts)
  end

  @doc "Sweep now: seat missing children, note which running arenas are without humans and stop those idle long enough."
  @spec sweep(GenServer.server()) :: :ok
  def sweep(sweeper \\ __MODULE__), do: GenServer.call(sweeper, :sweep)

  @impl GenServer
  def init(opts) do
    state = %{
      idle_after: Keyword.get(opts, :idle_after, 120),
      every: Keyword.get(opts, :every, 30),
      idle_since: %{}
    }

    schedule(state)
    {:ok, state}
  end

  @impl GenServer
  def handle_call(:sweep, _from, state), do: {:reply, :ok, run(state)}

  @impl GenServer
  def handle_info(:sweep, state) do
    state = run(state)
    schedule(state)
    {:noreply, state}
  end

  defp schedule(%{every: :never}), do: :ok
  defp schedule(%{every: seconds}), do: Process.send_after(self(), :sweep, seconds * 1_000)

  defp run(state) do
    now = System.monotonic_time(:second)
    running = Arenas.running_ids()
    Enum.each(running, &Arenas.reseat/1)

    idle =
      for id <- running,
          Arenas.humans(id) == [],
          into: %{},
          do: {id, Map.get(state.idle_since, id, now)}

    {stale, kept} = Enum.split_with(idle, fn {_id, since} -> now - since >= state.idle_after end)
    for {id, _since} <- stale, do: Arenas.stop(id)
    %{state | idle_since: Map.new(kept)}
  end
end
