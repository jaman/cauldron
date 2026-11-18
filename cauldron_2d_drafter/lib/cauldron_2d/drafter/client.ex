defmodule Cauldron2D.Drafter.Client do
  @moduledoc """
  The drafter application that puts a `Cauldron.World` in front of one player.

  Runs a game's client module — one implementing `Cauldron.Client.Game` —
  through its screens: a title, a lobby listing the worlds, settings, the world itself,
  and a summary when the game's `outcome/1` says play is over for this player. It holds the player's input, their audio, and their connection to the world.

  A world whose `world` is `{module, opts}` is this player's alone: the client starts
  a `Cauldron.World` for it when the player joins and stops it when they leave, and
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
      moves it can make; leaving a world then stops the client. Nothing is drawn until
      it runs

  A screen the game draws itself (its `fronts/1`) is open from the client's first
  frame, so the client's own version of that screen is never shown in its place.

  A game with `lobby?/0` false and no `start/0` is read as `{:play, :first, title: true}`.

      Drafter.Server.start_ssh(Cauldron2D.Drafter.Client,
        auth: {:accounts, accounts},
        tunnel: true,
        mount_props: %{game: MyGame.Client, accounts: accounts}
      )

  ## Mount props

    * `:game` — the client module. Required
    * `:username` — the player's name, set by the ssh transport. Default `"player"`
    * `:sink` — the `Cauldron.Audio.Sink` this player's audio plays through. Default:
      the game's `sink/1` given all the mount props, else for a session served over ssh
      (`:served_by`) raw PCM to `127.0.0.1:<:pulse_port>`, the account's tunnel, or
      silence without one; for any other session `Cauldron.Audio.Sink.speaker/0`
    * `:settings` — the map `Cauldron2D.Drafter.Client.Settings.to_props/1` produced,
      from the account props; a settings file for the player overrides it. Default: the
      game's first preset
    * `:accounts` — the `Drafter.Accounts` server settings are saved to. Default: none
    * `:kind` — the kind of client this is, the key its settings are kept under (see
      `Cauldron2D.Drafter.Client.Settings`). Default `:terminal`
    * `:start` — the flow, as the Flow section describes it, over the game's `start/0`.
      Default: the game's, else `:lobby`
    * `:picture` — how a game's picture reaches a terminal that keeps images, as
      `Cauldron2D.Drafter.Client.Picture` reads it
    * `:mute` — `true` plays no sound, whatever sink the game or the session would have
      had; `false` plays it
    * `:trace` — a file to write `Cauldron.Trace` events to

  `:picture`, `:mute` and `:trace` follow `Cauldron.Launch`'s order when the prop is
  not given: the game's saved launch values (`Cauldron2D.Drafter.Launcher.load/1`'s
  `:picture` and `:mute`), then `CAULDRON_PICTURE`, `CAULDRON_MUTE` (`1`/`true` or
  `0`/`false`) and `CAULDRON_TRACE`, then `config :cauldron_2d_drafter, picture: ...` and
  `mute: ...`, then the defaults: the game's look's picture or
  `Cauldron2D.Drafter.Client.Picture.default/0`, sound on, no trace.

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

  With `CAULDRON_TRACE` set (see `Cauldron.Trace`), the client writes every key and
  mouse event it steers with (`key`, `mouse`), every input it sends the world (`input`,
  with the actions held and the aim in tiles) and every frame the world sends back
  (`frame`, with its tick), so `mix cauldron.report --from mouse --to frame` measures
  the way round.

  ## Keys

  The client's own keys are `default_keys/0`, each replaceable or dropped by the game's
  `client_keys/0`; what follows describes the defaults. In the world `t` opens a line
  to talk to everyone in it — `Enter` sends, `Esc` cancels, and no key steers while it
  is open. `Esc` goes back: settings to where it was opened from, world to lobby, lobby
  to title, title out of the program. `q` (the `leave_world` key) quits the world for the lobby too, and goes
  to the title from the lobby. `^Q` goes back as `Esc` does, a step at a time out of the program; `^C` quits from anywhere. `?` shows the world's key hints and hides
  them again; held, it shows them until released. The `fps` key, bound only when the
  game binds it, shows under the world how many frames a second the world sends and,
  while the graphics card draws the world, how many it drew, and hides it again; a
  game whose look has `fps?: true` starts with it shown. The fps row, and a hud row the
  game tags `:status`, are drawn as a light bar with dark text. `=` (or `+`) and `-` zoom the world in and out through the levels
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
  own menu (its `open_menu/1`; see `Cauldron.Client.Game`), `mouse_look` lets
  the pointer turn and pitch the eye in first person; a drag turns and pitches it there
  whether or not `mouse_look` is on, and a click still reaches the game. What the view is, and how it is
  drawn, shows under the world when it is not the top-down default. A game's `look/0`
  sets the view it starts in.

  The player's keys, mouse and controllers, and its seats', are read through
  `Cauldron.Client.Party`, as every front end reads them; keys are read without
  their releases until the terminal says it reports them.

  Each connected controller plays one of the client's players — the player itself, then
  its seats — as `Cauldron.Client.Controllers` assigns them from the settings'
  `pads`, and the settings' `controllers` list them for the game's menus; a controller
  that plays no one is ignored during play, and while the game's menu is open any
  controller works it. A controller moved to another player first lets go of what it
  held for the one before.

  A controller plays the game's actions by its padmap (`Cauldron.Client.Game.padmap/3`:
  the game's `padmap/1`, or the d-pad and left stick on its directions and a button for
  each other action); the right stick, unless the padmap binds its axes to actions,
  nudges the aim a tile at a time top-down and isometric and looks around in first
  person, the triggers tilt the isometric diamond or pitch the eye — right up, left
  down, as far as they are pulled. `Start` opens the game's menu when it has one
  (`open_menu/1`); the projection is cycled by `Start` in a game without a menu and by
  `Back` in one with, and only when the look has more than one projection; the bumpers
  turn when one of the projections turns. The default padmap passes over these
  buttons. `client_pad/0` rebinds the client's own actions to buttons, and in the lobby
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

  alias Cauldron.{Audio, Chat, Input, Player, Sessions, Trace, World}
  alias Cauldron.Audio.Music
  alias Cauldron.Client.{Controls, Fronts, Game, Keys, Menus, Party, Start, View}
  alias Cauldron2D.{Atlas, Camera, Draw}
  alias Cauldron2D.Client.Look
  alias Cauldron2D.Drafter.{Launcher, Surface}

  alias Cauldron2D.Drafter.Client.{Gpu, Picture, Screens, Settings, Stage}

  alias Cauldron.Input.Pad
  alias Cauldron.World.Presence
  alias Drafter.Session.Context
  alias FrenchCurve.Backend.Cells

  @hold_ms 250
  @namesakes 9
  @audio_stop_ms 2_000
  @stick_turn 10 * :math.pi() / 18
  @stick_pitch 0.8
  @trigger_tilt 0.8
  @pan_step 4
  @traced {__MODULE__, :traced}

  @doc "The client's keys by action — a key, or a list of keys — before the game's `client_keys/0` is applied."
  @spec default_keys() :: %{atom() => atom() | [atom()]}
  def default_keys, do: Keys.defaults()

  @impl true
  def mount(props) do
    game = Map.fetch!(props, :game)
    username = Map.get(props, :username, "player")
    kind = Map.get(props, :kind, :terminal)

    settings =
      Settings.load(game, username, %{Settings.prop_key(kind) => Map.get(props, :settings, %{})},
        kind: kind
      )

    Sessions.track(username, kind)
    Atlas.subscribe(game.atlas())
    look = Look.of(game)
    launch = Launcher.load(game)
    picture = Picture.options(props, look, launch)

    %{
      game: game,
      props: props,
      kind: kind,
      username: username,
      accounts: Map.get(props, :accounts),
      pages: optional(game, :pages, [props], []),
      fronts: Fronts.of(game, props),
      front: nil,
      keys: Keys.of(game),
      pad_keys: Keys.pad(game, look),
      chat?: optional(game, :chat?, [], true),
      flow: Start.flow(game, props),
      local_world: nil,
      settings: settings,
      screen: Start.first_screen(Start.flow(game, props)),
      return: :title,
      help?: false,
      help_pressed_at: nil,
      fps?: Map.get(look, :fps?, false),
      fps: %{frames: 0, since: now(), shown: nil},
      audio: start_audio(game, props, settings, launch),
      party: Party.new(game, settings, props, releases?: Context.key_release?()),
      player_id: nil,
      joined: nil,
      view: nil,
      geometry: nil,
      zoom: Look.zoom(game),
      look: look,
      picture: picture,
      gpu: Gpu.new(picture),
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
      world_paused?: false,
      menu_frame: 0,
      requests: 0,
      request: nil,
      asked: nil,
      return_props: nil,
      return_extra: %{},
      world_ref: nil,
      summary_world: nil,
      rebinding: nil,
      cue: nil,
      last_input: nil,
      guide: %{offset: 0, rows: 16, return: :title}
    }
    |> Gpu.configure()
    |> first_front()
    |> cue_music()
  end

  @impl true
  def refresh_rate, do: "30fps"

  @impl true
  def handles_ctrl_q?, do: true

  @impl true
  def on_ready(state) do
    Trace.start(Map.get(state.props, :trace))
    chat_join(state, :lobby)
    Presence.subscribe()
    apply_frame_rate(state)
    blur_pages(state)
    if state.screen == :lobby, do: Drafter.blur(:chat_input)
    state = %{state | lobby: %{state.lobby | messages: chat_history(state, :lobby)}}
    state.flow |> begin(state) |> ready_front()
  end

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
    Gpu.stop(state)
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
  def render(%{front: %{screen: screen}, screen: screen} = state), do: Screens.front(state)
  def render(%{screen: :starting} = state), do: Screens.starting(state)
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
      text -> Chat.say({:world, to_string(state.joined.id)}, said_as(state), text)
    end

    Drafter.blur(:talk_input)
    {:ok, %{state | talk_text: "", talking?: false}}
  end

  def handle_event({:page, key}, _data, %{screen: :title} = state), do: {:ok, to_page(state, key)}

  def handle_event({:title, :play}, _data, %{screen: :title} = state), do: {:ok, play(state)}

  def handle_event({:title, :settings}, _data, %{screen: :title} = state),
    do: {:ok, to_settings(state)}

  def handle_event({:title, :guide}, _data, %{screen: :title} = state), do: {:ok, to_guide(state)}
  def handle_event({:title, :quit}, _data, %{screen: :title}), do: {:stop, :normal}

  def handle_event(:chat_submit, _text, state) do
    case String.trim(state.chat_text) do
      "" -> Drafter.blur(:chat_input)
      text -> Chat.say(:lobby, said_as(state), text)
    end

    {:ok, %{state | chat_text: ""}}
  end

  def handle_event(_name, _data, state), do: {:noreply, state}

  @impl true
  def handle_event({:key, :q, [:ctrl]}, state) do
    case List.wrap(state.keys.back) do
      [key | _] -> handle_event({:key, key}, state)
      [] -> {:stop, :normal}
    end
  end

  def handle_event({:key, :c, [:ctrl]}, _state), do: {:stop, :normal}

  def handle_event({:key_release_support, _supported?} = event, state),
    do: {:ok, %{state | party: Party.event(state.party, event, now())}}

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

  defp screen_key(event, %{front: %{screen: screen}, screen: screen} = state),
    do: front_event(event, state)

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
  def on_timer(:front_frame, %{front: nil} = state), do: state

  def on_timer(:front_frame, %{screen: screen} = state) do
    cond do
      Fronts.showing?(state) ->
        Drafter.set_timeout(Fronts.frame_ms(), :front_frame)
        state |> Fronts.tick(now()) |> cue_music()

      screen in [:settings, :guide] ->
        Drafter.set_timeout(Fronts.frame_ms(), :front_frame)
        state

      true ->
        %{state | front: nil}
    end
  end

  def on_timer(:menu_frame, %{menu: nil} = state), do: state

  def on_timer(:menu_frame, state) do
    Drafter.set_timeout(Menus.frame_ms(), :menu_frame)
    window_tick(%{state | menu_frame: state.menu_frame + 1})
  end

  def on_timer(_timer, state), do: state

  defp window_tick(%{view: nil} = state), do: state

  defp window_tick(state), do: Gpu.tick(state, game_scene(state))

  @impl true
  def on_message({:cauldron_frame, frame}, %{joined: joined} = state) when joined != nil do
    Trace.write(:frame, tick: frame.tick)

    state =
      %{
        state
        | view: frame.view,
          party: Party.expire(state.party, now()),
          fps: counted(state.fps, now())
      }
      |> followed()
      |> looked(now())
      |> window_tick()

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
        |> front_opened()
        |> cue_music()
    end
  end

  def on_message({:chat, {:world, _id}, message}, state) do
    %{state | talk: Enum.take(state.talk ++ [message], -20)}
  end

  def on_message({:cauldron_atlas, _name, :changed}, state), do: state

  def on_message({Stage, _stage, _message} = message, state) do
    updated = Gpu.message(message, state)
    if updated.gpu.mode != state.gpu.mode, do: apply_frame_rate(updated)
    updated
  end

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
    state |> leave_world() |> Map.put(:screen, :title) |> front_opened() |> cue_music()
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

  defp leave_settings(%{return: :play, joined: joined} = state) when joined != nil,
    do: %{state | screen: :play}

  defp leave_settings(%{return: :play} = state), do: %{state | screen: :lobby}
  defp leave_settings(%{return: screen} = state), do: %{state | screen: screen}

  defp release_keys(state), do: pushed(%{state | party: Party.let_go(state.party)})

  defp rebound(state),
    do: pushed(listed(%{state | party: Party.settings(state.party, state.settings)}))

  defp listed(state),
    do: %{state | settings: %{state.settings | controllers: Party.listed(state.party)}}

  defp push_seats(%{joined: nil} = state), do: state

  defp push_seats(state),
    do: %{state | party: Party.send_seats(state.party, state.joined.world, look(state))}

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
    do: lobby_action(Keys.action(state.keys, key, @lobby_actions), state)

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

    case local_world(entry) do
      {:ok, entry, local} -> entered(state, entry, local, props, extra)
      {:error, reason} -> refused(state, entry, reason)
    end
  end

  defp entered(state, entry, local, props, extra) do
    case join_as(entry.world, state.username, props, frame_rate(state)) do
      {:ok, player_id} ->
        chat_join(state, {:world, to_string(entry.id)})

        state = %{
          state
          | joined: entry,
            player_id: player_id,
            local_world: local,
            world_paused?: false,
            world_ref: watch(entry.world),
            screen: :play,
            view: nil,
            last_input: nil,
            talk: chat_history(state, {:world, to_string(entry.id)}),
            talking?: false,
            zoom: Look.zoom(state.game),
            pan: {0.0, 0.0},
            subject: nil,
            watching?: Map.get(extra, :spectate, false) == true,
            drag: nil,
            party:
              state.party
              |> Party.let_go()
              |> Party.seat(entry.world, player_id, props)
        }

        state |> listed() |> cue_music()

      {:error, reason} ->
        if local, do: GenServer.stop(local)
        refused(state, entry, reason)
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
    case World.start([game: module] ++ Keyword.drop(opts, [:name])) do
      {:ok, pid} ->
        Process.link(pid)
        {:ok, %{entry | world: pid}, pid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp local_world(entry), do: {:ok, entry, nil}

  defp refused(state, entry, reason),
    do:
      noted(state, %{
        from: entry.name,
        text: "could not join: " <> Game.refusal_text(state.game, reason)
      })

  defp leave_world(%{joined: nil} = state), do: state

  defp leave_world(state), do: forget_world(%{state | party: unseated(state)})

  defp unseated(%{joined: %{world: world}, player_id: player_id, party: party}) do
    without_seats = Party.unseat(party, world)
    Player.leave(world, player_id)
    without_seats
  catch
    :exit, _gone -> party
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

  defp chat_join(%{chat?: true}, room), do: Chat.join(room)
  defp chat_join(_state, _room), do: :ok

  defp chat_history(%{chat?: true}, room), do: Chat.history(room)
  defp chat_history(_state, _room), do: []

  defp chat_leave(%{chat?: true}, room), do: Chat.leave(room)
  defp chat_leave(_state, _room), do: :ok

  defp forget_world(state) do
    chat_leave(state, {:world, to_string(state.joined.id)})

    if state.local_world && Process.alive?(state.local_world),
      do: GenServer.stop(state.local_world)

    if state.world_ref, do: Process.demonitor(state.world_ref, [:flush])

    %{
      state
      | joined: nil,
        world_ref: nil,
        local_world: nil,
        world_paused?: false,
        view: nil,
        party: Party.drop_seats(state.party),
        talking?: false,
        zoom: Look.zoom(state.game),
        pan: {0.0, 0.0},
        subject: nil,
        watching?: false,
        drag: nil
    }
    |> listed()
  end

  defp toggle_pause(%{local_world: world, world_paused?: true} = state) do
    World.resume(world)
    %{state | world_paused?: World.paused?(world)}
  end

  defp toggle_pause(%{local_world: world} = state) do
    World.pause(world)
    %{state | world_paused?: World.paused?(world)}
  end

  @doc "Whether the player's own world is paused."
  @spec paused?(map()) :: boolean()
  def paused?(state), do: Map.get(state, :world_paused?, false)

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
    do: {:ok, state |> save_settings() |> rebound() |> leave_settings() |> cue_music()}

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

  defp adjust(%{selected: :drawing} = state, delta),
    do: put_settings(state, Settings.step_drawing(state.settings, delta))

  defp adjust(%{selected: :fps} = state, delta),
    do: put_settings(state, Settings.step_fps(state.settings, state.game, delta))

  defp apply_frame_rate(state) do
    rate = frame_rate(state)
    Drafter.set_refresh_rate(Integer.to_string(rate) <> "fps")
    Gpu.rate(state, rate)
    paced_frames(state, rate)
  end

  @doc "The frames a second the client draws at, from its settings and its terminal."
  @spec frame_rate(map()) :: pos_integer()
  def frame_rate(state) do
    protocol = Surface.protocol(%Surface{mode: Settings.surface_mode(state.settings)})
    placements? = FrenchCurve.Capability.placements?(Context.terminal_env())
    link = if Map.has_key?(state.props, :served_by), do: :ssh, else: :local
    Settings.frame_rate(state.settings, protocol, placements?, link, Gpu.shared_frames?(state))
  end

  defp paced_frames(%{joined: nil}, _rate), do: :ok

  defp paced_frames(state, rate) do
    Player.frames(state.joined.world, state.player_id, rate)
  catch
    :exit, _gone -> :ok
  end

  defp put_settings(state, settings) do
    Audio.levels(state.audio, settings.sfx, settings.music)
    updated = Gpu.configure(%{state | settings: settings})
    if frame_rate(updated) != frame_rate(state), do: apply_frame_rate(updated)
    updated
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

  defp open_menu(state), do: opened_menu(state, Menus.open(state.game, state.settings))

  defp open_menu(state, arg), do: opened_menu(state, Menus.open(state.game, state.settings, arg))

  defp opened_menu(state, menu) do
    paused? = pause_for_menu(state.local_world)
    Drafter.set_timeout(Menus.frame_ms(), :menu_frame)

    %{
      release_keys(state)
      | menu: menu,
        menu_paused?: paused?,
        world_paused?: paused_in(state.local_world)
    }
  end

  defp paused_in(nil), do: false
  defp paused_in(world), do: Process.alive?(world) and World.paused?(world)

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
    %{state | menu_paused?: false, world_paused?: false}
  end

  defp resume_after_menu(state), do: state

  defp menu_event(event, state) do
    if Menus.input?(event) do
      result = Menus.event(state.game, state.menu, event, state.settings)

      state =
        state
        |> take_menu_settings(Map.fetch!(result, :settings))
        |> Map.put(:menu, Map.get(result, :menu))
        |> resume_after_menu()
        |> menu_request(Map.get(result, :request))

      Audio.play(state.audio, Map.get(result, :sounds, []))
      if Map.get(result, :leave, false), do: leave(state), else: {:ok, window_tick(state)}
    else
      {:noreply, state}
    end
  end

  defp front_opened(state) do
    {opened, start?} = Fronts.open(state, front_context(state), now())
    if start?, do: Drafter.set_timeout(Fronts.frame_ms(), :front_frame)
    opened
  end

  defp front_context(state) do
    %{
      settings: state.settings,
      username: state.username,
      worlds: worlds(state),
      outcome: state.summary,
      view: state.view
    }
  end

  defp first_front(state) do
    {opened, _start?} = Fronts.open(state, front_context(state), now())
    opened
  end

  defp ready_front(state) do
    if Fronts.showing?(state) do
      Drafter.set_timeout(Fronts.frame_ms(), :front_frame)
      state
    else
      front_opened(state)
    end
  end

  defp front_event(event, state) do
    if Menus.input?(event) do
      {state, reply} = Fronts.event(state, event, state.settings)
      state = take_menu_settings(state, reply.settings)
      Audio.play(state.audio, Map.get(reply, :sounds, []))
      go(Map.get(reply, :go), state)
    else
      {:noreply, state}
    end
  end

  defp go(nil, state), do: {:ok, state}
  defp go(:play, state), do: {:ok, play(state)}
  defp go({:play, id}, state), do: {:ok, enter(state, id)}
  defp go(:again, state), do: after_summary(state)
  defp go(:lobby, state), do: {:ok, lobby(state)}
  defp go(:title, state), do: {:ok, title(state)}
  defp go(:settings, state), do: {:ok, to_settings(state)}
  defp go(:guide, state), do: {:ok, guide(state)}
  defp go(:quit, _state), do: {:stop, :normal}
  defp go(:back, %{screen: :title}), do: {:stop, :normal}
  defp go(:back, state), do: leave(state)

  defp take_menu_settings(%{settings: settings} = state, settings), do: state

  defp take_menu_settings(state, settings) do
    state
    |> put_settings(settings)
    |> save_settings()
    |> rebound()
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

  defp answer(state, {number, {:options, changes}}) when is_map(changes) do
    settings = state.settings
    options = Map.merge(settings.options, changes)
    take_menu_settings(%{state | asked: number}, %{settings | options: options})
  end

  defp answer(state, {number, {:clipboard, text}}) when is_binary(text) do
    Drafter.Clipboard.copy(text)
    %{state | asked: number}
  end

  defp answer(state, {number, {:enter, props}}) do
    returning = state.return_props || state.props
    state = leave_world(%{state | asked: number})

    entering = %{
      state
      | props: Map.merge(state.props, props),
        return_props: returning,
        return_extra: %{}
    }

    case enter(entering, :first) do
      %{joined: nil} = refused ->
        enter(%{refused | props: returning, return_props: nil}, :first, %{refused: true})

      entered ->
        entered
    end
  end

  defp answer(%{return_props: props} = state, {number, {:return, extra}})
       when props != nil and is_map(extra) do
    state = leave_world(%{state | asked: number})
    enter(%{state | props: props, return_props: nil, return_extra: %{}}, :first, extra)
  end

  defp answer(state, {number, {:on_return, extra}}) when is_map(extra),
    do: %{state | asked: number, return_extra: extra}

  defp answer(state, {number, _ask}), do: %{state | asked: number}

  defp returned(%{return_props: props, return_extra: extra} = state) do
    state = leave_world(state)
    enter(%{state | props: props, return_props: nil, return_extra: %{}}, :first, extra)
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
    :leave_world,
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
        Keys.action(state.keys, key, @play_actions ++ Keys.look_actions(state.keys)),
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
    if Look.turns_with_pointer?(look),
      do: play_input(event, %{state | pointer: {x, y}}),
      else: play_input(event, state)
  end

  defp play_event(
         {:mouse, %{type: :drag, button: :left, x: x, y: y}} = event,
         %{look: look} = state
       ) do
    if Look.turns_with_pointer?(look),
      do: turn_eye(event, state, {x, y}),
      else: play_input(event, state)
  end

  defp play_event({:mouse, %{type: :drag, x: x, y: y}} = event, state),
    do: play_input(event, %{state | pointer: {x, y}})

  defp play_event({:mouse, %{type: :move, x: x, y: y}} = event, %{look: look} = state) do
    if Look.turns_with_pointer?(look) and look.mouse_look?,
      do: turn_eye(event, state, {x, y}),
      else: play_input(event, unaimed(%{state | pointer: {x, y}}))
  end

  defp play_event(event, state), do: play_input(event, state)

  defp unaimed(state), do: %{state | party: Party.controls(state.party, &Controls.aim(&1, nil))}

  defp game_wheel?(%{watching?: true}, _direction), do: false
  defp game_wheel?(%{joined: nil}, _direction), do: false
  defp game_wheel?(state, :up), do: wheel_bound?(state, :wheel_up)
  defp game_wheel?(state, :down), do: wheel_bound?(state, :wheel_down)

  defp wheel_bound?(state, notch), do: Input.binds?(state.party.controls.input, {:mouse, notch})

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

  defp turn_eye(event, %{pointer: {px, py}} = state, {x, y}),
    do:
      play_input(
        event,
        unaimed(%{
          state
          | look: Look.dragged(state.look, pane_fraction(state, {x - px, y - py})),
            pointer: {x, y}
        })
      )

  defp turn_eye(event, state, {x, y}),
    do: play_input(event, unaimed(%{state | pointer: {x, y}}))

  defp pane_fraction(%{geometry: %{rect: %{width: width, height: height}}}, {dx, dy}),
    do: {dx / max(width, 1), dy / max(height, 1)}

  defp pane_fraction(_state, _delta), do: {0.0, 0.0}

  defp pane_cell(%{geometry: nil}, _mouse), do: nil
  defp pane_cell(%{geometry: %{rect: rect}}, %{x: x, y: y}), do: {x - rect.x, y - rect.y}

  defp pan_by(%{pan: {px, py}} = state, {dx, dy}),
    do: %{followed(state) | pan: {px + dx, py + dy}}

  defp followed(%{pan: {px, py}, view: view} = state)
       when view != nil and px == 0 and py == 0,
       do: %{state | subject: Map.get(scene(state), :subject)}

  defp followed(%{view: view} = state) when view != nil, do: follow(state, scene(state))

  defp followed(state), do: state

  @doc """
  The scene the client draws for its view and look: the game's `scene/2` where it
  defines one, else `scene/1`, with its picture drawn by the graphics card where the
  client has one (`Cauldron2D.Drafter.Client.Gpu.scene/2`).
  """
  @spec scene(map()) :: Game.scene()
  def scene(state), do: Gpu.scene(state, game_scene(state))

  defp game_scene(%{game: game, view: view} = state) do
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

  defp play_action(leave, _event, state) when leave in [:back, :leave_world], do: leave(state)

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
  defp play_action(:projection, _event, state), do: {:ok, %{state | look: Look.cycle(state.look)}}

  defp play_action(:turn_left, _event, state),
    do: {:ok, %{state | look: Look.turn(state.look, -1)}}

  defp play_action(:turn_right, _event, state),
    do: {:ok, %{state | look: Look.turn(state.look, 1)}}

  defp play_action(:tilt_up, _event, state), do: {:ok, %{state | look: Look.tilt(state.look, 1)}}

  defp play_action(:tilt_down, _event, state),
    do: {:ok, %{state | look: Look.tilt(state.look, -1)}}

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
      View.given(
        look,
        Map.get(state, :menu),
        Map.get(state, :menu_frame, 0),
        options_of(state)
      )

  def look(_state), do: Look.defaults()

  defp looked(%{looked_at: since} = state, now) when is_integer(since) do
    seconds = (now - since) / 1000

    state
    |> stick_looked(seconds)
    |> trigger_tilted(seconds)
    |> Map.put(:looked_at, now)
  end

  defp looked(state, now), do: %{state | looked_at: now}

  defp stick_looked(%{look: %{projection: :first_person} = look} = state, seconds) do
    pad = state.party.controls.pad
    {x, y} = {Pad.axis(pad, :right_x), Pad.axis(pad, :right_y)}

    look = %{
      look
      | heading: look.heading + x * @stick_turn * seconds,
        pitch: (look.pitch - y * @stick_pitch * seconds) |> min(1.0) |> max(-1.0)
    }

    %{state | look: look}
  end

  defp stick_looked(state, _seconds), do: state

  defp trigger_tilted(state, seconds) do
    pad = state.party.controls.pad
    pull = Pad.axis(pad, :right_trigger) - Pad.axis(pad, :left_trigger)

    if pull == 0.0,
      do: state,
      else: tilted_by(state, pull * @trigger_tilt * seconds)
  end

  defp tilted_by(%{look: %{projection: :iso} = look} = state, amount),
    do: %{state | look: %{look | tilt: (look.tilt + amount) |> min(1.5) |> max(0.5)}}

  defp tilted_by(%{look: %{projection: :first_person} = look} = state, amount),
    do: %{state | look: %{look | pitch: (look.pitch + amount) |> min(1.0) |> max(-1.0)}}

  defp tilted_by(state, _amount), do: state

  defp talk(state) do
    Drafter.focus(:talk_input)

    {:ok,
     %{state | talking?: true, party: Party.controls(state.party, &Controls.let_go/1)}
     |> push_input()}
  end

  defp play_input(event, %{joined: joined} = state) when joined != nil do
    trace_event(event)
    {:ok, pushed(%{state | party: Party.event(state.party, event, now())})}
  end

  defp play_input(_event, state), do: {:noreply, state}

  defp pushed(state), do: state |> push_input() |> push_seats()

  defp pad_event(event, %{screen: :play, menu: nil} = state) do
    {party, routed} = Party.pad(state.party, event)
    played_pad(event, routed, listed(%{state | party: party}))
  end

  defp pad_event(%{type: :button, pressed: true} = event, state), do: pad_screen(event, state)
  defp pad_event(%{type: :axis}, state), do: {:noreply, state}

  defp pad_event(event, state) do
    {party, _routed} = Party.pad(state.party, event)
    {:ok, listed(%{state | party: party})}
  end

  defp played_pad(%{type: :button, pressed: true, button: button} = event, :own, state) do
    case pad_action(state.pad_keys, button) do
      nil -> {:ok, pushed(state)}
      action -> play_action(action, event, state)
    end
  end

  defp played_pad(event, :own, state), do: {:ok, pushed(nudged(state, event))}
  defp played_pad(_event, _routed, state), do: {:ok, pushed(state)}

  defp nudged(state, event) do
    nudge = &Controls.nudge(&1, event, state.look, fn -> view_focus(state) end)
    %{state | party: Party.controls(state.party, nudge)}
  end

  defp view_focus(%{view: nil}), do: nil
  defp view_focus(state), do: focus(state, scene(state))

  defp pad_screen(
         %{type: :button, pressed: true, button: button},
         %{screen: :play, menu: menu} = state
       )
       when menu != nil do
    case Menus.pad_key(button) do
      nil -> {:noreply, state}
      key -> menu_event({:key, key, [:pad]}, state)
    end
  end

  defp pad_screen(%{type: :button, pressed: true, button: button}, %{screen: :lobby} = state) do
    case button do
      :dpad_down -> {:ok, select(state, 1)}
      :dpad_up -> {:ok, select(state, -1)}
      :a -> {:ok, join_selected(state, team_props(state))}
      :start -> {:ok, join_selected(state, team_props(state))}
      _other -> {:noreply, state}
    end
  end

  defp pad_screen(%{type: :button, pressed: true, button: button}, state)
       when state.front != nil and state.front.screen == state.screen do
    case Menus.pad_key(button) do
      nil -> {:noreply, state}
      key -> front_event({:key, key, [:pad]}, state)
    end
  end

  defp pad_screen(%{type: :button, pressed: true, button: button}, %{screen: :title} = state)
       when button in [:a, :start],
       do: {:ok, play(state)}

  defp pad_screen(%{type: :button, pressed: true, button: button}, %{screen: :summary} = state)
       when button in [:a, :start],
       do: after_summary(state)

  defp pad_screen(_event, state), do: {:noreply, state}

  defp pad_action(pad_keys, button) do
    Enum.find_value(pad_keys, fn {action, bound} -> if button in List.wrap(bound), do: action end)
  end

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
  end

  defp next_glyphs(%{settings: settings} = state) do
    sets = Cells.sets() -- [:braille]

    display =
      case Enum.find_index(sets, &(&1 == settings.display)) do
        nil -> hd(sets)
        index -> Enum.at(sets, rem(index + 1, length(sets)))
      end

    put_settings(state, %{settings | display: display})
  end

  defp trace_event({:mouse, %{type: type, x: x, y: y}}),
    do: Trace.write(:mouse, type: type, x: x, y: y)

  defp trace_event({:key, key}), do: Trace.write(:key, key: key)
  defp trace_event({:key, key, _modifiers}), do: Trace.write(:key, key: key)
  defp trace_event({:key_down, key, _modifiers}), do: Trace.write(:key, key: key)
  defp trace_event(_event), do: :ok

  defp push_input(%{joined: nil} = state), do: state

  defp push_input(state) do
    read = Party.state(state.party)

    sent =
      read
      |> Look.steered(look(state))
      |> Map.put(:aim, sent_aim(state, read.aim))
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

  defp sent_aim(state, read_aim) do
    controls = state.party.controls

    Controls.stick_aim(controls, state.look, fn -> view_focus(state) end) ||
      Controls.aim(controls) || pointer_aim(state, read_aim)
  end

  defp pointer_aim(%{settings: %{pointer: true}} = state, {_x, _y} = cell),
    do: aim_in_world(state, cell)

  defp pointer_aim(_state, _cell), do: nil

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
      eye: Draw.eye_height(game, scene),
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

  defp start_audio(game, props, settings, launch) do
    sink =
      if muted?(props, launch),
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

  defp muted?(props, launch) do
    Cauldron.Launch.value(
      given: Map.get(props, :mute),
      saved: launch,
      key: :mute,
      env: {"CAULDRON_MUTE", &mute_text/1},
      config: {:cauldron_2d_drafter, :mute},
      default: false
    ) == true
  end

  defp mute_text(text) when text in ["1", "true"], do: true
  defp mute_text(text) when text in ["0", "false"], do: false
  defp mute_text(_text), do: nil

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
    cue =
      if Fronts.showing?(state),
        do: Fronts.cue(state),
        else: state.game.cue(state.view, state.screen)

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
