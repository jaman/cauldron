defmodule Cauldron2D.TestGames.Race do
  @moduledoc false
  @behaviour Cauldron2D.Game

  @impl true
  def init(opts), do: %{players: %{}, events: [], seed: Keyword.get(opts, :seed, 0), ticks: 0}

  @impl true
  def join(state, id, props) do
    if map_size(state.players) >= 2 do
      {:error, :full}
    else
      {:ok,
       put_in(state.players[id], %{x: 0.0, speed: Map.get(props, :speed, 1.0), held: MapSet.new()})}
    end
  end

  @impl true
  def leave(state, id), do: %{state | players: Map.delete(state.players, id)}

  @impl true
  def handle_input(state, id, %{held: held}), do: put_in(state.players[id].held, held)

  @impl true
  def step(state, dt) do
    players =
      Map.new(state.players, fn {id, player} ->
        moving = MapSet.member?(player.held, :forward)
        {id, %{player | x: if(moving, do: player.x + player.speed * dt, else: player.x)}}
      end)

    events =
      if rem(state.ticks, 10) == 0, do: [{:beep, state.ticks} | state.events], else: state.events

    %{state | players: players, ticks: state.ticks + 1, events: events}
  end

  @impl true
  def view(state, id), do: %{me: state.players[id].x, others: map_size(state.players) - 1}

  @impl true
  def drain_events(state), do: {Enum.reverse(state.events), %{state | events: []}}
end
