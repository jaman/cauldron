defmodule Cauldron2D.Drafter.Client do
  @moduledoc """
  The drafter application that puts a `Cauldron2D.World` in front of one player.

  Runs a game's client module — one implementing `Cauldron2D.Client.Game` —
  through its screens: a title, a lobby listing the arenas, settings, the arena itself,
  and a summary when the game's `outcome/1` says play is over for this player. It holds the player's input, their audio, and their connection to the world.

  An arena whose `world` is `{module, opts}` is this player's alone: the client starts
  a `Cauldron2D.World` for it when the player joins and stops it when they leave, and
  `p` pauses and resumes it. A game whose `lobby?/0` is false goes from the title
  straight into its first arena, and back to the title from it.

      Drafter.Server.start_ssh(Cauldron2D.Drafter.Client,
        auth: {:accounts, accounts},
        tunnel: true,
        mount_props: %{game: MyGame.Client, accounts: accounts}
      )

  ## Mount props

    * `:game` — the client module. Required
    * `:username` — the player's name, set by the ssh transport. Default `"player"`
    * `:sink` — a `TuningFork.Sink` module or `{module, opts}` this player's audio plays
      through. Default: the game's `sink/1` given all the mount props, else
      `TuningFork.Sink.Speaker` when that package is present, else silence
    * `:settings` — the map `Cauldron2D.Drafter.Client.Settings.to_props/1` produced,
      from the account props; a settings file for the player overrides it. Default: the
      game's first preset
    * `:accounts` — the `Drafter.Accounts` server settings are saved to. Default: none
    * `:kind` — the kind of client this is, the key its settings are kept under (see
      `Cauldron2D.Drafter.Client.Settings`). Default `:terminal`
    * `:start` — the first screen, `:title` or `:lobby`. Started at the lobby, the
      client has no title of its own: going back from the lobby (`Esc` or `q`) stops
      it, as quitting from the title does. Default `:title`

  Every other mount prop is the game's, read by its `sink/1`, `pages/1` and `arenas/1`.

  ## Embedding

  A game with screens of its own — its own title, a menu, pages that take input —
  runs its own `Drafter.App` and drives this one from it: it keeps the client's state
  from `mount/1` (with `start: :lobby`), and hands it its events, messages and timers
  through `handle_event/2`, `handle_event/3`, `on_message/2` and `on_ready/1`, draws
  `render/1`, and calls `unmount/1` when done. A `{:stop, reason}` from the client
  is its wish to end: the game takes its screens back. The game's `use Drafter.App`
  needs the same options this module's has — `key_release: true, cell_size: true,
  frame_pacing: :always` — and its `refresh_rate/0` should be `refresh_rate/0` here.

  ## Tracing

  With `CAULDRON_TRACE` set (see `Cauldron2D.Trace`), the client writes every key and
  mouse event it steers with (`key`, `mouse`), every input it sends the world (`input`,
  with the actions held and the aim in tiles) and every frame the world sends back
  (`frame`, with its tick), so `mix cauldron.report --from mouse --to frame` measures
  the way round.

  ## Keys

  The client's own keys are `default_keys/0`, each replaceable or dropped by the game's
  `client_keys/0`; what follows describes the defaults. In the arena `t` opens a line
  to talk to everyone in it — `Enter` sends, `Esc` cancels, and no key steers while it
  is open. `Esc` goes back: settings to where it was opened from, arena to lobby, lobby
  to title, title out of the program. `q` quits the arena for the lobby too, and goes
  to the title from the lobby. `^Q` and `^C` quit from anywhere. `?` shows the arena's key hints and hides
  them again; held, it shows them until released. The `fps` key, bound only when the
  game binds it, shows under the arena how many frames a second the world sends and
  hides it again. `=` (or `+`) and `-` zoom the arena in and out through the levels
  `Cauldron2D.Drafter.Surface.zoom_levels/2` gives for the display in use, the wheel
  too (one step for the events a notch sends within 150 ms), and `0` puts the zoom
  back; the zoom shows under the world while it is not
  native. Watching (joined with `w`), the arrows and a drag with the left button pan
  the view, the wheel zooms about the pointer, and `0` recentres; flying, the view
  stays on the ship and the wheel zooms about it. A page the game adds (`pages/1`)
  opens from the title on its key; `Esc` or `q` closes it.

  Title: `Enter` plays, `s` opens settings, `h` the guide, `q` quits. Lobby: `↑`/`↓`
  pick an arena, `t` a team where the arena has them, `Enter` joins, `w` watches, `s`
  opens settings, `c` chats and `Enter` on an empty line leaves the chat. Settings: `↑`/`↓` move over
  the items — preset, each action's binding, pointer steering, effects level, music
  level, display (pixels where the terminal has them, braille, or glyphs), frame rate
  (auto picks the terminal's best) — `←`/`→` change the item under the cursor, `Enter` on a binding then
  a key or a mouse button adds it to the binding, `Backspace` removes the binding's last
  key, `Esc` during a rebind cancels it. Arena: the game's bindings; `Tab`
  opens settings without leaving the ship; the pointer steers only when pointer
  steering is on, and a key bound to one of the game's `steering/0` actions takes over
  from it until the pointer moves again.
  """

  use Drafter.App, key_release: true, cell_size: true, frame_pacing: :always

  alias Cauldron2D.{Atlas, Audio, Camera, Input, Player, Trace, World}
  alias Cauldron2D.Audio.Music
  alias Cauldron2D.Client.Game
  alias Cauldron2D.Drafter.{Chat, Surface}
  alias Cauldron2D.Drafter.Client.{Screens, Settings}
  alias Cauldron2D.World.Presence
  alias Drafter.Session.Context

  @hold_ms 250
  @default_keys %{
    back: :escape,
    title: :q,
    settings: :tab,
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
    zoom_reset: :"0"
  }
  @pan_step 4

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

    %{
      game: game,
      props: props,
      kind: kind,
      username: username,
      accounts: Map.get(props, :accounts),
      pages: optional(game, :pages, [props], []),
      keys: Map.merge(@default_keys, optional(game, :client_keys, [], %{})),
      chat?: optional(game, :chat?, [], true),
      lobby?: optional(game, :lobby?, [], true),
      local_world: nil,
      settings: settings,
      screen: Map.get(props, :start, :title),
      start: Map.get(props, :start, :title),
      return: :title,
      help?: false,
      help_pressed_at: nil,
      fps?: false,
      fps: %{frames: 0, since: now(), shown: nil},
      audio: start_audio(game, props, settings),
      input: nil,
      arena: nil,
      view: nil,
      geometry: nil,
      zoom: 1,
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
      summary_arena: nil,
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
    if state.start == :lobby, do: Drafter.blur(:chat_input)
    %{state | lobby: %{state.lobby | messages: Chat.history(:lobby)}}
  end

  @impl true
  def unmount(state) do
    leave_arena(state)
    if state.audio, do: GenServer.stop(state.audio)
    Trace.stop()
    :ok
  end

  @impl true
  def render(%{screen: :title} = state), do: Screens.title(state)
  def render(%{screen: :lobby} = state), do: Screens.lobby(state)
  def render(%{screen: :settings} = state), do: Screens.settings(state)
  def render(%{screen: {:page, key}} = state), do: Screens.page(state, key)
  def render(%{screen: :guide} = state), do: Screens.guide(state)
  def render(%{screen: :arena} = state), do: Screens.arena(state)
  def render(%{screen: :summary} = state), do: Screens.summary(state)

  @impl true
  def handle_event(:arena_geometry, geometry, state),
    do: {:noreply, %{state | geometry: geometry}}

  def handle_event(:guide_geometry, %{size: {_columns, rows}}, state) when rows > 0,
    do: {:ok, %{state | guide: %{state.guide | rows: rows}}}

  def handle_event(:guide_geometry, _geometry, state), do: {:noreply, state}

  def handle_event(:talk_submit, _text, state) do
    case String.trim(state.talk_text) do
      "" -> :ok
      text -> Chat.say({:arena, state.arena.id}, state.username, text)
    end

    Drafter.blur(:talk_input)
    {:ok, %{state | talk_text: "", talking?: false}}
  end

  def handle_event({:page, key}, _data, %{screen: :title} = state), do: {:ok, to_page(state, key)}

  def handle_event(:chat_submit, _text, state) do
    case String.trim(state.chat_text) do
      "" -> Drafter.blur(:chat_input)
      text -> Chat.say(:lobby, state.username, text)
    end

    {:ok, %{state | chat_text: ""}}
  end

  def handle_event(_name, _data, state), do: {:noreply, state}

  @impl true
  def handle_event({:key, :q, [:ctrl]}, _state), do: {:stop, :normal}
  def handle_event({:key, :c, [:ctrl]}, _state), do: {:stop, :normal}

  def handle_event({:key_release_support, true}, state),
    do:
      {:ok,
       %{
         state
         | input: state.input && Input.handle(state.input, {:key_release_support, true}, now())
       }}

  def handle_event({:cell_size, _}, state), do: {:noreply, state}

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
  defp screen_key(event, %{screen: :arena} = state), do: arena_event(event, state)
  defp screen_key({:key, :enter}, %{screen: :summary} = state), do: {:ok, after_summary(state)}

  defp screen_key({:key, key}, %{screen: :summary} = state) do
    cond do
      key == state.keys.back -> {:ok, to_lobby(state)}
      key == state.keys.title -> {:ok, to_title(state)}
      true -> {:noreply, state}
    end
  end

  defp screen_key(_event, state), do: {:noreply, state}

  defp blur_pages(%{pages: pages}), do: Enum.each(pages, &Drafter.blur(:"page_#{&1.key}"))

  defp to_page(state, key) do
    Drafter.blur(:"page_#{key}")
    %{state | screen: {:page, key}}
  end

  @impl true
  def on_message({:cauldron_frame, frame}, %{arena: arena} = state) when arena != nil do
    Trace.write(:frame, tick: frame.tick)

    state =
      %{
        state
        | view: frame.view,
          input: Input.expire(state.input, now()),
          fps: counted(state.fps, now())
      }
      |> followed()

    Audio.listener(state.audio, state.game.listener(frame.view))
    Audio.play(state.audio, frame.events)

    case outcome(state, frame.view) do
      nil ->
        state |> push_input() |> cue_music()

      summary ->
        state
        |> Map.put(:summary_arena, state.arena)
        |> leave_arena()
        |> Map.merge(%{screen: :summary, summary: summary, view: frame.view})
        |> cue_music()
    end
  end

  def on_message({:chat, {:arena, _id}, message}, state) do
    %{state | talk: Enum.take(state.talk ++ [message], -20)}
  end

  def on_message({:cauldron_atlas, _name, :changed}, state), do: state

  def on_message({:cauldron_players, _world, _change, _id}, state) do
    %{state | lobby: %{state.lobby | changes: state.lobby.changes + 1}}
  end

  def on_message({:chat, :lobby, message}, state) do
    %{
      state
      | lobby: %{state.lobby | messages: Enum.take(state.lobby.messages ++ [message], -100)}
    }
  end

  def on_message(_message, state), do: state

  defp counted(%{frames: frames, since: since} = fps, at) when at - since >= 1000,
    do: %{fps | frames: 0, since: at, shown: frames + 1}

  defp counted(fps, _at), do: %{fps | frames: fps.frames + 1}

  defp help_released(%{help_pressed_at: at} = state) when at != nil do
    if now() - at >= @hold_ms,
      do: %{state | help?: false, help_pressed_at: nil},
      else: %{state | help_pressed_at: nil}
  end

  defp play(%{lobby?: false} = state) do
    case arenas(state) do
      [arena | _] -> join(%{state | screen: :lobby}, arena, %{})
      [] -> to_lobby(state)
    end
  end

  defp play(state), do: to_lobby(state)

  defp to_lobby(%{lobby?: false} = state), do: to_title(state)

  defp to_lobby(state) do
    Drafter.blur(:chat_input)
    state |> leave_arena() |> Map.put(:screen, :lobby) |> cue_music()
  end

  defp to_title(state) do
    blur_pages(state)
    state |> leave_arena() |> Map.put(:screen, state.start) |> cue_music()
  end

  @doc "The game's arenas, from its `arenas/1` given the mount props."
  @spec arenas(map()) :: [Game.arena()]
  def arenas(%{game: game} = state), do: game.arenas(Map.get(state, :props, %{}))

  defp to_guide(%{screen: from} = state) do
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

  defp leave_settings(%{return: :arena, arena: arena} = state) when arena != nil do
    %{state | screen: :arena, input: new_input(state)}
  end

  defp leave_settings(%{return: :arena} = state), do: %{state | screen: :lobby}
  defp leave_settings(%{return: screen} = state), do: %{state | screen: screen}

  defp release_keys(%{input: nil} = state), do: state
  defp release_keys(state), do: %{state | input: new_input(state)} |> push_input()

  defp new_input(state) do
    Input.new(state.settings.bindings,
      releases?: Context.key_release?(),
      toggles: state.game.toggles(),
      holds: optional(state.game, :holds, []),
      steering: optional(state.game, :steering, [])
    )
  end

  defp lobby_key({:mouse, %{type: :scroll, direction: :down}}, state), do: {:ok, select(state, 1)}
  defp lobby_key({:mouse, %{type: :scroll, direction: :up}}, state), do: {:ok, select(state, -1)}

  defp lobby_key({:mouse, %{type: :mouse_down, button: :left, y: y}}, state) do
    case Screens.arena_at(arenas(state), state.lobby.selected, y) do
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
    do: {:ok, select(state, length(arenas(state)) - 1 - state.lobby.selected)}

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
  defp lobby_action(leave, %{start: :lobby}) when leave in [:back, :title], do: {:stop, :normal}
  defp lobby_action(leave, state) when leave in [:back, :title], do: {:ok, to_title(state)}
  defp lobby_action(_action, state), do: {:noreply, state}

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
    teams = arenas(state) |> Enum.at(state.lobby.selected, %{}) |> Map.get(:teams, [])
    choices = [nil | teams]
    index = Enum.find_index(choices, &(&1 == state.lobby.team)) || 0
    %{state | lobby: %{state.lobby | team: Enum.at(choices, rem(index + 1, length(choices)))}}
  end

  defp select(state, delta) do
    count = max(1, length(arenas(state)))

    selected =
      if abs(delta) > 1,
        do: state.lobby.selected |> Kernel.+(delta) |> max(0) |> min(count - 1),
        else: Integer.mod(state.lobby.selected + delta, count)

    %{state | lobby: %{state.lobby | selected: selected}}
  end

  defp join_selected(state, extra) do
    case Enum.at(arenas(state), state.lobby.selected) do
      nil -> state
      arena -> join(state, arena, extra)
    end
  end

  defp join(state, arena, extra) do
    game_props =
      optional(
        state.game,
        :join_props,
        [%{username: state.username, settings: state.settings}],
        %{}
      )

    props = %{username: state.username} |> Map.merge(game_props) |> Map.merge(extra)
    {arena, local} = local_world(arena)

    case Player.join(arena.world, state.username, props) do
      :ok ->
        Chat.join({:arena, arena.id})

        state = %{
          state
          | arena: arena,
            local_world: local,
            screen: :arena,
            view: nil,
            last_input: nil,
            talk: Chat.history({:arena, arena.id}),
            talking?: false,
            zoom: 1,
            pan: {0.0, 0.0},
            subject: nil,
            watching?: Map.get(extra, :spectate, false) == true,
            drag: nil
        }

        cue_music(%{state | input: new_input(state)})

      {:error, reason} ->
        if local, do: GenServer.stop(local)

        notice = %{
          from: arena.name,
          text: "could not join: " <> Game.refusal_text(state.game, reason)
        }

        %{
          state
          | lobby: %{state.lobby | messages: Enum.take(state.lobby.messages ++ [notice], -100)}
        }
    end
  end

  defp local_world(%{world: {module, opts}} = arena) do
    {:ok, world} = World.start_link([game: module] ++ Keyword.drop(opts, [:name]))
    {%{arena | world: world}, world}
  end

  defp local_world(arena), do: {arena, nil}

  defp leave_arena(%{arena: nil} = state), do: state

  defp leave_arena(state) do
    try do
      Player.leave(state.arena.world, state.username)
      Chat.leave({:arena, state.arena.id})
    catch
      :exit, _gone -> :ok
    end

    if state.local_world && Process.alive?(state.local_world),
      do: GenServer.stop(state.local_world)

    %{
      state
      | arena: nil,
        local_world: nil,
        view: nil,
        input: nil,
        talking?: false,
        zoom: 1,
        pan: {0.0, 0.0},
        subject: nil,
        watching?: false,
        drag: nil
    }
  end

  defp toggle_pause(%{local_world: nil} = state), do: state

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
    protocol =
      case Context.terminal_protocol() do
        {:ok, protocol} -> protocol
        :unprobed -> nil
      end

    Drafter.set_refresh_rate(
      Integer.to_string(Settings.frame_rate(state.settings, protocol)) <> "fps"
    )
  end

  defp put_settings(state, settings) do
    Audio.levels(state.audio, settings.sfx, settings.music)
    %{state | settings: settings}
  end

  defp step_preset(state, delta) do
    presets = Settings.presets(state.game)
    current = Enum.find_index(presets, &(&1 == state.settings.preset)) || 0
    preset = Enum.at(presets, Integer.mod(current + delta, length(presets)))
    %{state | settings: Settings.choose_preset(state.settings, state.game, preset)}
  end

  defp rebind_key({:key, :escape}), do: :cancel

  defp rebind_key({:mouse, %{type: :mouse_down, button: button}})
       when button in [:left, :middle, :right], do: {:mouse, button}

  defp rebind_key({:key_down, key, _mods}) when key in [:enter, :escape, :tab], do: nil
  defp rebind_key({:key_down, key, []}), do: key
  defp rebind_key({:key_down, key, mods}), do: {key, mods}
  defp rebind_key({:key, key}) when key not in [:enter, :tab], do: key
  defp rebind_key({:key, key, mods}), do: {key, mods}
  defp rebind_key(_event), do: nil

  defp save_settings(state) do
    Settings.save(state.settings, state.game, state.username, state.accounts, kind: state.kind)
    state
  end

  defp arena_event({:key, :escape}, %{talking?: true} = state) do
    Drafter.blur(:talk_input)
    {:ok, %{state | talking?: false, talk_text: ""}}
  end

  defp arena_event(_event, %{talking?: true} = state), do: {:noreply, state}

  @arena_actions [:back, :title, :settings, :fps, :pause, :talk, :zoom_in, :zoom_out, :zoom_reset]
  @pans %{left: {-1, 0}, right: {1, 0}, up: {0, -1}, down: {0, 1}}

  defp arena_event({:key, key}, %{watching?: true} = state) when is_map_key(@pans, key) do
    {dx, dy} = Map.fetch!(@pans, key)
    {:ok, pan_by(state, {dx * @pan_step / state.zoom, dy * @pan_step / state.zoom})}
  end

  defp arena_event({:key, key} = event, state),
    do: arena_action(client_action(state.keys, key, @arena_actions), event, state)

  @wheel_ms 150

  defp arena_event({:mouse, %{type: :scroll, direction: direction} = mouse}, state)
       when direction in [:up, :down] do
    at = now()

    if state.wheel_at != nil and at - state.wheel_at < @wheel_ms do
      {:noreply, state}
    else
      step = if direction == :up, do: 1, else: -1

      {:ok,
       zoom_step(%{state | wheel_at: at}, step, if(state.watching?, do: pane_cell(state, mouse)))}
    end
  end

  defp arena_event(
         {:mouse, %{type: :mouse_down, button: :left, x: x, y: y}},
         %{watching?: true} = state
       ),
       do: {:ok, %{state | drag: {x, y}}}

  defp arena_event(
         {:mouse, %{type: :drag, x: x, y: y}},
         %{watching?: true, drag: {fx, fy}} = state
       ),
       do:
         {:ok,
          pan_by(%{state | drag: {x, y}}, {(fx - x) / (2 * state.zoom), (fy - y) / state.zoom})}

  defp arena_event({:mouse, %{type: :mouse_up}}, %{watching?: true, drag: drag} = state)
       when drag != nil,
       do: {:ok, %{state | drag: nil}}

  defp arena_event(event, state), do: arena_input(event, state)

  defp pane_cell(%{geometry: nil}, _mouse), do: nil
  defp pane_cell(%{geometry: %{rect: rect}}, %{x: x, y: y}), do: {x - rect.x, y - rect.y}

  defp pan_by(%{pan: {px, py}} = state, {dx, dy}),
    do: %{followed(state) | pan: {px + dx, py + dy}}

  defp followed(%{pan: {px, py}, view: view, game: game} = state)
       when view != nil and px == 0 and py == 0,
       do: %{state | subject: Map.get(game.scene(view), :subject)}

  defp followed(%{view: view, game: game} = state) when view != nil,
    do: follow(state, game.scene(view))

  defp followed(state), do: state

  @doc "The state with its pan dropped when the scene's `:subject` is not the one the pan was taken on; a scene with no subject keeps the pan."
  @spec follow(map(), Game.scene()) :: map()
  def follow(%{subject: subject} = state, %{subject: subject}), do: state
  def follow(state, %{subject: subject}), do: %{state | pan: {0.0, 0.0}, subject: subject}
  def follow(state, _scene), do: state

  @doc "The zoom levels this client steps through: `Cauldron2D.Drafter.Surface.zoom_levels/2` for the game's atlas and the display in use."
  @spec zoom_levels(map()) :: [number()]
  def zoom_levels(%{game: game, settings: settings}),
    do: Surface.zoom_levels(game.atlas(), Settings.surface_mode(settings))

  defp zoom_step(state, step, anchor) do
    levels = zoom_levels(state)
    index = Enum.find_index(levels, &(&1 == state.zoom)) || Enum.find_index(levels, &(&1 == 1))
    zoom_to(state, Enum.at(levels, min(max(index - step, 0), length(levels) - 1)), anchor)
  end

  defp zoom_to(%{zoom: zoom} = state, zoom, _anchor), do: state

  defp zoom_to(
         %{geometry: %{size: size}, view: view, game: game, zoom: from} = state,
         to,
         {_, _} = cell
       )
       when view != nil do
    scene = game.scene(view)
    {fx, fy} = scene.focus
    {px, py} = state.pan
    {nx, ny} = Camera.zoom_about({fx + px, fy + py}, cell, size, from, to)
    %{state | zoom: to, pan: {nx - fx, ny - fy}, subject: Map.get(scene, :subject)}
  end

  defp zoom_to(state, to, _anchor), do: %{state | zoom: to}

  @doc "The point the arena is drawn around: the scene's focus moved by the pan."
  @spec focus(map(), Game.scene()) :: {number(), number()}
  def focus(%{pan: {px, py}}, %{focus: {fx, fy}}), do: {fx + px, fy + py}
  def focus(_state, %{focus: focus}), do: focus

  defp arena_action(leave, _event, state) when leave in [:back, :title],
    do: {:ok, to_lobby(state)}

  defp arena_action(:settings, _event, state), do: {:ok, to_settings(state)}
  defp arena_action(:fps, _event, state), do: {:ok, %{state | fps?: not state.fps?}}
  defp arena_action(:zoom_in, _event, state), do: {:ok, zoom_step(state, 1, nil)}
  defp arena_action(:zoom_out, _event, state), do: {:ok, zoom_step(state, -1, nil)}
  defp arena_action(:zoom_reset, _event, state), do: {:ok, %{state | zoom: 1, pan: {0.0, 0.0}}}

  defp arena_action(:pause, _event, %{local_world: world} = state) when world != nil,
    do: {:ok, toggle_pause(state)}

  defp arena_action(:talk, _event, %{chat?: true, arena: arena} = state) when arena != nil,
    do: talk(state)

  defp arena_action(_action, event, state), do: arena_input(event, state)

  defp talk(state) do
    Drafter.focus(:talk_input)
    {:ok, %{state | talking?: true, input: new_input(state)} |> push_input()}
  end

  defp arena_input(event, %{input: input} = state) when input != nil do
    trace_event(event)
    {:ok, %{state | input: Input.handle(input, event, now())} |> push_input()}
  end

  defp arena_input(_event, state), do: {:noreply, state}

  defp trace_event({:mouse, %{type: type, x: x, y: y}}),
    do: Trace.write(:mouse, type: type, x: x, y: y)

  defp trace_event({:key, key}), do: Trace.write(:key, key: key)
  defp trace_event({:key, key, _modifiers}), do: Trace.write(:key, key: key)
  defp trace_event({:key_down, key, _modifiers}), do: Trace.write(:key, key: key)
  defp trace_event(_event), do: :ok

  defp push_input(%{input: nil} = state), do: state

  defp push_input(state) do
    read = Input.state(state.input)

    sent = %{
      read
      | aim: if(state.settings.pointer and read.aim != nil, do: aim_in_world(state, read.aim))
    }

    if sent != state.last_input do
      Trace.write(:input, held: Enum.join(sent.held, ","), aim: aim_text(sent.aim))
      Player.input(state.arena.world, state.username, sent)
      %{state | last_input: sent}
    else
      state
    end
  end

  defp after_summary(state) do
    case next_arena(state) do
      nil -> to_lobby(state)
      arena -> state |> Map.put(:screen, :lobby) |> join(arena, team_props(state))
    end
  end

  @doc false
  @spec next_arena(map()) :: map() | nil
  def next_arena(%{summary: %{next: :same_arena}, summary_arena: arena}), do: arena

  def next_arena(%{summary: %{next: :next_arena}, summary_arena: arena} = state) do
    arenas = arenas(state)

    case Enum.find_index(arenas, &(&1.id == arena.id)) do
      nil -> List.first(arenas)
      index -> Enum.at(arenas, rem(index + 1, length(arenas)))
    end
  end

  def next_arena(_state), do: nil

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
    scene = game.scene(view)
    rect = geometry.rect

    origin =
      Camera.exact_origin(focus(state, scene), Camera.zoomed(geometry.size, zoom))

    Camera.tile_at(origin, {x - rect.x, y - rect.y}, zoom)
  end

  defp aim_in_world(_state, _cell), do: nil

  defp start_audio(game, props, settings) do
    sink = Map.get(props, :sink) || optional(game, :sink, [props], default_sink())

    {:ok, audio} =
      Audio.start_link(
        name: nil,
        sink: sink,
        sounds: game.sounds(),
        sfx: settings.sfx,
        music: settings.music,
        music_dir: Game.music_dir(game),
        parallel: true
      )

    for {name, spec} <- game.music(), do: Music.piece(audio, name, spec)
    audio
  end

  defp default_sink,
    do:
      if(Code.ensure_loaded?(TuningFork.Sink.Speaker),
        do: TuningFork.Sink.Speaker,
        else: TuningFork.Sink.Silent
      )

  defp cue_music(%{screen: :arena, view: nil} = state), do: state

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
