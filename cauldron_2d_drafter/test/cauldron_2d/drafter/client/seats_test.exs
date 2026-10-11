defmodule Cauldron2D.Drafter.Client.SeatsTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Drafter.Client.Seats
  alias Cauldron2D.World

  defmodule Held do
    @behaviour Cauldron2D.Game

    @impl true
    def init(_opts), do: %{held: %{}}
    @impl true
    def join(state, _id, _props), do: {:ok, state}
    @impl true
    def leave(state, id), do: %{state | held: Map.delete(state.held, id)}
    @impl true
    def handle_input(state, id, %{held: held}), do: put_in(state.held[id], held)
    @impl true
    def step(state, _dt), do: state
    @impl true
    def view(state, _id), do: state.held
    @impl true
    def drain_events(state), do: {[], state}
  end

  test "each seat joins as its own player, sends only its own keys, and is sent no frames" do
    {:ok, world} = World.start_link(game: Held, tick: :on_input)
    keymaps = [%{up: [:w]}, %{up: [:up]}]
    seats = Seats.join(world, "ana", %{}, keymaps, %{}, [])

    assert Enum.map(seats, & &1.id) == ["ana 2", "ana 3"]
    assert Enum.sort(World.players(world)) == ["ana 2", "ana 3"]

    seats
    |> Seats.key({:key, :up}, System.monotonic_time(:millisecond))
    |> Seats.send_input(world, & &1)

    held = World.snapshot(world).held

    assert MapSet.to_list(held["ana 3"]) == [:up]
    refute Map.has_key?(held, "ana 2") and MapSet.size(held["ana 2"]) > 0
    refute_received {:cauldron_frame, _frame}
  end
end
