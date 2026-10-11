defmodule Cauldron2D.Drafter.Client do
  @moduledoc """
  The drafter application that puts a `Cauldron2D.World` in front of one player.

  Runs a game's client module — one implementing `Cauldron2D.Client.Game` —
  through its screens: a title, a lobby listing the worlds, settings, the world itself,
  and a summary when the game's `outcome/1` says play is over for this player. It holds the player's input, their audio, and their connection to the world.

  A world whose `world` is `{module, opts}` is this player's alone: the client starts
  a `Cauldron2D.World` for it when the player joins and stops it when they leave, and
  `p` pauses and resumes it.

  ## Flow

  Where the client starts and where leaving a world goes is the game's `start/0`, or
  the `:start` mount prop over it:

    * `:lobby` — the title, then the lobby, then a world; back retraces it. The default
    * `{:lobby, title: false}` — the lobby first; back from it stops the client
    * `{:play, id}` — straight into world `id` of `worlds/1` (`:first` for the first
      listed); leaving it stops the client
    * `{:play, id, title: true}` — the title, then that world; back returns to the title
    * a function of the client's state, called once the client is ready, for a flow of
      the game's own: `enter/3`, `to_lobby/1`, `to_title/1` and `to_guide/1` are the
      moves it can make; leaving a world then stops the client

  A game with `lobby?/0` false and no `start/0` is read as `{:play, :first, title: true}`.

      Drafter.Server.start_ssh(Cauldron2D.Drafter.Client,
        auth: {:accounts, accounts},
        tunnel: true,
        mount_props: %{game: MyGame.Client, accounts: accounts}
      )

  ## Mount props

    * `:game` — the client module. Required
    * `:username` — the player's name, set by the ssh transport. Default `"player"`
    * `:sink` — a `TuningFork.Sink` module or `{module, opts}` this player's audio plays
      through. Default: the game's `sink/1` given all the mount props, else for a session
      served over ssh (`:served_by`) raw PCM to `127.0.0.1:<:pulse_port>`, the account's
      tunnel (`TuningFork.Sink.Tcp`), or silence without one; for any other session
      `TuningFork.Sink.Speaker` when that package is present, else silence
    * `:settings` — the map `Cauldron2D.Drafter.Client.Settings.to_props/1` produced,
      from the account props; a settings file for the player overrides it. Default: the
      game's first preset
    * `:accounts` — the `Drafter.Accounts` server settings are saved to. Default: none
    * `:kind` — the kind of client this is, the key its settings are kept under (see
      `Cauldron2D.Drafter.Client.Settings`). Default `:terminal`
    * `:start` — the flow, as the Flow section describes it, over the game's `start/0`.
      Default: the game's, else `:lobby`
    * `:picture` — how a game's picture reaches a terminal that keeps images, as
      `Cauldron2D.Drafter.Client.Picture` reads it. Default: the application env
      `config :cauldron_2d_drafter, picture: ...`, else `CAULDRON_PICTURE`, else the
      game's look, else `Cauldron2D.Drafter.Client.Picture.default/0`
    * `:mute` — `true` plays no sound, whatever sink the game or the session would have
      had. Default: the application env `config :cauldron_2d_drafter, mute: true`, else
      `CAULDRON_MUTE` set to `1` or `true`, else `false`

  Every other mount prop is the game's, read by its `sink/1`, `pages/1` and `worlds/1`.

  ## Embedding

  A game with screens of its own — its own title, a menu, pages that take input —
  runs its own `Drafter.App` and drives this one from it: it keeps the client's state
  from `mount/1` (with `start: {:lobby, title: false}`), and hands it its events, messages and timers
  through `handle_event/2`, `handle_event/3`, `on_message/2` and `on_ready/1`, draws
  `render/1`, and calls `unmount/1` when done. A `{:stop, reason}` from the client
  is its wish to end: the game takes its screens back. The game's `use Drafter.App`
  needs the same options this module's has — `key_release: true, cell_size: true,
  controller: true, mouse_hover: true, frame_pacing: :always` — and its
  `refresh_rate/0` should be `refresh_rate/0` here.

  ## Tracing

  With `CAULDRON_TRACE` set (see `Cauldron2D.Trace`), the client writes every key and
  mouse event it steers with (`key`, `mouse`), every input it sends the world (`input`,
  with the actions held and the aim in tiles) and every frame the world sends back
  (`frame`, with its tick), so `mix cauldron.report --from mouse --to frame` measures
  the way round.

  ## Keys

  The client's own keys are `default_keys/0`, each replaceable or dropped by the game's
  `client_keys/0`; what follows describes the defaults. In the world `t` opens a line
  to talk to everyone in it — `Enter` sends, `Esc` cancels, and no key steers while it
  is open. `Esc` goes back: settings to where it was opened from, world to lobby, lobby
  to title, title out of the program. `q` quits the world for the lobby too, and goes
  to the title from the lobby. `^Q` and `^C` quit from anywhere. `?` shows the world's key hints and hides
  them again; held, it shows them until released. The `fps` key, bound only when the
  game binds it, shows under the world how many frames a second the world sends and
  hides it again. `=` (or `+`) and `-` zoom the world in and out through the levels
  `Cauldron2D.Drafter.Surface.zoom_levels/2` gives for the display in use, the wheel
  too (one step for the events a notch sends within 150 ms) unless the game binds the
  wheel (`{:mouse, :wheel_up}`, `{:mouse, :wheel_down}`), and `0` puts the zoom
  back; the zoom shows under the world while it is not
  native. Watching (joined with `w`), the arrows and a drag with the left button pan
  the view, the wheel zooms about the pointer, and `0` recentres; flying, the view
  stays on the ship and the wheel zooms about it. A page the game adds (`pages/1`)
  opens from the title on its key; `Esc` or `q` closes it.

  The view: `v` cycles the projection (top-down, oblique, isometric, mode 7, first
  person, as the game's `look/0` lists them), `[` and `]`
  turn it — the isometric facing, or the eye by 15° in first person when the scene
  gives no heading — `'` and `;` tilt the isometric diamond or pitch the eye. Four
  keys are unbound until a game binds them through `client_keys/0`: `display` toggles
  pictures against block characters, `glyphs` cycles the glyph sets, `menu` opens the game's
  own menu (its `open_menu/1`; see `Cauldron2D.Client.Game`), `mouse_look` lets
  the pointer turn and pitch the eye in first person; a drag turns and pitches it there
  whether or not `mouse_look` is on, and a click still reaches the game. What the view is, and how it is
  drawn, shows under the world when it is not the top-down default. A game's `look/0`
  sets the view it starts in.

  Each connected controller plays one of the client's players — the player itself, then
  its seats — as `Cauldron2D.Drafter.Client.Controllers` assigns them from the settings'
  `pads`, and the settings' `controllers` list them for the game's menus; a controller
  that plays no one is ignored during play, and while the game's menu is open any
  controller works it. A controller moved to another player first lets go of what it
  held for the one before.

  A controller: the left stick and d-pad hold the game's directions (`padmap/1`), the
  right stick, unless the padmap binds its axes to actions, nudges the aim a tile at a time top-down and isometric and looks around
  in first person, the triggers tilt the isometric diamond or pitch the eye — right up,
  left down, as far as they are pulled — `Start` cycles the projection and the bumpers
  turn; `client_pad/0` rebinds the client's own actions to buttons, and in the lobby
  the d-pad chooses and `A` joins. A stick the padmap binds to `:aim` aims instead,
  eight tiles from the focus in the direction it is pushed (turned with the isometric
  facing), letting go when it comes back to centre; a stick that aims does not nudge.

  Title: `Enter` plays, `s` opens settings, `h` the guide, `q` quits. Lobby: `↑`/`↓`
  pick a world, `t` a team where the world has them, `Enter` joins, `w` watches, `s`
  opens settings, `c` chats and `Enter` on an empty line leaves the chat. Settings: `↑`/`↓` move over
  the items — preset, each action's binding, pointer steering, effects level, music
  level, display (pixels where the terminal has them, braille, a block-character glyph
  set, or glyphs), frame rate
  (auto picks the terminal's best) — `←`/`→` change the item under the cursor, `Enter` on a binding then
  a key, a mouse button or a notch of the wheel adds it to the binding, `Backspace` removes the binding's last
  key, `Esc` during a rebind cancels it. World: the game's bindings; `Tab`
  opens settings without leaving the ship; the pointer steers only when pointer
  steering is on, and a key bound to one of the game's `steering/0` actions takes over
  from it until the pointer moves again.
  """

  use Drafter.App,
    key_release: true,
    cell_size: true,
    controller: true,
    mouse_hover: true,
    frame_pacing: :always

  alias Cauldron2D.{Atlas, Audio, Camera, Input, Player, Sessions, Trace, World}
  alias Cauldron2D.Audio.Music
  alias Cauldron2D.Client.Game
  alias Cauldron2D.Drafter.{Chat, Surface}
  alias Cauldron2D.Drafter.Client.{Controllers, Picture, Screens, Seats, Settings}
  alias Cauldron2D.Input.Pad
  alias Cauldron2D.Projection.Iso
  alias Cauldron2D.World.Presence
  alias Drafter.Session.Context
  alias FrenchCurve.Backend.Cells

  @hold_ms 250
  @namesakes 9
  @menu_frame_ms 100
  @audio_stop_ms 2_000
  @default_keys %{
    back: :escape,
    title: :q,
    settings: :tab,
    menu: nil,
    settings_menu: :s,
    talk: :t,
    watch: :w,
    team: :t,
    chat: :c,
    guide: :h,
    hints: :"?",
    fps: nil,
    pause: :p,
    zoom_in: [:=, :+],
    zoom_out: [:-, :_],
    zoom_reset: :"0",
    projection: :v,
    turn_left: :"[",
    turn_right: :"]",
    tilt_up: :"'",
    tilt_down: :";",
    display: nil,
    glyphs: nil,
    mouse_look: nil
  }
  @default_pad %{
    projection: :start,
    turn_left: :left_bumper,
    turn_right: :right_bumper
  }
  @look %{
    projection: :top,
    projections: [:top, :iso, :first_person],
    facings: 4,
    facing: 0,
    tilt: 1.0,
    heading: 0.0,
    pitch: 0.0,
    mouse_look?: false
  }
  @stick_aim_distance 8.0
  @mouse_turn 0.02
  @mouse_pitch 0.05
  @mouse_tilt 0.01
  @turn :math.pi() / 12
  @tilt_step 0.125
  @pitch_step 0.1
  @stick_turn 10 * :math.pi() / 18
  @stick_pitch 0.8
  @trigger_tilt 0.8
  @pan_step 4
  @traced {__MODULE__, :traced}

  @doc "The client's keys by action — a key, or a list of keys — before the game's `client_keys/0` is applied."
  @spec default_keys() :: %{atom() => atom() | [atom()]}
  def default_keys, do: @default_keys

  @impl true
  def mount(props) do
    game = Map.fetch!(props, :game)
    username = Map.get(props, :username, "player")
    kind = Map.get(props, :kind, :terminal)

    settings =
      Settings.load(game, username, %{Settings.prop_key(kind) => Map.get(props, :settings, %{})},
        kind: kind
      )

    Chat.ensure_started()
    Sessions.track(username, kind)
    look = Map.merge(@look, optional(game, :look, [], %{}))

    %{
      game: game,
      props: props,
      kind: kind,
      username: username,
      accounts: Map.get(props, :accounts),
      pages: optional(game, :pages, [props], []),
      keys: Map.merge(@default_keys, optional(game, :client_keys, [], %{})),
      pad_keys: Map.merge(@default_pad, optional(game, :client_pad, [], %{})),
      chat?: optional(game, :chat?, [], true),
      flow: flow(props, game),
      local_world: nil,
      settings: settings,
      screen: first_screen(flow(props, game)),
      return: :title,
      help?: false,
      help_pressed_at: nil,
      fps?: false,
      fps: %{frames: 0, since: now(), shown: nil},
      audio: start_audio(game, props, settings),
      input: nil,
      pad: Pad.new(padmap(game, props)),
      seats: [],
      devices: %{},
      controllers: Controllers.new(),
      player_id: nil,
      joined: nil,
      view: nil,
      geometry: nil,
      zoom: initial_zoom(game),
      look: look,
      picture: Picture.options(props, look),
      pad_aim: nil,
      stick_aim?: false,
      looked_at: nil,
      pointer: nil,
      pan: {0.0, 0.0},
      subject: nil,
      watching?: false,
      drag: nil,
      wheel_at: nil,
      lobby: %{selected: 0, messages: [], team: nil, changes: 0},
      chat_text: "",
      talk_text: "",
      talking?: false,
      talk: [],
      selected: :preset,
      summary: nil,
      menu: nil,
      menu_paused?: false,
      menu_frame: 0,
      requests: 0,
      request: nil,
      asked: nil,
      return_props: nil,
      world_ref: nil,
      summary_world: nil,
      rebinding: nil,
      cue: nil,
      last_input: nil,
      guide: %{offset: 0, rows: 16, return: :title}
    }
    |> cue_music()
  end

  @impl true
  def refresh_rate, do: "30fps"

  @impl true
  def on_ready(state) do
    Trace.start()
    Chat.join(:lobby)
    Presence.subscribe()
    Atlas.subscribe(state.game.atlas())
    apply_frame_rate(state)
    blur_pages(state)
    if state.screen == :lobby, do: Drafter.blur(:chat_input)
    state = %{state | lobby: %{state.lobby | messages: Chat.history(:lobby)}}
    begin(state.flow, state)
  end

  defp flow(props, game) do
    case Map.get(props, :start) || optional(game, :start, [], nil) || legacy_flow(game) do
      :title -> :lobby
      :lobby -> :lobby
      {:lobby, opts} -> {:lobby, opts}
      {:play, id} -> {:play, id, []}
      {:play, id, opts} -> {:play, id, opts}
      fun when is_function(fun, 1) -> fun
    end
  end

  defp legacy_flow(game) do
    if optional(game, :lobby?, [], true), do: :lobby, else: {:play, :first, title: true}
  end

  defp first_screen(:lobby), do: :title

  defp first_screen({:lobby, opts}),
    do: if(Keyword.get(opts, :title, true), do: :title, else: :lobby)

  defp first_screen({:play, _id, opts}),
    do: if(Keyword.get(opts, :title, false), do: :title, else: :play)

  defp first_screen(fun) when is_function(fun, 1), do: :lobby

  defp begin({:play, id, opts}, state) do
    if Keyword.get(opts, :title, false), do: state, else: enter(state, id)
  end

  defp begin(fun, state) when is_function(fun, 1), do: fun.(state)
  defp begin(_lobby, state), do: state

  @doc """
  Join world `id` of the game's `worlds/1`, or the first when `id` is `:first`, with
  `props` merged into the join; the client then shows the world. With no such world the
  state comes back unchanged.
  """
  @spec enter(map(), term(), map()) :: map()
  def enter(state, id, props \\ %{}) do
    case pick_world(worlds(state), id) do
      nil -> state
      world -> join(%{state | screen: :lobby}, world, props)
    end
  end

  defp pick_world([first | _], :first), do: first
  defp pick_world(worlds, id), do: Enum.find(worlds, &(&1.id == id))

  @doc "Show the guide, returning to the screen the client is on."
  @spec to_guide(map()) :: map()
  def to_guide(state), do: guide(state)

  @doc "Show the lobby, leaving any world the player is in."
  @spec to_lobby(map()) :: map()
  def to_lobby(state), do: lobby(state)

  @doc "Show the title, leaving any world the player is in."
  @spec to_title(map()) :: map()
  def to_title(state), do: title(state)

  @doc "Where leaving the world goes for the flow in force: the lobby, the title, or out."
  @spec home(map()) :: :lobby | :title | :stop
  def home(%{flow: :lobby}), do: :lobby
  def home(%{flow: {:lobby, _opts}}), do: :lobby

  def home(%{flow: {:play, _id, opts}}),
    do: if(Keyword.get(opts, :title, false), do: :title, else: :stop)

  def home(%{flow: fun}) when is_function(fun, 1), do: :stop

  @impl true
  def unmount(state) do
    leave_world(state)
    if state.audio, do: stop_audio(state.audio)
    Trace.stop()
    :ok
  end

  defp stop_audio(audio) do
    GenServer.stop(audio, :normal, @audio_stop_ms)
  catch
    :exit, _gone -> :ok
  end

  @impl true
  def render(%{screen: :title} = state), do: Screens.title(state)
  def render(%{screen: :lobby} = state), do: Screens.lobby(state)
  def render(%{screen: :settings} = state), do: Screens.settings(state)
  def render(%{screen: {:page, key}} = state), do: Screens.page(state, key)
  def render(%{screen: :guide} = state), do: Screens.guide(state)
  def render(%{screen: :play} = state), do: Screens.play(state)
  def render(%{screen: :summary} = state), do: Screens.summary(state)

  @impl true
  def handle_event(:play_geometry, geometry, state),
    do: {:noreply, %{state | geometry: geometry}}

  def handle_event(:guide_geometry, %{size: {_columns, rows}}, state) when rows > 0,
    do: {:ok, %{state | guide: %{state.guide | rows: rows}}}

  def handle_event(:guide_geometry, _geometry, state), do: {:noreply, state}

  def handle_event(:talk_submit, _text, state) do
    case String.trim(state.talk_text) do
      "" -> :ok
      text -> Chat.say({:world, state.joined.id}, said_as(state), text)
    end

    Drafter.blur(:talk_input)
    {:ok, %{state | talk_text: "", talking?: false}}
  end

  def handle_event({:page, key}, _data, %{screen: :title} = state), do: {:ok, to_page(state, key)}

  def handle_event(:chat_submit, _text, state) do
    case String.trim(state.chat_text) do
      "" -> Drafter.blur(:chat_input)
      text -> Chat.say(:lobby, said_as(state), text)
    end

    {:ok, %{state | chat_text: ""}}
  end

  def handle_event(_name, _data, state), do: {:noreply, state}

  @impl true
  def handle_event({:key, :q, [:ctrl]}, _state), do: {:stop, :normal}
  def handle_event({:key, :c, [:ctrl]}, _state), do: {:stop, :normal}

  def handle_event({:key_release_support, true} = event, state) do
    now = now()

    {:ok,
     %{
       state
       | input: state.input && Input.handle(state.input, event, now),
         seats: Seats.key(state.seats, event, now)
     }}
  end

  def handle_event({:cell_size, _}, state), do: {:noreply, state}

  def handle_event({:controller, event}, %{rebinding: nil, talking?: false} = state),
    do: pad_event(event, state)

  def handle_event({:controller, _event}, state), do: {:noreply, state}

  def handle_event({:key, key} = event, %{rebinding: nil} = state) when is_atom(key) do
    if key == state.keys.hints and key != nil,
      do: {:ok, %{state | help?: not state.help?, help_pressed_at: now()}},
      else: screen_key(event, state)
  end

  def handle_event({:key_up, key, _mods}, %{help_pressed_at: at} = state)
      when key in [:"?", :/] and at != nil, do: {:ok, help_released(state)}

  def handle_event(event, state), do: screen_key(event, state)

  defp screen_key({:key, :enter}, %{screen: :title} = state), do: {:ok, play(state)}

  defp screen_key({:key, key}, %{screen: :title} = state) do
    cond do
      key in [state.keys.back, state.keys.title] -> {:stop, :normal}
      key == state.keys.settings_menu -> {:ok, to_settings(state)}
      key == state.keys.guide -> {:ok, to_guide(state)}
      page = Enum.find(state.pages, &(&1.key == key)) -> {:ok, to_page(state, page.key)}
      true -> {:noreply, state}
    end
  end

  defp screen_key(_event, %{screen: :title} = state), do: {:noreply, state}

  defp screen_key({:key, key}, %{screen: {:page, _}} = state) when key in [:escape, :q],
    do: {:ok, to_title(state)}

  defp screen_key(_event, %{screen: {:page, _}} = state), do: {:noreply, state}

  defp screen_key(event, %{screen: :guide} = state), do: guide_key(event, state)
  defp screen_key(event, %{screen: :lobby} = state), do: lobby_key(event, state)
  defp screen_key(event, %{screen: :settings} = state), do: settings_key(event, state)

  defp screen_key(event, %{screen: :play, menu: menu} = state) when menu != nil,
    do: menu_event(event, state)

  defp screen_key(event, %{screen: :play} = state), do: play_event(event, state)
  defp screen_key({:key, :enter}, %{screen: :summary} = state), do: after_summary(state)

  defp screen_key({:key, key}, %{screen: :summary} = state) do
    cond do
      key == state.keys.back -> leave(state)
      key == state.keys.title -> leave(state)
      true -> {:noreply, state}
    end
  end

  defp screen_key(_event, state), do: {:noreply, state}

  defp blur_pages(%{pages: pages}), do: Enum.each(pages, &Drafter.blur(:"page_#{&1.key}"))

  defp to_page(state, key) do
    Drafter.blur(:"page_#{key}")
    %{state | screen: {:page, key}}
  end

  defp said_as(%{game: game, username: username}), do: Screens.player_label(game, username)

  @impl true
  def on_timer(:menu_frame, %{menu: nil} = state), do: state

  def on_timer(:menu_frame, state) do
    Drafter.set_timeout(@menu_frame_ms, :menu_frame)
    %{state | menu_frame: state.menu_frame + 1}
  end

  def on_timer(_timer, state), do: state

  @impl true
  def on_message({:cauldron_frame, frame}, %{joined: joined} = state) when joined != nil do
    Trace.write(:frame, tick: frame.tick)

    state =
      %{
        state
        | view: frame.view,
          input: Input.expire(state.input, now()),
          seats: Seats.expire(state.seats, now()),
          fps: counted(state.fps, now())
      }
      |> followed()
      |> looked(now())
      |> stick_aimed(Pad.aim(state.pad))

    Audio.listener(state.audio, state.game.listener(frame.view))
    Audio.play(state.audio, frame.events)
    state = answer(state, Game.optional(state.game, :ask, [frame.view], nil))

    case outcome(state, frame.view) do
      nil ->
        state |> push_input() |> push_seats() |> cue_music()

      summary ->
        state
        |> Map.put(:summary_world, state.joined)
        |> leave_world()
        |> Map.merge(%{screen: :summary, summary: summary, view: frame.view})
        |> cue_music()
    end
  end

  def on_message({:chat, {:world, _id}, message}, state) do
    %{state | talk: Enum.take(state.talk ++ [message], -20)}
  end

  def on_message({:cauldron_atlas, _name, :changed}, state), do: state

  def on_message({:cauldron_players, _world, _change, _id}, state) do
    %{state | lobby: %{state.lobby | changes: state.lobby.changes + 1}}
  end

  def on_message({:chat, :lobby, message}, state), do: noted(state, message)

  def on_message({:DOWN, ref, :process, _world, _reason}, %{world_ref: ref} = state)
      when state.return_props != nil,
      do: returned(%{state | world_ref: nil})

  def on_message({:DOWN, ref, :process, _world, _reason}, %{world_ref: ref} = state),
    do: world_gone(state)

  def on_message(_message, state), do: state

  defp counted(%{frames: frames, since: since} = fps, at) when at - since >= 1000,
    do: %{fps | frames: 0, since: at, shown: frames + 1}

  defp counted(fps, _at), do: %{fps | frames: fps.frames + 1}

  defp help_released(%{help_pressed_at: at} = state) when at != nil do
    if now() - at >= @hold_ms,
      do: %{state | help?: false, help_pressed_at: nil},
      else: %{state | help_pressed_at: nil}
  end

  defp play(%{flow: {:play, id, _opts}} = state), do: enter(state, id)
  defp play(state), do: lobby(state)

  defp lobby(state) do
    Drafter.blur(:chat_input)
    state |> leave_world() |> Map.put(:screen, :lobby) |> cue_music()
  end

  defp title(state) do
    blur_pages(state)
    state |> leave_world() |> Map.put(:screen, :title) |> cue_music()
  end

  defp leave(state) do
    case home(state) do
      :lobby -> {:ok, lobby(state)}
      :title -> {:ok, title(state)}
      :stop -> {:stop, :normal}
    end
  end

  @doc "The game's worlds, from its `worlds/1` given the mount props."
  @spec worlds(map()) :: [Game.world()]
  def worlds(%{game: game} = state), do: game.worlds(Map.get(state, :props, %{}))

  defp guide(%{screen: from} = state) do
    Drafter.blur(:chat_input)
    blur_pages(state)

    if Code.ensure_loaded?(state.game) and function_exported?(state.game, :guide, 0),
      do: %{state | screen: :guide, guide: %{state.guide | offset: 0, return: from}},
      else: state
  end

  defp guide_key({:key, key}, %{guide: %{return: return}} = state) when key in [:escape, :q],
    do: {:ok, %{state | screen: return}}

  defp guide_key({:key, key}, state) when key in [:down, :j], do: {:ok, scroll_guide(state, 1)}
  defp guide_key({:key, key}, state) when key in [:up, :k], do: {:ok, scroll_guide(state, -1)}
  defp guide_key({:key, :page_down}, state), do: {:ok, scroll_guide(state, state.guide.rows)}
  defp guide_key({:key, :page_up}, state), do: {:ok, scroll_guide(state, -state.guide.rows)}
  defp guide_key({:key, :home}, state), do: {:ok, scroll_guide(state, -state.guide.offset)}

  defp guide_key({:key, :end}, state),
    do: {:ok, scroll_guide(state, Screens.guide_length(state.game))}

  defp guide_key({:mouse, %{type: :scroll, direction: :down}}, state),
    do: {:ok, scroll_guide(state, 3)}

  defp guide_key({:mouse, %{type: :scroll, direction: :up}}, state),
    do: {:ok, scroll_guide(state, -3)}

  defp guide_key(_event, state), do: {:noreply, state}

  defp scroll_guide(%{guide: guide} = state, delta) do
    furthest = max(0, Screens.guide_length(state.game) - guide.rows)

    %{
      state
      | guide: %{guide | offset: guide.offset |> Kernel.+(delta) |> max(0) |> min(furthest)}
    }
  end

  defp to_settings(%{screen: from} = state) do
    Drafter.blur(:chat_input)

    state
    |> release_keys()
    |> Map.merge(%{screen: :settings, return: from, rebinding: nil})
    |> cue_music()
  end

  defp leave_settings(%{return: :play, joined: joined} = state) when joined != nil do
    %{state | screen: :play, input: new_input(state)}
  end

  defp leave_settings(%{return: :play} = state), do: %{state | screen: :lobby}
  defp leave_settings(%{return: screen} = state), do: %{state | screen: screen}

  defp release_keys(%{input: nil} = state), do: state

  defp release_keys(state) do
    seats = Seats.release(state.seats, local_seats(state), input_options(state))
    %{state | input: new_input(state), seats: seats} |> push_input() |> push_seats()
  end

  defp new_input(state), do: Input.new(state.settings.bindings, input_options(state))

  defp input_options(state) do
    [
      releases?: Context.key_release?(),
      toggles: state.game.toggles(),
      holds: optional(state.game, :holds, []),
      steering: optional(state.game, :steering, [])
    ] ++ optional(state.game, :input_options, [options_of(state)], [])
  end

  defp local_seats(state),
    do: optional(state.game, :local_seats, [Map.put(state.props, :settings, state.settings)], [])

  defp join_seats(state, props) do
    seats =
      Seats.join(
        state.joined.world,
        state.player_id,
        props,
        local_seats(state),
        padmap(state.game, state.props),
        input_options(state)
      )

    assign_controllers(%{state | seats: seats})
  end

  defp push_seats(%{joined: nil} = state), do: state
  defp push_seats(%{seats: []} = state), do: state

  defp push_seats(state) do
    look = look(state)
    %{state | seats: Seats.send_input(state.seats, state.joined.world, &steered(&1, look))}
  end

  defp lobby_key({:mouse, %{type: :scroll, direction: :down}}, state), do: {:ok, select(state, 1)}
  defp lobby_key({:mouse, %{type: :scroll, direction: :up}}, state), do: {:ok, select(state, -1)}

  defp lobby_key({:mouse, %{type: :mouse_down, button: :left, y: y}}, state) do
    case Screens.world_at(worlds(state), state.lobby.selected, y) do
      nil -> {:noreply, state}
      index when index == state.lobby.selected -> {:ok, join_selected(state, team_props(state))}
      index -> {:ok, %{state | lobby: %{state.lobby | selected: index}}}
    end
  end

  defp lobby_key({:key, :down}, state), do: {:ok, select(state, 1)}
  defp lobby_key({:key, :up}, state), do: {:ok, select(state, -1)}
  defp lobby_key({:key, :j}, state), do: {:ok, select(state, 1)}
  defp lobby_key({:key, :k}, state), do: {:ok, select(state, -1)}
  defp lobby_key({:key, :page_down}, state), do: {:ok, select(state, Screens.lobby_window())}
  defp lobby_key({:key, :page_up}, state), do: {:ok, select(state, -Screens.lobby_window())}
  defp lobby_key({:key, :home}, state), do: {:ok, select(state, -state.lobby.selected)}

  defp lobby_key({:key, :end}, state),
    do: {:ok, select(state, length(worlds(state)) - 1 - state.lobby.selected)}

  defp lobby_key({:key, :enter}, state), do: {:ok, join_selected(state, team_props(state))}

  @lobby_actions [:team, :watch, :settings_menu, :guide, :chat, :back, :title]

  defp lobby_key({:key, key}, state),
    do: lobby_action(client_action(state.keys, key, @lobby_actions), state)

  defp lobby_key(_event, state), do: {:noreply, state}

  defp lobby_action(:team, state), do: {:ok, cycle_team(state)}
  defp lobby_action(:watch, state), do: {:ok, join_selected(state, %{spectate: true})}
  defp lobby_action(:settings_menu, state), do: {:ok, to_settings(state)}
  defp lobby_action(:guide, state), do: {:ok, to_guide(state)}
  defp lobby_action(:chat, %{chat?: true} = state), do: focus_chat(state)

  defp lobby_action(leave, %{flow: :lobby} = state) when leave in [:back, :title],
    do: {:ok, title(state)}

  defp lobby_action(leave, %{flow: {:lobby, opts}} = state) when leave in [:back, :title],
    do: if(Keyword.get(opts, :title, true), do: {:ok, title(state)}, else: {:stop, :normal})

  defp lobby_action(leave, _state) when leave in [:back, :title], do: {:stop, :normal}
  defp lobby_action(_action, state), do: {:noreply, state}

  defp look_actions(%{keys: keys}), do: for({:look, _key} = action <- Map.keys(keys), do: action)

  defp client_action(_keys, nil, _order), do: nil

  defp client_action(keys, key, order),
    do: Enum.find(order, &(key in List.wrap(Map.get(keys, &1))))

  defp focus_chat(state) do
    Drafter.focus(:chat_input)
    {:noreply, state}
  end

  defp team_props(%{lobby: %{team: nil}}), do: %{}
  defp team_props(%{lobby: %{team: team}}), do: %{team: team}

  defp cycle_team(state) do
    teams = worlds(state) |> Enum.at(state.lobby.selected, %{}) |> Map.get(:teams, [])
    choices = [nil | teams]
    index = Enum.find_index(choices, &(&1 == state.lobby.team)) || 0
    %{state | lobby: %{state.lobby | team: Enum.at(choices, rem(index + 1, length(choices)))}}
  end

  defp select(state, delta) do
    count = max(1, length(worlds(state)))

    selected =
      if abs(delta) > 1,
        do: state.lobby.selected |> Kernel.+(delta) |> max(0) |> min(count - 1),
        else: Integer.mod(state.lobby.selected + delta, count)

    %{state | lobby: %{state.lobby | selected: selected}}
  end

  defp join_selected(state, extra) do
    case Enum.at(worlds(state), state.lobby.selected) do
      nil -> state
      world -> join(state, world, extra)
    end
  end

  defp join(state, entry, extra) do
    game_props =
      optional(
        state.game,
        :join_props,
        [%{username: state.username, settings: state.settings}],
        %{}
      )

    props = %{username: state.username} |> Map.merge(game_props) |> Map.merge(extra)
    {entry, local} = local_world(entry)

    case join_as(entry.world, state.username, props, frame_rate(state)) do
      {:ok, player_id} ->
        Chat.join({:world, entry.id})

        state = %{
          state
          | joined: entry,
            player_id: player_id,
            local_world: local,
            world_ref: watch(entry.world),
            screen: :play,
            view: nil,
            last_input: nil,
            talk: Chat.history({:world, entry.id}),
            talking?: false,
            zoom: initial_zoom(state.game),
            pan: {0.0, 0.0},
            subject: nil,
            watching?: Map.get(extra, :spectate, false) == true,
            drag: nil
        }

        %{state | input: new_input(state)} |> join_seats(props) |> cue_music()

      {:error, reason} ->
        if local, do: GenServer.stop(local)

        noted(state, %{
          from: entry.name,
          text: "could not join: " <> Game.refusal_text(state.game, reason)
        })
    end
  end

  defp join_as(world, username, props, rate) do
    [username | Enum.map(2..@namesakes, &"#{username} (#{&1})")]
    |> Enum.reduce_while({:error, :taken}, fn id, _taken ->
      case Player.join(world, id, props, frames: rate) do
        :ok -> {:halt, {:ok, id}}
        {:error, :taken} -> {:cont, {:error, :taken}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp local_world(%{world: {module, opts}} = entry) do
    {:ok, pid} = World.start_link([game: module] ++ Keyword.drop(opts, [:name]))
    {%{entry | world: pid}, pid}
  end

  defp local_world(entry), do: {entry, nil}

  defp leave_world(%{joined: nil} = state), do: state

  defp leave_world(state) do
    try do
      Seats.leave(state.seats, state.joined.world)
      Player.leave(state.joined.world, state.player_id)
    catch
      :exit, _gone -> :ok
    end

    forget_world(state)
  end

  defp world_gone(%{joined: entry} = state) do
    state
    |> forget_world()
    |> Map.put(:screen, :lobby)
    |> noted(%{from: entry.name, text: "#{entry.name} stopped"})
  end

  defp noted(state, message),
    do: %{
      state
      | lobby: %{state.lobby | messages: Enum.take(state.lobby.messages ++ [message], -100)}
    }

  defp forget_world(state) do
    Chat.leave({:world, state.joined.id})

    if state.local_world && Process.alive?(state.local_world),
      do: GenServer.stop(state.local_world)

    if state.world_ref, do: Process.demonitor(state.world_ref, [:flush])

    %{
      state
      | joined: nil,
        world_ref: nil,
        local_world: nil,
        view: nil,
        input: nil,
        seats: [],
        devices: %{},
        talking?: false,
        zoom: initial_zoom(state.game),
        pan: {0.0, 0.0},
        subject: nil,
        watching?: false,
        drag: nil
    }
  end

  defp toggle_pause(%{local_world: world} = state) do
    if World.paused?(world), do: World.resume(world), else: World.pause(world)
    state
  end

  @doc "Whether the player's own world is paused."
  @spec paused?(map()) :: boolean()
  def paused?(%{local_world: nil}), do: false
  def paused?(%{local_world: world}), do: Process.alive?(world) and World.paused?(world)

  defp settings_key(event, %{rebinding: action} = state) when action != nil do
    case rebind_key(event) do
      nil ->
        {:noreply, state}

      :cancel ->
        {:ok, %{state | rebinding: nil}}

      key ->
        {:ok, %{state | settings: Settings.bind(state.settings, action, key), rebinding: nil}}
    end
  end

  defp settings_key({:key, :escape}, state),
    do: {:ok, state |> save_settings() |> leave_settings() |> cue_music()}

  defp settings_key({:key, :enter}, %{selected: {:action, action}} = state),
    do: {:ok, %{state | rebinding: action}}

  defp settings_key({:key, key}, %{selected: {:action, action}} = state)
       when key in [:backspace, :delete],
       do: {:ok, %{state | settings: Settings.unbind_last(state.settings, action)}}

  defp settings_key({:key, :down}, state), do: {:ok, %{state | selected: step_item(state, 1)}}
  defp settings_key({:key, :up}, state), do: {:ok, %{state | selected: step_item(state, -1)}}
  defp settings_key({:key, :right}, state), do: {:ok, adjust(state, 1)}
  defp settings_key({:key, :left}, state), do: {:ok, adjust(state, -1)}
  defp settings_key(_event, state), do: {:noreply, state}

  defp step_item(state, delta) do
    items = Settings.items(state.game)
    current = Enum.find_index(items, &(&1 == state.selected)) || 0
    Enum.at(items, Integer.mod(current + delta, length(items)))
  end

  defp adjust(%{selected: :preset} = state, delta), do: step_preset(state, delta)
  defp adjust(%{selected: {:action, _}} = state, _delta), do: state

  defp adjust(%{selected: :pointer} = state, _delta),
    do: put_settings(state, %{state.settings | pointer: not state.settings.pointer})

  defp adjust(%{selected: level} = state, delta) when level in [:sfx, :music],
    do: put_settings(state, Settings.nudge(state.settings, level, delta * 0.1))

  defp adjust(%{selected: :display} = state, delta),
    do: put_settings(state, Settings.step_display(state.settings, delta))

  defp adjust(%{selected: :fps} = state, delta) do
    state = put_settings(state, Settings.step_fps(state.settings, state.game, delta))
    apply_frame_rate(state)
    state
  end

  defp apply_frame_rate(state) do
    rate = frame_rate(state)
    Drafter.set_refresh_rate(Integer.to_string(rate) <> "fps")
    paced_frames(state, rate)
  end

  defp frame_rate(state) do
    protocol = Surface.protocol(%Surface{mode: Settings.surface_mode(state.settings)})
    placements? = FrenchCurve.Capability.placements?(Context.terminal_env())
    link = if Map.has_key?(state.props, :served_by), do: :ssh, else: :local
    Settings.frame_rate(state.settings, protocol, placements?, link)
  end

  defp paced_frames(%{joined: nil}, _rate), do: :ok

  defp paced_frames(state, rate) do
    Player.frames(state.joined.world, state.player_id, rate)
  catch
    :exit, _gone -> :ok
  end

  defp put_settings(state, settings) do
    Audio.levels(state.audio, settings.sfx, settings.music)
    assign_controllers(%{state | settings: settings})
  end

  defp step_preset(state, delta) do
    presets = Settings.presets(state.game)
    current = Enum.find_index(presets, &(&1 == state.settings.preset)) || 0
    preset = Enum.at(presets, Integer.mod(current + delta, length(presets)))
    %{state | settings: Settings.choose_preset(state.settings, state.game, preset)}
  end

  defp rebind_key({:key, :escape}), do: :cancel
  defp rebind_key({:key_down, key, _mods}) when key in [:enter, :escape, :tab], do: nil
  defp rebind_key({:key, key}) when key in [:enter, :tab], do: nil
  defp rebind_key(event), do: Input.spec_of(event)

  defp open_menu(state), do: opened_menu(state, state.game.open_menu(state.settings))

  defp open_menu(state, arg) do
    if function_exported?(state.game, :open_menu, 2),
      do: opened_menu(state, state.game.open_menu(state.settings, arg)),
      else: open_menu(state)
  end

  defp opened_menu(state, menu) do
    paused? = pause_for_menu(state.local_world)
    Drafter.set_timeout(@menu_frame_ms, :menu_frame)
    %{release_keys(state) | menu: menu, menu_paused?: paused?}
  end

  defp pause_for_menu(nil), do: false

  defp pause_for_menu(world) do
    if Process.alive?(world) and not World.paused?(world) do
      World.pause(world)
      true
    else
      false
    end
  end

  defp resume_after_menu(%{menu: nil, menu_paused?: true, local_world: world} = state) do
    if world && Process.alive?(world), do: World.resume(world)
    %{state | menu_paused?: false}
  end

  defp resume_after_menu(state), do: state

  defp menu_event(event, state) do
    if menu_input?(event) do
      result = state.game.menu_event(state.menu, event, state.settings)

      state =
        state
        |> take_menu_settings(Map.fetch!(result, :settings))
        |> Map.put(:menu, Map.get(result, :menu))
        |> resume_after_menu()
        |> menu_request(Map.get(result, :request))

      Audio.play(state.audio, Map.get(result, :sounds, []))
      if Map.get(result, :leave, false), do: leave(state), else: {:ok, state}
    else
      {:noreply, state}
    end
  end

  defp menu_input?({:key, _key}), do: true
  defp menu_input?({:key, _key, _mods}), do: true
  defp menu_input?({:mouse, %{type: type}}), do: type in [:mouse_down, :scroll]
  defp menu_input?(_event), do: false

  defp menu_pad_key(:dpad_up), do: :up
  defp menu_pad_key(:dpad_down), do: :down
  defp menu_pad_key(:dpad_left), do: :left
  defp menu_pad_key(:dpad_right), do: :right
  defp menu_pad_key(:a), do: :enter
  defp menu_pad_key(button) when button in [:b, :start], do: :escape
  defp menu_pad_key(_button), do: nil

  defp take_menu_settings(%{settings: settings} = state, settings), do: state

  defp take_menu_settings(state, settings) do
    state
    |> put_settings(settings)
    |> save_settings()
    |> release_keys()
  end

  defp answer(state, nil), do: state
  defp answer(%{asked: number} = state, {number, _ask}), do: state

  defp answer(state, {number, :quit}) do
    send(self(), :shutdown)
    %{state | asked: number}
  end

  defp answer(%{menu: nil} = state, {number, :menu}) do
    if function_exported?(state.game, :open_menu, 1),
      do: open_menu(%{state | asked: number}),
      else: %{state | asked: number}
  end

  defp answer(%{menu: nil} = state, {number, {:menu, arg}}) do
    if function_exported?(state.game, :open_menu, 1) or
         function_exported?(state.game, :open_menu, 2),
       do: open_menu(%{state | asked: number}, arg),
       else: %{state | asked: number}
  end

  defp answer(state, {number, {:enter, props}}) do
    returning = state.return_props || state.props
    state = leave_world(%{state | asked: number})
    enter(%{state | props: Map.merge(state.props, props), return_props: returning}, :first)
  end

  defp answer(state, {number, _ask}), do: %{state | asked: number}

  defp returned(%{return_props: props} = state) do
    state = leave_world(state)
    enter(%{state | props: props, return_props: nil}, :first)
  end

  defp watch(world) do
    case GenServer.whereis(world) do
      pid when is_pid(pid) -> Process.monitor(pid)
      _none -> nil
    end
  end

  defp menu_request(state, nil), do: state

  defp menu_request(state, request) do
    count = state.requests + 1
    push_input(%{state | requests: count, request: {count, request}})
  end

  defp options_of(%{settings: %{options: options}}), do: options
  defp options_of(_state), do: %{}

  defp save_settings(state) do
    Settings.save(state.settings, state.game, state.username, state.accounts, kind: state.kind)
    state
  end

  defp play_event({:key, :escape}, %{talking?: true} = state) do
    Drafter.blur(:talk_input)
    {:ok, %{state | talking?: false, talk_text: ""}}
  end

  defp play_event(_event, %{talking?: true} = state), do: {:noreply, state}

  @play_actions [
    :back,
    :title,
    :settings,
    :menu,
    :fps,
    :pause,
    :talk,
    :zoom_in,
    :zoom_out,
    :zoom_reset,
    :projection,
    :turn_left,
    :turn_right,
    :tilt_up,
    :tilt_down,
    :display,
    :glyphs,
    :mouse_look
  ]
  @pans %{left: {-1, 0}, right: {1, 0}, up: {0, -1}, down: {0, 1}}

  defp play_event({:key, key}, %{watching?: true} = state) when is_map_key(@pans, key) do
    {dx, dy} = Map.fetch!(@pans, key)
    {:ok, pan_by(state, {dx * @pan_step / state.zoom, dy * @pan_step / state.zoom})}
  end

  defp play_event({:key, key} = event, state),
    do:
      play_action(
        client_action(state.keys, key, @play_actions ++ look_actions(state)),
        event,
        state
      )

  @wheel_ms 150

  defp play_event({:mouse, %{px: {px, py}} = payload}, %{look: %{projection: :picture}} = state) do
    payload = Map.delete(payload, :px)

    case Context.cell_size() do
      {cell_width, cell_height} ->
        play_event({:mouse, %{payload | x: px / cell_width, y: py / cell_height}}, state)

      nil ->
        play_event({:mouse, payload}, state)
    end
  end

  defp play_event({:mouse, %{type: :scroll, direction: direction}} = event, state)
       when direction in [:up, :down] do
    if game_wheel?(state, direction),
      do: play_input(event, state),
      else: zoom_wheel(event, state)
  end

  defp play_event(
         {:mouse, %{type: :mouse_down, button: :left, x: x, y: y}},
         %{watching?: true} = state
       ),
       do: {:ok, %{state | drag: {x, y}}}

  defp play_event(
         {:mouse, %{type: :drag, x: x, y: y}},
         %{watching?: true, drag: {fx, fy}} = state
       ),
       do:
         {:ok,
          pan_by(%{state | drag: {x, y}}, {(fx - x) / (2 * state.zoom), (fy - y) / state.zoom})}

  defp play_event({:mouse, %{type: :mouse_up}}, %{watching?: true, drag: drag} = state)
       when drag != nil,
       do: {:ok, %{state | drag: nil}}

  defp play_event({:mouse, %{type: :mouse_down, x: x, y: y}} = event, %{look: look} = state) do
    if turns_with_pointer?(look),
      do: play_input(event, %{state | pointer: {x, y}}),
      else: play_input(event, state)
  end

  defp play_event(
         {:mouse, %{type: :drag, button: :left, x: x, y: y}} = event,
         %{look: look} = state
       ) do
    if turns_with_pointer?(look),
      do: turn_eye(event, state, {x, y}),
      else: play_input(event, state)
  end

  defp play_event({:mouse, %{type: :drag, x: x, y: y}} = event, state),
    do: play_input(event, %{state | pointer: {x, y}})

  defp play_event({:mouse, %{type: :move, x: x, y: y}} = event, %{look: look} = state) do
    if turns_with_pointer?(look) and look.mouse_look?,
      do: turn_eye(event, state, {x, y}),
      else: play_input(event, %{state | pointer: {x, y}, pad_aim: nil})
  end

  defp play_event(event, state), do: play_input(event, state)

  defp game_wheel?(%{watching?: true}, _direction), do: false
  defp game_wheel?(%{input: nil}, _direction), do: false
  defp game_wheel?(state, :up), do: Input.binds?(state.input, {:mouse, :wheel_up})
  defp game_wheel?(state, :down), do: Input.binds?(state.input, {:mouse, :wheel_down})

  defp zoom_wheel({:mouse, %{direction: direction} = mouse}, state) do
    at = now()

    if state.wheel_at != nil and at - state.wheel_at < @wheel_ms do
      {:noreply, state}
    else
      step = if direction == :up, do: 1, else: -1

      {:ok,
       zoom_step(%{state | wheel_at: at}, step, if(state.watching?, do: pane_cell(state, mouse)))}
    end
  end

  @doc """
  Whether a drag with the left button turns the view the look describes: it does in first
  person and mode 7, and in the isometric view when the game offers more than four
  facings. At four facings the view steps in quarters and there is nothing to drag to.

  Only the left button. A drag with any other belongs to the game, which may have bound it
  to an action whose aim must stay where the player put it: turning the view under a held
  button moves the world out from under the pointer, so the release lands somewhere the
  player never pointed at.
  """
  @spec turns_with_pointer?(map()) :: boolean()
  def turns_with_pointer?(%{projection: projection}) when projection in [:first_person, :mode7],
    do: true

  def turns_with_pointer?(%{projection: :iso} = look), do: facings_of(look) > 4
  def turns_with_pointer?(_look), do: false

  defp facings_of(%{projection: projection} = look) do
    case Map.get(look, :facings) do
      counts when is_map(counts) -> Map.get(counts, projection, fixed(projection))
      nil -> fixed(projection)
      count -> if projection == :oblique, do: fixed(projection), else: count
    end
  end

  defp fixed(:oblique), do: 1
  defp fixed(_projection), do: 4

  defp turn_eye(event, %{pointer: {px, py}} = state, {x, y}),
    do:
      play_input(event, %{
        state
        | look: dragged(state.look, {x - px, y - py}),
          pointer: {x, y},
          pad_aim: nil
      })

  defp turn_eye(event, state, {x, y}),
    do: play_input(event, %{state | pointer: {x, y}, pad_aim: nil})

  defp dragged(%{projection: :iso} = look, {dx, dy}) do
    facings = facings_of(look)
    steps = dx * @mouse_turn * facings / (2 * :math.pi())

    %{
      look
      | facing: :math.fmod(:math.fmod(look.facing + steps, facings) + facings, facings),
        tilt: (look.tilt - dy * @mouse_tilt) |> min(1.5) |> max(0.5)
    }
  end

  defp dragged(%{projection: :mode7} = look, {dx, dy}),
    do: %{
      look
      | heading: look.heading + dx * @mouse_turn,
        pitch: (look.pitch - dy * @mouse_pitch) |> min(0.8) |> max(-0.8)
    }

  defp dragged(look, {dx, dy}),
    do: %{
      look
      | heading: look.heading + dx * @mouse_turn,
        pitch: (look.pitch - dy * @mouse_pitch) |> min(1.0) |> max(-1.0)
    }

  defp pane_cell(%{geometry: nil}, _mouse), do: nil
  defp pane_cell(%{geometry: %{rect: rect}}, %{x: x, y: y}), do: {x - rect.x, y - rect.y}

  defp pan_by(%{pan: {px, py}} = state, {dx, dy}),
    do: %{followed(state) | pan: {px + dx, py + dy}}

  defp followed(%{pan: {px, py}, view: view} = state)
       when view != nil and px == 0 and py == 0,
       do: %{state | subject: Map.get(scene(state), :subject)}

  defp followed(%{view: view} = state) when view != nil, do: follow(state, scene(state))

  defp followed(state), do: state

  @doc "The game's scene for the client's view and look: `scene/2` where the game defines it, else `scene/1`."
  @spec scene(map()) :: Game.scene()
  def scene(%{game: game, view: view} = state) do
    if function_exported?(game, :scene, 2),
      do: game.scene(view, look(state)),
      else: game.scene(view)
  end

  @doc "The state with its pan dropped when the scene's `:subject` is not the one the pan was taken on; a scene with no subject keeps the pan."
  @spec follow(map(), Game.scene()) :: map()
  def follow(%{subject: subject} = state, %{subject: subject}), do: state
  def follow(state, %{subject: subject}), do: %{state | pan: {0.0, 0.0}, subject: subject}
  def follow(state, _scene), do: state

  @doc "The zoom levels this client steps through: `Cauldron2D.Drafter.Surface.zoom_levels/3` for the game's atlas, the display in use and the projection in view."
  @spec zoom_levels(map()) :: [number()]
  def zoom_levels(%{game: game, settings: settings} = state),
    do: Surface.zoom_levels(game.atlas(), Settings.surface_mode(settings), look(state).projection)

  defp zoom_step(state, step, anchor) do
    levels = zoom_levels(state)
    index = Enum.find_index(levels, &(&1 == state.zoom)) || Enum.find_index(levels, &(&1 == 1))
    zoom_to(state, Enum.at(levels, min(max(index - step, 0), length(levels) - 1)), anchor)
  end

  defp initial_zoom(game), do: game |> optional(:look, [], %{}) |> Map.get(:zoom, 1)

  defp zoom_to(%{zoom: zoom} = state, zoom, _anchor), do: state

  defp zoom_to(
         %{geometry: %{size: size}, view: view, zoom: from} = state,
         to,
         {_, _} = cell
       )
       when view != nil do
    scene = scene(state)
    {fx, fy} = scene.focus
    {px, py} = state.pan
    {nx, ny} = Camera.zoom_about({fx + px, fy + py}, cell, size, from, to)
    %{state | zoom: to, pan: {nx - fx, ny - fy}, subject: Map.get(scene, :subject)}
  end

  defp zoom_to(state, to, _anchor), do: %{state | zoom: to}

  @doc "The point the world is drawn around: the scene's focus moved by the pan."
  @spec focus(map(), Game.scene()) :: {number(), number()}
  def focus(%{pan: {px, py}}, %{focus: {fx, fy}}), do: {fx + px, fy + py}
  def focus(_state, %{focus: focus}), do: focus

  @doc """
  How far above the ground the camera sits for a scene, in tiles, or `nil` to leave the
  projection its own.

  The scene's `:eye` says it: a height in tiles, or the art whose eyes they are, whose
  own `Cauldron2D.Atlas.eye_height/2` is then used. A game that draws figures of
  different heights gives the art, so each player sees the world from their own height.
  """
  @spec eye_height(module(), Game.scene()) :: number() | nil
  def eye_height(game, scene) do
    case Map.get(scene, :eye) do
      nil -> nil
      tiles when is_number(tiles) -> tiles
      art -> Atlas.eye_height(Atlas.fetch(game.atlas()), art)
    end
  end

  defp play_action(leave, _event, state) when leave in [:back, :title], do: leave(state)

  defp play_action(:settings, _event, state), do: {:ok, to_settings(state)}

  defp play_action(:menu, event, state) do
    if Code.ensure_loaded?(state.game) and function_exported?(state.game, :open_menu, 1),
      do: {:ok, open_menu(state)},
      else: play_input(event, state)
  end

  defp play_action(:fps, _event, state), do: {:ok, %{state | fps?: not state.fps?}}
  defp play_action(:zoom_in, _event, state), do: {:ok, zoom_step(state, 1, nil)}
  defp play_action(:zoom_out, _event, state), do: {:ok, zoom_step(state, -1, nil)}
  defp play_action(:zoom_reset, _event, state), do: {:ok, %{state | zoom: 1, pan: {0.0, 0.0}}}
  defp play_action(:projection, _event, state), do: {:ok, cycle_projection(state)}
  defp play_action(:turn_left, _event, state), do: {:ok, turn(state, -1)}
  defp play_action(:turn_right, _event, state), do: {:ok, turn(state, 1)}
  defp play_action(:tilt_up, _event, state), do: {:ok, tilt(state, 1)}
  defp play_action(:tilt_down, _event, state), do: {:ok, tilt(state, -1)}

  defp play_action({:look, key}, _event, %{look: look} = state),
    do: {:ok, %{state | look: Map.update(look, key, true, &(not &1))}}

  defp play_action(:display, _event, state), do: {:ok, toggle_display(state)}
  defp play_action(:glyphs, _event, state), do: {:ok, next_glyphs(state)}

  defp play_action(:mouse_look, _event, state), do: {:ok, toggle_mouse_look(state)}

  defp play_action(:pause, _event, %{local_world: world} = state) when world != nil,
    do: {:ok, toggle_pause(state)}

  defp play_action(:talk, _event, %{chat?: true, joined: joined} = state) when joined != nil,
    do: talk(state)

  defp play_action(_action, event, state), do: play_input(event, state)

  @doc "The client's projection settings for the world: projection, facing, tilt, heading and pitch, as `Cauldron2D.Drafter.Surface` takes them."
  @spec look(map()) :: map()
  def look(%{look: look} = state),
    do:
      Map.merge(look, %{
        menu: Map.get(state, :menu),
        menu_frame: Map.get(state, :menu_frame, 0),
        options: options_of(state)
      })

  def look(_state), do: @look

  defp cycle_projection(%{look: %{projections: projections} = look} = state) do
    index = Enum.find_index(projections, &(&1 == look.projection)) || 0
    next = Enum.at(projections, rem(index + 1, length(projections)))
    %{state | look: %{look | projection: next}}
  end

  defp looked(%{looked_at: since} = state, now) when is_integer(since) do
    seconds = (now - since) / 1000

    state
    |> stick_looked(seconds)
    |> trigger_tilted(seconds)
    |> Map.put(:looked_at, now)
  end

  defp looked(state, now), do: %{state | looked_at: now}

  defp stick_looked(%{look: %{projection: :first_person} = look} = state, seconds) do
    {x, y} = {Pad.axis(state.pad, :right_x), Pad.axis(state.pad, :right_y)}

    look = %{
      look
      | heading: look.heading + x * @stick_turn * seconds,
        pitch: (look.pitch - y * @stick_pitch * seconds) |> min(1.0) |> max(-1.0)
    }

    %{state | look: look}
  end

  defp stick_looked(state, _seconds), do: state

  defp trigger_tilted(state, seconds) do
    pull = Pad.axis(state.pad, :right_trigger) - Pad.axis(state.pad, :left_trigger)

    if pull == 0.0,
      do: state,
      else: tilted_by(state, pull * @trigger_tilt * seconds)
  end

  defp tilted_by(%{look: %{projection: :iso} = look} = state, amount),
    do: %{state | look: %{look | tilt: (look.tilt + amount) |> min(1.5) |> max(0.5)}}

  defp tilted_by(%{look: %{projection: :first_person} = look} = state, amount),
    do: %{state | look: %{look | pitch: (look.pitch + amount) |> min(1.0) |> max(-1.0)}}

  defp tilted_by(state, _amount), do: state

  defp turn(%{look: %{projection: :iso} = look} = state, steps), do: stepped(state, look, steps)

  defp turn(%{look: %{projection: :oblique} = look} = state, steps),
    do: stepped(state, look, steps)

  defp turn(%{look: %{projection: :mode7} = look} = state, amount),
    do: %{state | look: %{look | heading: look.heading + amount * @turn}}

  defp turn(%{look: %{projection: :first_person} = look} = state, amount),
    do: %{state | look: %{look | heading: look.heading + amount * @turn}}

  defp turn(state, _amount), do: state

  defp stepped(state, look, steps) do
    facings = facings_of(look)
    turned = look.facing + steps

    wrapped =
      if is_integer(turned),
        do: Integer.mod(turned, facings),
        else: :math.fmod(:math.fmod(turned, facings) + facings, facings)

    %{state | look: %{look | facing: wrapped}}
  end

  defp tilt(%{look: %{projection: :iso} = look} = state, amount),
    do: %{state | look: %{look | tilt: (look.tilt + amount * @tilt_step) |> min(1.5) |> max(0.5)}}

  defp tilt(%{look: %{projection: :mode7} = look} = state, amount),
    do: %{
      state
      | look: %{look | pitch: (look.pitch + amount * @pitch_step) |> min(0.8) |> max(-0.8)}
    }

  defp tilt(%{look: %{projection: :first_person} = look} = state, amount),
    do: %{
      state
      | look: %{look | pitch: (look.pitch + amount * @pitch_step) |> min(1.0) |> max(-1.0)}
    }

  defp tilt(state, _amount), do: state

  defp talk(state) do
    Drafter.focus(:talk_input)
    {:ok, %{state | talking?: true, input: new_input(state)} |> push_input()}
  end

  defp play_input(event, %{input: input} = state) when input != nil do
    trace_event(event)
    now = now()

    {:ok,
     %{state | input: Input.handle(input, event, now), seats: Seats.key(state.seats, event, now)}
     |> push_input()
     |> push_seats()}
  end

  defp play_input(_event, state), do: {:noreply, state}

  defp padmap(game, props),
    do: optional(game, :padmap, [props], Pad.default_map(game.actions()))

  defp pad_event(%{type: :connected, device: device, name: name}, state) do
    controllers = Controllers.connect(state.controllers, device, name)
    {:ok, assign_controllers(%{state | controllers: controllers})}
  end

  defp pad_event(%{type: :disconnected, device: device} = event, state) do
    slot = Map.get(state.devices, device, 0)
    state = %{state | controllers: Controllers.disconnect(state.controllers, device)}

    if slot == 0,
      do: own_pad_event(event, assign_controllers(state)),
      else: {:ok, state |> release_device(slot, event) |> assign_controllers() |> push_seats()}
  end

  defp pad_event(%{device: device} = event, %{screen: :play, menu: nil} = state) do
    state = known(state, device)

    case Map.get(state.devices, device) do
      0 -> own_pad_event(event, state)
      nil -> {:noreply, state}
      slot -> {:ok, push_seats(%{state | seats: Seats.controller(state.seats, slot - 1, event)})}
    end
  end

  defp pad_event(event, state), do: own_pad_event(event, state)

  defp known(state, device) do
    if Controllers.known?(state.controllers, device),
      do: state,
      else:
        assign_controllers(%{state | controllers: Controllers.seen(state.controllers, device)})
  end

  defp assign_controllers(state) do
    slots = Controllers.slots(state.controllers, state.settings.pads, 1 + length(state.seats))

    state =
      Enum.reduce(state.devices, state, fn {device, slot}, state ->
        if Map.get(slots, device) == slot,
          do: state,
          else: release_device(state, slot, %{type: :disconnected, device: device})
      end)

    settings = %{state.settings | controllers: Controllers.listed(state.controllers, slots)}
    %{state | devices: slots, settings: settings}
  end

  defp release_device(state, nil, _event), do: state
  defp release_device(state, 0, event), do: %{state | pad: Pad.handle(state.pad, event)}

  defp release_device(state, slot, event),
    do: %{state | seats: Seats.controller(state.seats, slot - 1, event)}

  defp own_pad_event(event, state) do
    pad = Pad.handle(state.pad, event)
    pad_screen(event, %{state | pad: pad})
  end

  defp pad_screen(
         %{type: :button, pressed: true, button: button},
         %{screen: :play, menu: menu} = state
       )
       when menu != nil do
    case menu_pad_key(button) do
      nil -> {:noreply, state}
      key -> menu_event({:key, key}, state)
    end
  end

  defp pad_screen(_event, %{screen: :play, menu: menu} = state) when menu != nil,
    do: {:noreply, state}

  defp pad_screen(
         %{type: :button, pressed: true, button: button} = event,
         %{screen: :play} = state
       ) do
    case pad_action(state.pad_keys, button) do
      nil -> pad_input(event, state)
      action -> play_action(action, event, state)
    end
  end

  defp pad_screen(
         %{type: :axis, axis: axis} = event,
         %{screen: :play, look: %{projection: :first_person}} = state
       )
       when axis in [:right_x, :right_y],
       do: pad_input(event, state)

  defp pad_screen(%{type: :axis, axis: axis, value: value} = event, %{screen: :play} = state)
       when axis in [:right_x, :right_y] do
    cond do
      Pad.aim_stick(state.pad) == :right or Pad.binds_axis?(state.pad, axis) ->
        pad_input(event, state)

      abs(value) >= 0.5 ->
        nudge_aim(state, axis, value)

      true ->
        pad_input(event, state)
    end
  end

  defp pad_screen(event, %{screen: :play} = state), do: pad_input(event, state)

  defp pad_screen(%{type: :button, pressed: true, button: button}, %{screen: :lobby} = state) do
    case button do
      :dpad_down -> {:ok, select(state, 1)}
      :dpad_up -> {:ok, select(state, -1)}
      :a -> {:ok, join_selected(state, team_props(state))}
      :start -> {:ok, join_selected(state, team_props(state))}
      _other -> {:noreply, state}
    end
  end

  defp pad_screen(%{type: :button, pressed: true, button: button}, %{screen: :title} = state)
       when button in [:a, :start],
       do: {:ok, play(state)}

  defp pad_screen(%{type: :button, pressed: true, button: button}, %{screen: :summary} = state)
       when button in [:a, :start],
       do: after_summary(state)

  defp pad_screen(_event, state), do: {:noreply, state}

  defp pad_input(_event, %{input: input} = state) when input != nil do
    input = Input.merge(input, Pad.held(state.pad), Pad.strength(state.pad))
    {:ok, %{state | input: input} |> stick_aimed(Pad.aim(state.pad)) |> push_input()}
  end

  defp pad_input(_event, state), do: {:noreply, state}

  defp pad_action(pad_keys, button) do
    Enum.find_value(pad_keys, fn {action, bound} -> if button in List.wrap(bound), do: action end)
  end

  defp stick_aimed(%{stick_aim?: true} = state, nil),
    do: %{state | pad_aim: nil, stick_aim?: false}

  defp stick_aimed(state, nil), do: state
  defp stick_aimed(%{view: nil} = state, _direction), do: state

  defp stick_aimed(state, {dx, dy}) do
    {tx, ty} = turned({dx, dy}, rem(4 - facing_of(state.look), 4))
    {fx, fy} = focus(state, scene(state))

    %{
      state
      | pad_aim: {fx + tx * @stick_aim_distance, fy + ty * @stick_aim_distance},
        stick_aim?: true,
        input: %{state.input | aim: nil}
    }
  end

  defp nudge_aim(%{view: nil} = state, _axis, _value), do: {:noreply, state}

  defp nudge_aim(state, axis, value) do
    scene = scene(state)
    step = if value > 0, do: 1, else: -1
    screen = if axis == :right_x, do: {step, 0}, else: {0, step}
    {dx, dy} = turned(screen, rem(4 - facing_of(state.look), 4))
    {ax, ay} = state.pad_aim || focus(state, scene)
    {:ok, %{state | pad_aim: {ax + dx, ay + dy}} |> push_input()}
  end

  defp facing_of(%{projection: :iso, facing: facing} = look) when look.facings == 4, do: facing
  defp facing_of(_look), do: 0

  defp toggle_mouse_look(%{look: look} = state),
    do: %{state | look: %{look | mouse_look?: not look.mouse_look?}}

  defp toggle_display(%{settings: settings} = state) do
    display =
      case settings.display do
        :auto -> Map.get(state, :last_glyphs) || Cells.default_set(Context.terminal_env())
        _cells -> :auto
      end

    state
    |> Map.put(:last_glyphs, settings.display)
    |> put_settings(%{settings | display: display})
    |> repaced()
  end

  defp next_glyphs(%{settings: settings} = state) do
    sets = Cells.sets() -- [:braille]

    display =
      case Enum.find_index(sets, &(&1 == settings.display)) do
        nil -> hd(sets)
        index -> Enum.at(sets, rem(index + 1, length(sets)))
      end

    state |> put_settings(%{settings | display: display}) |> repaced()
  end

  defp repaced(state) do
    apply_frame_rate(state)
    state
  end

  defp trace_event({:mouse, %{type: type, x: x, y: y}}),
    do: Trace.write(:mouse, type: type, x: x, y: y)

  defp trace_event({:key, key}), do: Trace.write(:key, key: key)
  defp trace_event({:key, key, _modifiers}), do: Trace.write(:key, key: key)
  defp trace_event({:key_down, key, _modifiers}), do: Trace.write(:key, key: key)
  defp trace_event(_event), do: :ok

  @directions %{left: {-1, 0}, right: {1, 0}, up: {0, -1}, down: {0, 1}}

  @doc """
  The player's input as the world should see it for the projection in use. A view that
  does not turn sends it as held: top-down always, and the oblique view at its default
  single facing. A view at one of four facings turns the four direction actions with it,
  and of the directions a stick holds keeps only the one pushed hardest.

  On a finer `facings` a quarter turn is no longer the step, so the directions go as held
  and the input carries `:heading` instead, as it does in first person and mode 7: a
  heading in radians with `0` along `+x`, along which the game walks `:up`, against which
  it walks `:down`, and across which it walks `:left` and `:right`. A game offering more
  than four facings must read `:heading`; pressing up then moves the same way across the
  picture however far the view has turned. Turning the view is the client's `turn_left`
  and `turn_right`, not a game action.
  """
  @spec steered(Input.state(), map()) :: map()
  def steered(read, %{projection: :top}), do: read

  def steered(read, %{projection: projection, heading: heading})
      when projection in [:first_person, :mode7],
      do: Map.put(read, :heading, heading)

  def steered(read, %{projection: projection} = look) when projection in [:iso, :oblique] do
    case facings_of(look) do
      1 -> read
      4 -> quartered(read, look.facing)
      facings -> Map.put(read, :heading, Iso.up(facing: look.facing, facings: facings))
    end
  end

  def steered(read, _look), do: read

  defp quartered(read, facing) do
    held =
      MapSet.new(snapped(read), fn action ->
        case Map.fetch(@directions, action) do
          {:ok, screen} -> screen |> turned(rem(4 - facing, 4)) |> direction_action()
          :error -> action
        end
      end)

    %{read | held: held}
  end

  defp snapped(%{held: held, strength: strength}) do
    pushed = Map.take(strength, Map.keys(@directions))

    case Enum.max_by(pushed, &elem(&1, 1), fn -> nil end) do
      nil ->
        held

      {hardest, _} ->
        held |> MapSet.difference(MapSet.new(Map.keys(pushed))) |> MapSet.put(hardest)
    end
  end

  defp snapped(%{held: held}), do: held

  defp turned({dx, dy}, 0), do: {dx, dy}
  defp turned({dx, dy}, 1), do: {dy, -dx}
  defp turned({dx, dy}, 2), do: {-dx, -dy}
  defp turned({dx, dy}, 3), do: {-dy, dx}

  defp direction_action({dx, dy}) do
    {action, _} = Enum.find(@directions, fn {_, {sx, sy}} -> {sx, sy} == {dx, dy} end)
    action
  end

  defp push_input(%{input: nil} = state), do: state

  defp push_input(state) do
    read = Input.state(state.input)

    sent =
      %{
        steered(read, look(state))
        | aim:
            state.pad_aim ||
              if(state.settings.pointer and read.aim != nil, do: aim_in_world(state, read.aim))
      }
      |> with_options(options_of(state))
      |> with_request(Map.get(state, :request))

    if sent != state.last_input do
      Trace.write(:input, held: Enum.join(sent.held, ","), aim: aim_text(sent.aim))
      Player.input(state.joined.world, state.player_id, sent)
      %{state | last_input: sent}
    else
      state
    end
  end

  defp with_options(sent, options) when map_size(options) == 0, do: sent
  defp with_options(sent, options), do: Map.put(sent, :options, options)

  defp with_request(sent, nil), do: sent
  defp with_request(sent, request), do: Map.put(sent, :request, request)

  defp after_summary(state) do
    case next_world(state) do
      nil -> leave(state)
      world -> {:ok, state |> Map.put(:screen, :lobby) |> join(world, team_props(state))}
    end
  end

  @doc false
  @spec next_world(map()) :: map() | nil
  def next_world(%{summary: %{next: :same_world}, summary_world: world}), do: world

  def next_world(%{summary: %{next: :next_world}, summary_world: world} = state) do
    worlds = worlds(state)

    case Enum.find_index(worlds, &(&1.id == world.id)) do
      nil -> List.first(worlds)
      index -> Enum.at(worlds, rem(index + 1, length(worlds)))
    end
  end

  def next_world(_state), do: nil

  defp outcome(%{game: game}, view) do
    Game.outcome(game, view)
  end

  defp optional(game, callback, default), do: optional(game, callback, [], default)

  defp optional(game, callback, args, default) do
    if Code.ensure_loaded?(game) and function_exported?(game, callback, length(args)),
      do: apply(game, callback, args),
      else: default
  end

  defp aim_text(nil), do: "-"
  defp aim_text({x, y}), do: "#{Float.round(x / 1, 2)},#{Float.round(y / 1, 2)}"

  defp aim_in_world(%{geometry: nil}, _cell), do: nil

  defp aim_in_world(%{geometry: geometry, view: view, game: game, zoom: zoom} = state, {x, y})
       when view != nil do
    scene = scene(state)
    rect = geometry.rect
    look = look(state)

    surface = %Surface{
      atlas: game.atlas(),
      focus: focus(state, scene),
      zoom: zoom,
      mode: Settings.surface_mode(state.settings),
      projection: look.projection,
      facing: look.facing,
      facings: Map.get(look, :facings) || 4,
      tilt: look.tilt,
      heading: Map.get(scene, :heading) || look.heading,
      pitch: look.pitch,
      density: Map.get(look, :density),
      eye: eye_height(game, scene),
      frame: Map.get(scene, :frame)
    }

    cell = {x - rect.x, y - rect.y}
    world = Surface.world_at(surface, rect, cell)
    traced(surface, rect, cell, world, scene, state)
    world
  end

  defp aim_in_world(_state, _cell), do: nil

  defp traced(_surface, _rect, _cell, nil, _scene, _state), do: :ok

  defp traced(surface, rect, cell, world, scene, state) do
    if Process.put(@traced, {cell, world, scene.focus}) != {cell, world, scene.focus},
      do: trace_click(surface, rect, cell, world, scene, state)
  end

  defp trace_click(surface, rect, {cx, cy}, {wx, wy}, scene, state) do
    {hx, hy} = scene.focus
    {fx, fy} = surface.focus
    {px, py} = Map.get(state, :pan) || {0.0, 0.0}
    hero = Surface.cell_at(surface, rect, scene.focus)

    Trace.write(:click,
      cell_x: cx,
      cell_y: cy,
      pane_x: rect.x,
      pane_y: rect.y,
      pane_w: rect.width,
      pane_h: rect.height,
      projection: surface.projection,
      facing: surface.facing,
      facings: surface.facings,
      tilt: surface.tilt,
      zoom: surface.zoom,
      world_x: wx,
      world_y: wy,
      camera_x: fx,
      camera_y: fy,
      pan_x: px,
      pan_y: py,
      hero_x: hx,
      hero_y: hy,
      hero_cell_x: hero && elem(hero, 0),
      hero_cell_y: hero && elem(hero, 1)
    )
  end

  defp start_audio(game, props, settings) do
    sink =
      if muted?(props),
        do: TuningFork.Sink.Silent,
        else: Map.get(props, :sink) || optional(game, :sink, [props], default_sink(props))

    {:ok, audio} =
      Audio.start_link(
        [
          name: nil,
          sink: sink,
          sounds: game.sounds(),
          sfx: settings.sfx,
          music: settings.music,
          music_dir: Game.music_dir(game),
          parallel: true
        ] ++ Game.audio_options(game)
      )

    for {name, spec} <- game.music(), do: Music.piece(audio, name, spec)
    audio
  end

  defp muted?(props) do
    case Map.get(props, :mute) do
      nil ->
        Application.get_env(
          :cauldron_2d_drafter,
          :mute,
          System.get_env("CAULDRON_MUTE") in ["1", "true"]
        )

      mute ->
        mute == true
    end
  end

  defp default_sink(%{served_by: _server, pulse_port: port}) when is_integer(port),
    do: {TuningFork.Sink.Tcp, port: port}

  defp default_sink(%{served_by: _server}), do: TuningFork.Sink.Silent

  defp default_sink(_props),
    do:
      if(Code.ensure_loaded?(TuningFork.Sink.Speaker),
        do: TuningFork.Sink.Speaker,
        else: TuningFork.Sink.Silent
      )

  defp cue_music(%{screen: :play, view: nil} = state), do: state

  defp cue_music(state) do
    cue = state.game.cue(state.view, state.screen)

    cond do
      cue == state.cue ->
        state

      cue == nil ->
        Music.stop(state.audio)
        %{state | cue: nil}

      true ->
        Music.cue(state.audio, cue)
        %{state | cue: cue}
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end
