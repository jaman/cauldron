defmodule Cauldron.Net.Link.World do
  @moduledoc """
  A server's world spoken for in this VM: a process a client joins, sends input to and
  leaves exactly as it would a `Cauldron.World` (`Cauldron.Player`), which opens a
  WebSocket to the server for each player (`Cauldron.Net.Link.Socket`, through a
  `Cauldron.Net.Link.World.Relay` of the player's own) and turns what comes back into
  frames, and plays the sound that comes with them through this machine's speaker.

      {:ok, world} = Cauldron.Net.Link.World.start(url: url, token: token, world: "pit", drawer: {Cauldron2D.Net.Drawer, atlas: :my_game})
      :ok = Cauldron.Player.join(world, "alice", %{username: "alice"})

  The view a player receives is `%{remote: remote, world: name}`: `remote` holds the
  server's latest `status` (`Cauldron.Net.Wire.status/1`), the round's end (`ended`)
  and what the drawer's reader keeps of each scene (`c:Cauldron.Net.Drawer.remote/2`);
  the player gets a frame each time a scene arrives, and when the connection ends, one
  last view with `closed: reason`. A game's `Cauldron.Client.Game` draws such views with
  the drawer's scene (for 2D, `Cauldron2D.Net.RemoteScene.scene/1`) and this module's
  `hud/1` and `outcome/1`:

      def scene(%{remote: _} = view), do: Cauldron2D.Net.RemoteScene.scene(view)
      def scene(view), do: ...

  The input a player sends holds the game's actions by name and aims at a world point.

  ## Options

    * `:url`, `:token` — the server and the token from `Cauldron.Net.Remote.login/4`. Required
    * `:world` — the world's id as it writes. Required
    * `:drawer` — the `Cauldron.Net.Drawer` that reads the server's scenes, a module or
      `{module, opts}`. Required
    * `:pane` — the tiles across and down the server draws for, `{columns, rows}`.
      Default `{40, 22}`
    * `:topic` — the channel's topic prefix. Default `"world"`
    * `:sound` — `false` for silence. Default `true`
    * `:name` — a GenServer name. Default none
  """

  use GenServer

  alias Cauldron.Net.Link.World.Relay

  @supervisor Cauldron.Net.Link.World.Supervisor

  @doc false
  def child_spec(_opts),
    do: %{
      id: @supervisor,
      start: {DynamicSupervisor, :start_link, [[strategy: :one_for_one, name: @supervisor]]},
      type: :supervisor
    }

  @doc "Start the world under the package's supervisor, so it outlives the caller."
  @spec start(keyword()) :: DynamicSupervisor.on_start_child()
  def start(opts) do
    DynamicSupervisor.start_child(@supervisor, %{
      id: {__MODULE__, Keyword.fetch!(opts, :url), Keyword.fetch!(opts, :world)},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    })
  end

  @doc "Start the world linked to the caller."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  @doc "The hud of a remote view, rows of runs."
  @spec hud(map()) :: Cauldron.Client.Hud.t()
  def hud(%{closed: reason}), do: [[{"connection closed: #{inspect(reason)}", {255, 120, 120}}]]

  def hud(%{remote: %{status: %{hud: hud}}}),
    do: for(row <- hud, do: for({text, colour} <- row, do: {text, rgb(colour)}))

  def hud(_view), do: []

  @doc "The outcome a remote view carries, `nil` while play goes on."
  @spec outcome(map()) :: map() | nil
  def outcome(%{remote: %{ended: %{outcome: outcome}}}), do: outcome

  def outcome(%{remote: %{status: %{over: %{"title" => title, "lines" => lines}}}}),
    do: %{title: title, lines: lines}

  def outcome(_view), do: nil

  defp rgb("#" <> hex),
    do: hex |> Base.decode16!(case: :mixed) |> then(fn <<r, g, b>> -> {r, g, b} end)

  defp rgb(_none), do: nil

  @impl GenServer
  def init(opts) do
    {:ok,
     %{
       url: Keyword.fetch!(opts, :url),
       token: Keyword.fetch!(opts, :token),
       world: Keyword.fetch!(opts, :world),
       drawer: Keyword.fetch!(opts, :drawer),
       pane: Keyword.get(opts, :pane, {40, 22}),
       topic: Keyword.get(opts, :topic, "world"),
       sound?: Keyword.get(opts, :sound, true),
       players: %{}
     }}
  end

  @impl GenServer
  def handle_call({:join, id, props, pid, frames?}, _from, state) do
    params =
      for {key, value} <- Map.take(props, [:team, :spectate]),
          value != nil and value != false,
          into: %{},
          do: {Atom.to_string(key), value}

    case Relay.start_link(
           url: state.url,
           token: state.token,
           topic: "#{state.topic}:#{state.world}",
           params: params,
           player: pid,
           world: state.world,
           drawer: state.drawer,
           pane: state.pane,
           frames?: frames?,
           sound?: state.sound? and frames?
         ) do
      {:ok, relay} ->
        monitor = Process.monitor(pid)

        {:reply, :ok,
         %{state | players: Map.put(state.players, id, %{relay: relay, monitor: monitor})}}

      _refused ->
        {:reply, {:error, :refused}, state}
    end
  end

  def handle_call({:leave, id}, _from, state), do: {:reply, :ok, drop(state, id)}
  def handle_call(:players, _from, state), do: {:reply, Map.keys(state.players), state}
  def handle_call(:snapshot, _from, state), do: {:reply, %{world: state.world}, state}

  def handle_call(:stats, _from, state),
    do:
      {:reply,
       %{
         players: map_size(state.players),
         hz: 0,
         steps: 0,
         ticks: 0,
         tick_us: %{mean: 0, p95: 0, max: 0},
         behind: 0
       }, state}

  def handle_call(:pause, _from, state), do: {:reply, :ok, state}
  def handle_call(:resume, _from, state), do: {:reply, :ok, state}
  def handle_call(:paused?, _from, state), do: {:reply, false, state}
  def handle_call(:replay, _from, state), do: {:reply, nil, state}

  @impl GenServer
  def handle_cast({:input, id, input}, state) do
    case Map.fetch(state.players, id) do
      {:ok, %{relay: relay}} -> Relay.input(relay, input)
      :error -> :ok
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    case Enum.find(state.players, fn {_id, player} -> player.monitor == monitor end) do
      {id, _player} -> {:noreply, drop(state, id)}
      nil -> {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp drop(state, id) do
    case Map.pop(state.players, id) do
      {nil, _} ->
        state

      {%{relay: relay, monitor: monitor}, players} ->
        Process.demonitor(monitor, [:flush])
        if Process.alive?(relay), do: GenServer.stop(relay)
        %{state | players: players}
    end
  end
end
