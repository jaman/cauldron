defmodule Cauldron.Net.Link.World.Relay do
  @moduledoc """
  One player of a `Cauldron.Net.Link.World`: owns the player's
  `Cauldron.Net.Link.Socket`, keeps what the server last sent — its status, the round's
  end, and what the drawer keeps of each scene (`c:Cauldron.Net.Drawer.remote/2`) — and
  hands the player a frame with the view `Cauldron.Net.Link.World` describes each time a
  scene arrives. The player's input, the game's actions held by name and
  an aim at a world point, goes to the server as holds and an aim.
  """

  use GenServer

  alias Cauldron.Net.{Drawer, Sound}
  alias Cauldron.Net.Link.Socket

  @doc "Join the server for one player; options as `Cauldron.Net.Link.World` passes them."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "What the player holds (`:held`, a set or list of actions) and aims at (`:aim`, a world point or `nil`)."
  @spec input(GenServer.server(), map()) :: :ok
  def input(relay, input), do: GenServer.cast(relay, {:input, input})

  @impl GenServer
  def init(opts) do
    {:ok, link} =
      Socket.start_link(
        url: Keyword.fetch!(opts, :url),
        token: Keyword.fetch!(opts, :token),
        topic: Keyword.fetch!(opts, :topic),
        params: Keyword.get(opts, :params, %{}),
        drawer: Keyword.fetch!(opts, :drawer),
        owner: self()
      )

    {:ok,
     %{
       link: link,
       drawer: elem(Drawer.fetch!(opts), 0),
       player: Keyword.fetch!(opts, :player),
       world: Keyword.fetch!(opts, :world),
       pane: Keyword.fetch!(opts, :pane),
       frames?: Keyword.get(opts, :frames?, true),
       sound: if(Keyword.get(opts, :sound?, true), do: sound()),
       remote: %{status: nil, ended: nil},
       held: MapSet.new(),
       aim: nil,
       tick: 0
     }}
  end

  @impl GenServer
  def handle_cast({:input, input}, state) do
    held = MapSet.new(Map.get(input, :held, []))

    for action <- MapSet.difference(held, state.held),
        do: Socket.hold(state.link, Atom.to_string(action), true)

    for action <- MapSet.difference(state.held, held),
        do: Socket.hold(state.link, Atom.to_string(action), false)

    aim = Map.get(input, :aim)
    if aim != state.aim, do: Socket.aim(state.link, aim)
    {:noreply, %{state | held: held, aim: aim}}
  end

  @impl GenServer
  def handle_info({:cauldron_link, :joined}, state) do
    Socket.pane(state.link, state.pane)
    {:noreply, state}
  end

  def handle_info({:cauldron_link, :status, status}, state),
    do: {:noreply, remote(state, :status, status)}

  def handle_info({:cauldron_link, :ended, ended}, state),
    do: {:noreply, remote(state, :ended, ended)}

  def handle_info(
        {:cauldron_link, :audio, %{rate: rate, channels: channels}},
        %{sound: sound} = state
      )
      when sound != nil do
    Sound.format(sound, rate, channels)
    {:noreply, state}
  end

  def handle_info({:cauldron_link, :pcm, chunk}, %{sound: sound} = state) when sound != nil do
    Sound.play(sound, chunk)
    {:noreply, state}
  end

  def handle_info({:cauldron_link, closed, reason}, state) when closed in [:closed, :refused] do
    send(
      state.player,
      {:cauldron_frame,
       %{
         tick: state.tick,
         view: %{remote: state.remote, world: state.world, closed: reason},
         events: []
       }}
    )

    {:stop, :normal, state}
  end

  def handle_info({:cauldron_link, key, value}, state) do
    case state.drawer.remote(state.remote, {key, value}) do
      {:frame, remote} -> {:noreply, framed(%{state | remote: remote})}
      {:kept, remote} -> {:noreply, %{state | remote: remote}}
      :unknown -> {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state) do
    if Process.alive?(state.link), do: Socket.leave(state.link)
    if state.sound && Process.alive?(state.sound), do: GenServer.stop(state.sound)
    :ok
  end

  defp remote(state, key, value), do: %{state | remote: Map.put(state.remote, key, value)}

  defp framed(%{frames?: false} = state), do: state

  defp framed(state) do
    send(
      state.player,
      {:cauldron_frame,
       %{tick: state.tick, view: %{remote: state.remote, world: state.world}, events: []}}
    )

    %{state | tick: state.tick + 1}
  end

  defp sound do
    case Sound.start_link(rate: 44_100, channels: 2) do
      {:ok, sound} -> sound
      _ -> nil
    end
  end
end
