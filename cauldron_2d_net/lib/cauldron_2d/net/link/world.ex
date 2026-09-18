defmodule Cauldron2D.Net.Link.World do
  @moduledoc """
  A server's arena spoken for in this VM: a process a client joins, sends input to and
  leaves exactly as it would a `Cauldron2D.World` (`Cauldron2D.Player`), which opens a
  WebSocket to the server for each player (`Cauldron2D.Net.Link.Socket`) and turns what
  comes back into frames, and plays the sound that comes with them through this
  machine's speaker.

      {:ok, world} = Cauldron2D.Net.Link.World.start(url: url, token: token, arena: "pit")
      :ok = Cauldron2D.Player.join(world, "alice", %{username: "alice"})

  The view a player receives is `%{wire: frame, map: map, sheet: sheet, arena: name}`,
  the frame and map in the shapes `Cauldron2D.Net.Wire` gives and the sheet its index;
  when the connection ends, one last view with `wire: nil` and `closed: reason`. A
  game's `Cauldron2D.Client.Game` draws such views through `scene/2`, `hud/1`,
  `outcome/1` and `labels/1` here:

      def scene(%{wire: _} = view), do: Cauldron2D.Net.Link.World.scene(view, :my_game)
      def scene(view), do: ...

  The arts are matched to the local atlas by name, so both sides must draw from the
  same atlas.

  ## Options

    * `:url`, `:token` — the server and the token from `Cauldron2D.Net.Remote.login/4`. Required
    * `:arena` — the arena's id as it writes. Required
    * `:topic` — the channel's topic prefix. Default `"world"`
    * `:sound` — `false` for silence. Default `true`
    * `:name` — a GenServer name. Default none
  """

  use GenServer

  alias Cauldron2D.Client.Hud
  alias Cauldron2D.Net.Link.Socket
  alias Cauldron2D.Net.Sound

  @supervisor Cauldron2D.Net.Link.World.Supervisor

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
      id: {__MODULE__, Keyword.fetch!(opts, :url), Keyword.fetch!(opts, :arena)},
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

  @doc "The scene of a wire view for a surface drawing from `atlas`: focus, bounds, a cell function over the map, movers, labels, and the subject when the frame carries one."
  @spec scene(map(), Cauldron2D.Atlas.name()) :: Cauldron2D.Client.Game.scene()
  def scene(%{wire: nil, map: map}, _atlas),
    do: %{focus: {0.0, 0.0}, bounds: bounds(map), cell: fn _ -> :void end, movers: [], labels: []}

  def scene(%{wire: frame, map: map, sheet: sheet}, atlas) do
    arts = arts(sheet, atlas)
    rows = if map, do: map.rows |> Enum.map(&List.to_tuple/1) |> List.to_tuple(), else: {}

    %{
      focus: frame.focus,
      bounds: bounds(map),
      cell: fn point -> cell(rows, map, arts, point) end,
      movers:
        for(
          {index, x, y} <- frame.movers,
          art = Map.get(arts, index),
          art != nil,
          do: {art, {x, y}}
        ),
      labels: labels(frame)
    }
    |> subject(frame)
  end

  defp subject(scene, %{subject: subject}) when subject != nil,
    do: Map.put(scene, :subject, subject)

  defp subject(scene, _frame), do: scene

  defp bounds(nil), do: :unbounded
  defp bounds(%{width: width, height: height}), do: {width, height}

  defp cell(_rows, nil, _arts, _point), do: :void

  defp cell(rows, map, arts, {x, y}) do
    {x, y} =
      if map.wrap, do: {Integer.mod(x, map.width), Integer.mod(y, map.height)}, else: {x, y}

    if x >= 0 and y >= 0 and x < map.width and y < map.height do
      case Map.get(arts, elem(elem(rows, y), x)) do
        nil -> :void
        art -> {art, [], nil}
      end
    else
      :void
    end
  end

  defp arts(sheet, atlas) do
    names =
      for art <- Cauldron2D.Atlas.fetch(atlas).entries |> Map.keys(),
          into: %{},
          do: {if(is_atom(art), do: Atom.to_string(art), else: inspect(art)), art}

    for {name, index} <- Map.get(sheet, :arts, %{}),
        art = Map.get(names, name),
        art != nil,
        into: %{},
        do: {index, art}
  end

  @doc "The labels of a wire view, as a surface takes them."
  @spec labels(map()) :: list()
  def labels(%{labels: labels}),
    do: for({text, x, y, colour, scale} <- labels, do: {text, {x, y}, rgb(colour), scale: scale})

  def labels(_frame), do: []

  @doc "The hud of a wire view, rows of runs."
  @spec hud(map()) :: Hud.t()
  def hud(%{wire: nil, closed: reason}),
    do: [[{"connection closed: #{inspect(reason)}", {255, 120, 120}}]]

  def hud(%{wire: frame}),
    do: for(row <- frame.hud, do: for({text, colour} <- row, do: {text, rgb(colour)}))

  @doc "The outcome a wire view carries, `nil` while play goes on."
  @spec outcome(map()) :: map() | nil
  def outcome(%{wire: %{over: %{"title" => title, "lines" => lines}}}),
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
       arena: Keyword.fetch!(opts, :arena),
       topic: Keyword.get(opts, :topic, "world"),
       sound?: Keyword.get(opts, :sound, true),
       players: %{},
       sheet: nil,
       map: nil
     }}
  end

  @impl GenServer
  def handle_call({:join, id, props, pid}, _from, state) do
    params =
      for {key, value} <- Map.take(props, [:team, :spectate]),
          value != nil and value != false,
          into: %{},
          do: {Atom.to_string(key), value}

    case Socket.start_link(
           url: state.url,
           token: state.token,
           topic: "#{state.topic}:#{state.arena}",
           params: params,
           owner: self()
         ) do
      {:ok, link} ->
        monitor = Process.monitor(pid)
        sound = if state.sound?, do: start_sound()
        player = %{pid: pid, link: link, monitor: monitor, tick: 0, sound: sound}
        {:reply, :ok, %{state | players: Map.put(state.players, id, player)}}

      _refused ->
        {:reply, {:error, :refused}, state}
    end
  end

  def handle_call({:leave, id}, _from, state), do: {:reply, :ok, drop(state, id)}
  def handle_call(:players, _from, state), do: {:reply, Map.keys(state.players), state}

  def handle_call(:snapshot, _from, state),
    do: {:reply, %{map: state.map, sheet: state.sheet}, state}

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
  def handle_cast({:input, id, %{held: held} = input}, state) do
    case Map.fetch(state.players, id) do
      {:ok, %{link: link}} ->
        Socket.input(link, %{
          held: held |> Enum.map(&Atom.to_string/1) |> Enum.sort(),
          aim: input[:aim] && Tuple.to_list(input.aim)
        })

      :error ->
        :ok
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:cauldron_link, :sheet, sheet, _png}, state),
    do: {:noreply, %{state | sheet: sheet}}

  def handle_info({:cauldron_link, :map, map}, state), do: {:noreply, %{state | map: map}}

  def handle_info({:cauldron_link, :frame, frame}, state) do
    players =
      Map.new(state.players, fn {id, player} ->
        send(
          player.pid,
          {:cauldron_frame,
           %{
             tick: player.tick,
             view: %{wire: frame, map: state.map, sheet: state.sheet, arena: state.arena},
             events: []
           }}
        )

        {id, %{player | tick: player.tick + 1}}
      end)

    {:noreply, %{state | players: players}}
  end

  def handle_info({:cauldron_link, :audio, :off}, state), do: {:noreply, state}

  def handle_info({:cauldron_link, :audio, %{rate: rate, channels: channels}}, state) do
    for {_id, %{sound: sound}} <- state.players,
        sound != nil,
        do: Sound.format(sound, rate, channels)

    {:noreply, state}
  end

  def handle_info({:cauldron_link, :pcm, chunk}, state) do
    for {_id, %{sound: sound}} <- state.players, sound != nil, do: Sound.play(sound, chunk)
    {:noreply, state}
  end

  def handle_info({:cauldron_link, closed, reason}, state) when closed in [:closed, :refused] do
    state =
      Enum.reduce(state.players, state, fn {id, player}, acc ->
        send(
          player.pid,
          {:cauldron_frame,
           %{
             tick: player.tick,
             view: %{
               wire: nil,
               map: state.map,
               sheet: state.sheet,
               arena: state.arena,
               closed: reason
             },
             events: []
           }}
        )

        drop(acc, id)
      end)

    {:noreply, state}
  end

  def handle_info({:cauldron_link, :joined}, state), do: {:noreply, state}

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

      {%{link: link, monitor: monitor, sound: sound}, players} ->
        Process.demonitor(monitor, [:flush])
        if Process.alive?(link), do: Socket.leave(link)
        if sound, do: GenServer.stop(sound)
        %{state | players: players}
    end
  end

  defp start_sound do
    case Sound.start_link(rate: 44_100, channels: 2) do
      {:ok, sound} -> sound
      _ -> nil
    end
  end
end
