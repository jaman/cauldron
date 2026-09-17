defmodule Cauldron2D.TestGames.Dots do
  @moduledoc false
  @behaviour Cauldron2D.Game

  @impl true
  def init(_opts), do: %{players: %{}, events: []}

  @impl true
  def join(%{players: players}, id, _props) when is_map_key(players, id),
    do: {:error, :already_joined}

  def join(state, id, props),
    do:
      {:ok,
       put_in(state.players[id], %{
         pos: {5.0, 5.0},
         held: MapSet.new(),
         spectator: Map.get(props, :spectate, false)
       })}

  @impl true
  def leave(state, id), do: %{state | players: Map.delete(state.players, id)}

  @impl true
  def handle_input(state, id, %{held: held} = input),
    do: update_in(state.players[id], &Map.merge(&1, %{held: held, aim: Map.get(input, :aim)}))

  @impl true
  def step(state, dt) do
    players =
      Map.new(state.players, fn {id, p} ->
        {x, y} = p.pos
        dx = if MapSet.member?(p.held, :right), do: 4.0 * dt, else: 0.0
        {id, %{p | pos: {x + dx, y}}}
      end)

    %{state | players: players}
  end

  @impl true
  def view(state, id) do
    %{
      me: state.players[id],
      movers: for({_, p} <- state.players, do: {:dot, p.pos}),
      width: 20,
      height: 12
    }
  end

  @impl true
  def drain_events(state), do: {Enum.reverse(state.events), %{state | events: []}}
end
