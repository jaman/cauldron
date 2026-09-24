defmodule Cauldron2D.Ledger.RecorderTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.{Ledger, Player, World}

  defmodule Rounds do
    @moduledoc false
    @behaviour Cauldron2D.Game

    @impl true
    def init(_opts), do: %{players: [], ticks: 0, events: []}
    @impl true
    def join(state, id, _props), do: {:ok, %{state | players: [id | state.players]}}
    @impl true
    def leave(state, id), do: %{state | players: List.delete(state.players, id)}
    @impl true
    def handle_input(state, _id, _input), do: state

    @impl true
    def step(%{ticks: 4} = state, _dt) do
      results =
        for id <- state.players,
            do:
              {:result,
               %{
                 id: id,
                 name: to_string(id),
                 kills: 1,
                 deaths: 0,
                 won?: true,
                 best_streak: 1,
                 laps: 0
               }}

      %{state | ticks: 5, events: results ++ [{:other, :thing}]}
    end

    def step(state, _dt), do: %{state | ticks: state.ticks + 1}
    @impl true
    def view(state, _id), do: state.ticks
    @impl true
    def drain_events(state), do: {state.events, %{state | events: []}}
  end

  test "every tagged event in the world goes to the ledger under the world's name, and the recorder stops with the world" do
    path =
      Path.join(System.tmp_dir!(), "cauldron_recorder_#{System.unique_integer([:positive])}.dets")

    {:ok, ledger} = Ledger.start_link(path: path, name: nil, metrics: [kills: {:sum, :kills}])
    {:ok, world} = World.start_link(game: Rounds, hz: 100)
    test = self()

    {:ok, recorder} =
      Ledger.Recorder.start_link(
        world: world,
        label: "Pit",
        ledger: ledger,
        on_result: fn row -> send(test, {:seen, row}) end
      )

    :ok = Player.join(world, :alice, %{})
    assert_receive {:seen, %{id: :alice}}, 1_000
    assert [%{account: :alice, value: 1}] = Ledger.board(ledger, :all, :kills, world: "Pit")
    ref = Process.monitor(recorder)
    GenServer.stop(world)
    assert_receive {:DOWN, ^ref, :process, ^recorder, :normal}, 500
    GenServer.stop(ledger)
    File.rm(path)
  end
end
