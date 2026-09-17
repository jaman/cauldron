defmodule Cauldron2D.Ledger.Recorder do
  @moduledoc """
  One arena's scribe: subscribed to its world's events (`Cauldron2D.World.Events`), it
  puts every `{tag, row}` — `:result` unless told otherwise — in the ledger under the
  arena's name. It stops when the world does.

      Cauldron2D.Ledger.Recorder.start_link(world: world, arena: "Pit", ledger: Cauldron2D.Ledger)

  ## Options

    * `:world` — the world to record. Required
    * `:arena` — the name results are kept under. Required
    * `:ledger` — the ledger. Default `Cauldron2D.Ledger`
    * `:tag` — the events to keep. Default `:result`
    * `:on_result` — a function given each row after it is kept. Default none
  """

  use GenServer

  alias Cauldron2D.Ledger
  alias Cauldron2D.World.Events

  @doc "Start recording; see the module documentation for the options."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl GenServer
  def init(opts) do
    world = Keyword.fetch!(opts, :world)

    case Events.subscribe(world) do
      :ok ->
        Process.monitor(GenServer.whereis(world))

        {:ok,
         %{
           arena: Keyword.fetch!(opts, :arena),
           ledger: Keyword.get(opts, :ledger, Ledger),
           tag: Keyword.get(opts, :tag, :result),
           on_result: Keyword.get(opts, :on_result)
         }}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_info({:cauldron_events, _world, _tick, events}, state) do
    for {tag, row} <- events, tag == state.tag do
      Ledger.record(state.ledger, state.arena, row)
      if state.on_result, do: state.on_result.(row)
    end

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state), do: {:stop, :normal, state}
  def handle_info(_message, state), do: {:noreply, state}
end
