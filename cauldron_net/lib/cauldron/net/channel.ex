defmodule Cauldron.Net.Channel do
  @moduledoc """
  The Phoenix channel a game's browser players join, one per player: a world, driven
  by `Cauldron.Net.Session`, or one of the game's own screens outside a world (its
  title, its summary), driven by `Cauldron.Net.FrontSession`.

      defmodule MyGame.Web.WorldChannel do
        use Cauldron.Net.Channel,
          game: MyGame.Client,
          drawer: Cauldron2D.Net.Drawer,
          topic: "world",
          audio: %{rate: 22_050, channels: 2}
      end

  `:game` implements `Cauldron.Client.Game`; `:drawer` is the `Cauldron.Net.Drawer`
  its scenes go to the browser through, a module or `{module, opts}`. The topic is `"world:<id>"` (`:topic`
  names another prefix); `id` is the world, as its id writes, among the game's
  `worlds/1` given the socket's assigns, `front:title` for the game's title front, or
  `chat:lobby` for the lobby's room of `Cauldron.Chat` in a game with a chat. A world's
  players talk in its own room: the channel pushes `"chat_history"` (`messages`) on
  joining and `"chat"` (`from`, `text`, `at`) for each message, `"talk"` when the
  player's talk key asks for a line, and takes `"say"` (`text`).
  The socket's assigns must carry `:username`; `:settings` (a map with `:sfx` and
  `:music`) is read when present. The join params reach the game's
  `join_props/1` as `:params`, and whatever it returns joins the world as props; a
  join param `"audio"` of `%{"rate" => hertz, "channels" => 1 | 2}` (8 000 to 48 000
  Hz) is the PCM format the browser wants, as `cauldron.js`'s `audio` option sends it;
  without one the format is the `:audio` option of `use` (default 44 100 Hz stereo), and
  `false` asks for no sound; what the session gets is `Cauldron.Net.Audio`'s to say.
  A join param `"saved"` is the player's settings as a `"settings"` push gave them.
  A refusal is shown as the game's `refusal_text/1` gives it, `inspect/1` without one.

  The drawer's pushes go to the browser as they are: its first ones on joining, those
  for each frame after the frame's `"status"` (hud rows, outcome, subject, focus), and
  those for a message of its own the channel receives (`Cauldron.Net.Session.changed/2`).
  A binary payload goes as a binary push. The audio goes as binary `"pcm"` pushes
  (the session's own stage and the world's shared music mixed, as
  `Cauldron.Net.Audio`'s policy has it). The game's menu, its fronts and the client's
  keys (`Cauldron.Client.Stage`) answer `"go"` (`to`: `"world"` with `id`,
  `"lobby"`, `"settings"`, `"guide"`, `"title"` or `"quit"`), `"clipboard"` (`text`)
  and `"settings"` (`sfx`, `music` and `saved`, the player's settings signed with the
  endpoint's `secret_key_base` for the browser to keep and send back). When the round
  is over and the game has a summary front, the channel leaves the world, pushes
  `"front"` (`screen: "summary"`) and runs the summary. When the world asks to move the
  player (`c:Cauldron.Client.Game.ask/1`'s `{:enter, props}`, `{:return, props}`,
  `{:on_return, props}`), the channel leaves it and joins the first world the game lists
  for the client's props merged with those — on a refusal the earlier world again, with
  `refused: true`; when that world goes down, the earlier one with the `on_return` props —
  pushing `"world"` (`id`) and the new world's first pushes.

  From the browser: `"pane"` (`columns`, `rows`: the tiles it shows at zoom 1), `"key"`
  (`key`, a `KeyboardEvent.key`, and `mods` of `"ctrl"`, `"shift"`, `"alt"`, `"meta"`),
  `"mouse"` (`button` with `down`, `wheel` `"up"`/`"down"`, or `move: true`, each with
  `at`, the pointer as fractions of the picture), `"hold"` (`action`, `down`, and
  `strength` 0.0–1.0 or none: an action held by name, as a touch screen's buttons hold
  them), `"aim"` (`at`, a world point or `null`, for a client that aims itself),
  `"padline"` (`line`, a `Gamepad.Wire` line from the page's controllers), `"pan"`
  (`x`, `y`: how far to move a watching player's view, as fractions of the pane),
  `"recentre"`, `"configure"` (`preset`, `pointer`, `fps`: the player's settings changed
  beside the world), `"levels"`, `"music"` (`on`, the music switched off or back on at its
  level) and `"pause"` (for a world of the player's own). Keys go up as well as down
  (`"key"` with `down: false`), so the session holds the game's actions as
  `Cauldron.Client.Controls` reads them. Leaving the channel leaves the world. Input
  messages arrive many times a second and are not logged.
  """

  alias Cauldron.Chat
  alias Cauldron.Client.{Fronts, Game, Menus, Stage}
  alias Cauldron.Net.Audio, as: NetAudio
  alias Cauldron.Net.{FrontSession, Keys, Session}
  alias Phoenix.Socket

  @salt "cauldron settings"

  defmacro __using__(opts) do
    game = Keyword.fetch!(opts, :game)
    prefix = Keyword.get(opts, :topic, "world")
    audio = Keyword.get(opts, :audio, Macro.escape(%{rate: 44_100, channels: 2}))
    drawer = Keyword.fetch!(opts, :drawer)

    quote do
      use Phoenix.Channel, log_handle_in: false

      @impl true
      def join(unquote(prefix) <> ":" <> id, params, socket),
        do:
          Cauldron.Net.Channel.join(
            unquote(game),
            [audio: unquote(audio), drawer: unquote(drawer)],
            id,
            params,
            socket
          )

      @impl true
      def handle_in(event, payload, socket),
        do: Cauldron.Net.Channel.handle_in(event, payload, socket)

      @impl true
      def handle_info(message, socket), do: Cauldron.Net.Channel.handle_info(message, socket)

      @impl true
      def terminate(_reason, socket), do: Cauldron.Net.Channel.terminate(socket)
    end
  end

  @doc false
  def join(game, opts, "front:title", params, socket) do
    props = props(Socket.assign(socket, :game, game), params)

    case FrontSession.open(
           game,
           :title,
           socket.assigns.username,
           props,
           session_opts(opts, params)
         ) do
      {:ok, front, pushes} ->
        send(self(), {:cauldron_web_pushes, pushes})
        Process.send_after(self(), :cauldron_front_tick, FrontSession.frame_ms())

        {:ok,
         socket
         |> Socket.assign(:game, game)
         |> Socket.assign(:opts, opts)
         |> Socket.assign(:front, front)}

      {:error, :no_front} ->
        {:error, %{reason: "no title"}}
    end
  end

  def join(game, _opts, "chat:lobby", _params, socket) do
    if Stage.chat?(game) do
      Chat.join(:lobby)
      send(self(), {:cauldron_web_pushes, [{"chat_history", %{messages: Chat.history(:lobby)}}]})
      {:ok, socket |> Socket.assign(:game, game) |> Socket.assign(:chat_room, :lobby)}
    else
      {:error, %{reason: "no chat"}}
    end
  end

  def join(game, opts, id, params, socket) do
    case Game.world(game, socket.assigns, id) do
      nil ->
        {:error, %{reason: "no such world"}}

      %{world: world} ->
        props = props(Socket.assign(socket, :game, game), params)

        case Session.join(
               game,
               world,
               socket.assigns.username,
               props,
               session_opts(opts, params) ++ [chat_room: {:world, id}]
             ) do
          {:ok, session, pushes} ->
            NetAudio.subscribe()
            send(self(), {:cauldron_web_pushes, pushes})

            {:ok,
             socket
             |> Socket.assign(:game, game)
             |> Socket.assign(:opts, opts)
             |> Socket.assign(:world_id, id)
             |> Socket.assign(:params, params)
             |> Socket.assign(:client_props, %{username: socket.assigns.username})
             |> Socket.assign(:return_props, nil)
             |> Socket.assign(:return_extra, %{})
             |> Socket.assign(:session, session)}

          {:error, reason} ->
            {:error, %{reason: reason(game, reason)}}
        end
    end
  end

  defp session_opts(opts, params) do
    audio(params) ++
      [audio: Keyword.fetch!(opts, :audio), drawer: Keyword.fetch!(opts, :drawer), params: params]
  end

  @doc false
  def handle_in(
        "hold",
        %{"action" => action, "down" => down} = payload,
        %{assigns: %{session: session}} = socket
      )
      when is_binary(action) and is_boolean(down) do
    strength = if is_number(payload["strength"]), do: min(max(payload["strength"], 0), 1)
    {:noreply, Socket.assign(socket, :session, Session.hold(session, action, down, strength))}
  end

  def handle_in("configure", payload, %{assigns: %{session: session, game: game}} = socket)
      when is_map(payload) do
    changes =
      %{}
      |> preset(game, payload["preset"])
      |> then(
        &if is_boolean(payload["pointer"]),
          do: Map.put(&1, :pointer, payload["pointer"]),
          else: &1
      )
      |> rated(game, payload["fps"])

    {:noreply, Socket.assign(socket, :session, Session.configure(session, changes))}
  end

  def handle_in("aim", %{"at" => at}, %{assigns: %{session: session}} = socket) do
    {:noreply, Socket.assign(socket, :session, Session.aim(session, aim_point(at)))}
  end

  def handle_in("padline", %{"line" => line}, socket) when is_binary(line) do
    case Gamepad.Wire.parse(line) do
      %{type: _} = event -> answer(socket, &Session.pad_event(&1, event), &pad_front(&1, event))
      _other -> {:noreply, socket}
    end
  end

  def handle_in("pane", %{"columns" => columns, "rows" => rows}, socket)
      when is_integer(columns) and columns > 0 and is_integer(rows) and rows > 0,
      do:
        answer(
          socket,
          &Session.pane(&1, {columns, rows}),
          &FrontSession.pane(&1, {columns, rows})
        )

  def handle_in("key", %{"key" => key} = payload, socket) when is_binary(key) do
    case Keys.input_key(key, payload["code"]) do
      nil ->
        {:noreply, socket}

      atom ->
        mods = Keys.input_mods(payload["mods"])
        down? = payload["down"] != false

        answer(
          socket,
          &Session.key(&1, atom, mods, down?),
          &if(down?, do: FrontSession.key(&1, atom, mods), else: {&1, []})
        )
    end
  end

  def handle_in("pan", %{"x" => fx, "y" => fy}, %{assigns: %{session: _}} = socket)
      when is_number(fx) and is_number(fy),
      do: answer(socket, &Session.pan(&1, {fx, fy}), nil)

  def handle_in("recentre", _payload, %{assigns: %{session: _}} = socket),
    do: answer(socket, &Session.recentre/1, nil)

  def handle_in("mouse", payload, socket) when is_map(payload) do
    case mouse(payload) do
      nil -> {:noreply, socket}
      mouse -> answer(socket, &Session.mouse(&1, mouse), &FrontSession.mouse(&1, mouse))
    end
  end

  def handle_in("say", %{"text" => text}, %{assigns: %{session: session}} = socket)
      when is_binary(text),
      do: {:noreply, Socket.assign(socket, :session, Session.say(session, text))}

  def handle_in("say", %{"text" => text}, %{assigns: %{chat_room: room}} = socket)
      when is_binary(text) do
    case text |> String.trim() |> String.slice(0, 500) do
      "" ->
        :ok

      said ->
        Chat.say(room, Game.player_label(socket.assigns.game, socket.assigns.username), said)
    end

    {:noreply, socket}
  end

  def handle_in("levels", %{"sfx" => sfx, "music" => music}, socket)
      when is_number(sfx) and is_number(music) do
    case socket.assigns do
      %{session: session} ->
        {:noreply, Socket.assign(socket, :session, Session.levels(session, sfx, music))}

      %{front: front} ->
        {:noreply, Socket.assign(socket, :front, FrontSession.levels(front, sfx, music))}
    end
  end

  def handle_in("music", %{"on" => on}, %{assigns: %{session: session}} = socket)
      when is_boolean(on),
      do: {:noreply, Socket.assign(socket, :session, Session.music(session, on))}

  def handle_in("pause", _payload, %{assigns: %{session: session}} = socket),
    do: {:noreply, Socket.assign(socket, :session, Session.toggle_pause(session))}

  def handle_in(_event, _payload, socket), do: {:noreply, socket}

  @doc false
  def handle_info({:cauldron_frame, message}, %{assigns: %{session: _}} = socket),
    do: answer(socket, &Session.frame(&1, message), nil)

  def handle_info({:chat, _room, message}, %{assigns: %{session: _}} = socket),
    do: answer(socket, &Session.chat(&1, message), nil)

  def handle_info({:chat, _room, message}, %{assigns: %{chat_room: _}} = socket) do
    push_all(socket, [{"chat", message}])
    {:noreply, socket}
  end

  def handle_info({:pcm, chunk}, %{assigns: %{session: session}} = socket) do
    {session, pushes} = Session.pcm(session, chunk)
    push_all(socket, pushes)
    {:noreply, Socket.assign(socket, :session, session)}
  end

  def handle_info({:pcm, chunk}, socket) do
    push_all(socket, [{"pcm", chunk}])
    {:noreply, socket}
  end

  def handle_info({:cauldron_shared_pcm, chunk}, %{assigns: %{session: session}} = socket) do
    {session, pushes} = Session.shared_pcm(session, chunk)
    push_all(socket, pushes)
    {:noreply, Socket.assign(socket, :session, session)}
  end

  def handle_info({:cauldron_audio_rate, rate}, %{assigns: %{session: session}} = socket) do
    {session, pushes} = Session.rerate(session, rate)
    push_all(socket, pushes)
    {:noreply, Socket.assign(socket, :session, session)}
  end

  def handle_info(:cauldron_menu_tick, socket) do
    socket = Socket.assign(socket, :menu_ticking?, false)
    answer(socket, &Session.menu_tick/1, nil)
  end

  def handle_info(:cauldron_front_tick, %{assigns: %{front: _}} = socket) do
    Process.send_after(self(), :cauldron_front_tick, FrontSession.frame_ms())
    answer(socket, nil, &FrontSession.tick/1)
  end

  def handle_info(
        {:DOWN, ref, :process, _world, _reason},
        %{assigns: %{world_watch: ref, return_props: props}} = socket
      )
      when props != nil do
    socket = Socket.assign(socket, :world_watch, nil)
    {:noreply, travel(socket, {:return, socket.assigns.return_extra})}
  end

  def handle_info({:cauldron_web_pushes, pushes}, socket) do
    push_all(socket, pushes)
    {:noreply, socket}
  end

  def handle_info(message, %{assigns: %{session: session}} = socket) do
    case Session.changed(session, message) do
      :unknown -> {:noreply, socket}
      changed -> answer(socket, fn _session -> changed end, nil)
    end
  end

  def handle_info(message, %{assigns: %{front: front}} = socket) do
    case FrontSession.changed(front, message) do
      :unknown -> {:noreply, socket}
      changed -> answer(socket, nil, fn _front -> changed end)
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @doc false
  def terminate(socket) do
    case socket.assigns do
      %{chat_room: room} -> Chat.leave(room)
      %{session: session} -> Session.leave(session)
      %{front: front} -> FrontSession.close(front)
      _ -> :ok
    end
  end

  defp answer(%{assigns: %{session: session}} = socket, world_step, _front_step)
       when world_step != nil do
    {session, pushes} = world_step.(session)
    socket = Socket.assign(socket, :session, session)

    {moves, pushes} = Enum.split_with(pushes, &match?({"travel", _}, &1))

    case List.keyfind(pushes, "ended", 0) do
      {"ended", ended} ->
        summarise(socket, pushes, ended)

      nil ->
        {:noreply, socket} = pushed(socket, pushes)

        {:noreply,
         Enum.reduce(moves, socket, fn {"travel", move}, socket -> travel(socket, move) end)}
    end
  end

  defp answer(%{assigns: %{front: front}} = socket, _world_step, front_step)
       when front_step != nil do
    {front, pushes} = front_step.(front)
    pushed(Socket.assign(socket, :front, front), pushes)
  end

  defp answer(socket, _world_step, _front_step), do: {:noreply, socket}

  defp travel(socket, {:on_return, extra}), do: Socket.assign(socket, :return_extra, extra)

  defp travel(%{assigns: %{return_props: nil}} = socket, {:return, _extra}), do: socket

  defp travel(socket, {:return, extra}) do
    returning = socket.assigns.return_props
    socket = left(socket)

    case entered(socket, returning, extra) do
      {:ok, socket} ->
        socket |> Socket.assign(:return_props, nil) |> Socket.assign(:return_extra, %{})

      {:error, socket} ->
        socket
    end
  end

  defp travel(socket, {:enter, props}) do
    returning = socket.assigns.return_props || socket.assigns.client_props
    socket = left(socket)

    case entered(socket, Map.merge(socket.assigns.client_props, props), %{}) do
      {:ok, socket} ->
        socket |> Socket.assign(:return_props, returning) |> Socket.assign(:return_extra, %{})

      {:error, socket} ->
        {_, socket} = entered(socket, returning, %{refused: true})
        Socket.assign(socket, :return_props, nil)
    end
  end

  defp left(socket) do
    Session.leave(socket.assigns.session)
    if ref = socket.assigns[:world_watch], do: Process.demonitor(ref, [:flush])
    socket
  end

  defp entered(socket, client_props, extra) do
    game = socket.assigns.game

    with [world | _] <- game.worlds(client_props),
         id = to_string(world.id),
         props = socket |> props(socket.assigns.params) |> Map.merge(extra),
         {:ok, session, pushes} <-
           Session.join(
             game,
             world.world,
             socket.assigns.username,
             props,
             session_opts(socket.assigns.opts, socket.assigns.params) ++
               [chat_room: {:world, id}]
           ) do
      push_all(socket, [{"world", %{id: id}} | pushes])

      {:ok,
       socket
       |> Socket.assign(:session, session)
       |> Socket.assign(:world_id, id)
       |> Socket.assign(:client_props, client_props)
       |> Socket.assign(:world_watch, watch(session.world))}
    else
      _refused -> {:error, socket}
    end
  end

  defp watch(world) do
    case GenServer.whereis(world) do
      pid when is_pid(pid) -> Process.monitor(pid)
      _none -> nil
    end
  end

  defp pushed(socket, pushes) do
    push_all(socket, pushes)
    {:noreply, tick_menu(socket)}
  end

  defp summarise(socket, pushes, %{outcome: outcome, view: view}) do
    game = socket.assigns.game

    if Map.has_key?(Fronts.of(game, %{username: socket.assigns.username}), :summary) do
      session = socket.assigns.session
      Session.leave(session)

      props =
        socket
        |> props(socket.assigns.params)
        |> Map.put(:settings, Session.settings(session))
        |> Map.merge(%{outcome: outcome, view: view, world: socket.assigns.world_id})

      {:ok, front, front_pushes} =
        FrontSession.open(
          game,
          :summary,
          socket.assigns.username,
          props,
          session_opts(socket.assigns.opts, socket.assigns.params)
        )

      push_all(socket, [{"front", %{screen: "summary"}} | front_pushes])
      Process.send_after(self(), :cauldron_front_tick, FrontSession.frame_ms())

      socket =
        socket
        |> Map.update!(:assigns, &Map.delete(&1, :session))
        |> Socket.assign(:front, front)

      {:noreply, socket}
    else
      pushed(socket, Enum.reject(pushes, &match?({"ended", _}, &1)))
    end
  end

  defp tick_menu(%{assigns: %{session: session}} = socket) do
    if Session.menu_open?(session) and not Map.get(socket.assigns, :menu_ticking?, false) do
      Process.send_after(self(), :cauldron_menu_tick, Menus.frame_ms())
      Socket.assign(socket, :menu_ticking?, true)
    else
      socket
    end
  end

  defp tick_menu(socket), do: socket

  @doc false
  def props(socket, params) do
    given = Map.get(socket.assigns, :settings, %{})

    settings =
      socket
      |> saved(params["saved"])
      |> Map.merge(given)
      |> preset(socket.assigns[:game], params["preset"])
      |> rated(socket.assigns[:game], params["fps"])
      |> pointing(params["pointer"])

    %{settings: settings, params: Map.drop(params, ["saved", "preset", "fps", "pointer"])}
  end

  defp preset(settings, game, name) when is_binary(name) and game != nil do
    case Enum.find(game.keymaps(), fn {preset, _} -> Atom.to_string(preset) == name end) do
      {preset, _keymap} -> Map.put(settings, :preset, preset)
      nil -> settings
    end
  end

  defp preset(settings, _game, _name), do: settings

  defp rated(settings, game, fps) when is_integer(fps) and game != nil do
    if fps in Game.frame_rates(game), do: Map.put(settings, :fps, fps), else: settings
  end

  defp rated(settings, game, "auto") when game != nil, do: Map.put(settings, :fps, :auto)
  defp rated(settings, _game, _fps), do: settings

  defp pointing(settings, pointer) when is_boolean(pointer),
    do: Map.put(settings, :pointer, pointer)

  defp pointing(settings, _pointer), do: settings

  defp saved(socket, token) when is_binary(token) do
    case Plug.Crypto.verify(secret(socket), @salt, token) do
      {:ok, settings} when is_map(settings) -> settings
      _other -> %{}
    end
  end

  defp saved(_socket, _token), do: %{}

  defp secret(socket), do: socket.endpoint.config(:secret_key_base)

  defp pad_front(front, %{type: :button, button: button, pressed: true}),
    do: FrontSession.pad(front, button)

  defp pad_front(front, _event), do: {front, []}

  @doc false
  def mouse(payload) do
    at = pointer(payload["at"])

    case payload do
      %{"wheel" => "up"} ->
        %{type: :scroll, direction: :up, at: at}

      %{"wheel" => "down"} ->
        %{type: :scroll, direction: :down, at: at}

      %{"button" => button} when button in ["left", "middle", "right"] ->
        type = if payload["down"] == false, do: :mouse_up, else: :mouse_down
        %{type: type, button: String.to_existing_atom(button), at: at}

      %{"move" => true} ->
        %{type: :move, at: at}

      _other ->
        nil
    end
  end

  defp pointer([fx, fy]) when is_number(fx) and is_number(fy), do: {fx, fy}
  defp pointer(_none), do: {0.5, 0.5}

  defp aim_point([x, y]) when is_number(x) and is_number(y), do: {x, y}
  defp aim_point(_at), do: nil

  @doc ~S|The `:audio` option for `Cauldron.Net.Session.join/5` from the join params: the format asked, `:off` for `"audio": false`, `[]` without a valid `"audio"`.|
  @spec audio(map()) :: [audio: %{rate: pos_integer(), channels: 1 | 2} | :off]
  def audio(%{"audio" => false}), do: [audio: :off]

  def audio(%{"audio" => %{"rate" => rate, "channels" => channels}})
      when is_integer(rate) and rate >= 8_000 and rate <= 48_000 and channels in [1, 2] do
    [audio: %{rate: rate, channels: channels}]
  end

  def audio(_params), do: []

  @doc false
  def push_all(socket, pushes) do
    Enum.each(pushes, fn
      {"settings", settings} ->
        Phoenix.Channel.push(socket, "settings", %{
          sfx: settings.sfx,
          music: settings.music,
          saved: Plug.Crypto.sign(secret(socket), @salt, settings)
        })

      {"ended", ended} ->
        Phoenix.Channel.push(socket, "ended", {:binary, :erlang.term_to_binary(ended)})

      {event, payload} when is_binary(payload) ->
        Phoenix.Channel.push(socket, event, {:binary, payload})

      {event, payload} ->
        Phoenix.Channel.push(socket, event, payload)
    end)
  end

  @doc false
  def reason(game, reason), do: Game.refusal_text(game, reason)

  @doc false
  def world(game, assigns, id), do: Game.world(game, assigns, id)
end
