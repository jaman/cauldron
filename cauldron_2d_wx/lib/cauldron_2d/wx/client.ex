defmodule Cauldron2D.Wx.Client do
  @moduledoc """
  The window that puts a game's worlds in front of one player: a title, a lobby of
  worlds, settings, the world, a summary, the guide and the game's own pages, from a
  `Cauldron.Client.Game` — the desktop's twin of the terminal's
  `Cauldron2D.Drafter.Client`, reading the game's description the same way.

      Cauldron2D.Wx.Client.run(game: MyGame.Client, username: "alice")

  The world is a `Cauldron2D.Wx.View` joined through a link the `:link` function gives
  for the chosen world: without one, a local link to the world's process — a name on this
  node, or `{module, opts}` for a world of the player's own, started for them and
  stopped when they leave. Settings — the key preset, the effects and music levels,
  whether the pointer aims, the frame rate (one of `Cauldron.Client.Game.frame_rates/1`),
  and the game's own options (`c:Cauldron.Client.Game.options/0`)
  — are kept per player under `Cauldron.Paths.config(home, "<player>.desktop.settings")`,
  `home` the game's `Cauldron.Client.Game.home/1`, or under the game's atlas name
  where a file is kept there and none under the home; the game's menu changes them too.

  The game's own title and summary (`c:Cauldron.Client.Game.fronts/1`) are drawn and
  run here in place of the window's own, its `start/0` decides where the window opens
  (a function flow is the terminal client's own, and opens on the title here), and in
  the world its menu, its look and the client's keys (`client_keys/0`) work as they do
  in the terminal, through `Cauldron.Client.Stage`. Game controllers play by the game's
  padmap (`Cauldron.Client.Game.padmap/3`) and work its fronts and menus.

  ## Keys

  The client's keys are `Cauldron.Client.Keys.of/1`'s. Title: `Enter` plays, the
  `settings_menu` key (`s`) settings, `guide` (`h`) the guide, a page's key, `back` or
  `title` (`Esc`, `q`) quits. Lobby: `↑`/`↓`, `PgUp`/`PgDn`, `Home`/`End`, `Enter`
  join, `watch` (`w`), `team` (`t`), `settings_menu`, `guide`, `chat` (`c`, in a game
  with a chat: a line to the lobby's room, `Enter` says it, `Esc` drops it), `back` to
  the title.
  Settings: `↑`/`↓` choose, `←`/`→` change, `Esc` back. World: the game's keys and the
  client's (`Cauldron.Client.Stage`). Summary: `Enter` again or on, as the outcome's
  `:next` says, `Esc` lobby. Guide and pages: `↑`/`↓`, `Esc` back. Every item on a
  screen can be clicked instead.

  ## Options

    * `:game` — the module. Required
    * `:username` — the player's name. Default `"player"`
    * `:props` — the props the game's `worlds/1`, `pages/1`, `fronts/1` and `sink/1`
      are given, and the launch's `:start`. Default `%{}`
    * `:link` — a function from a world to the link the view joins with, `{:local,
      opts}` or `{:socket, opts}`. Default: a local link to the world's process
    * `:size` — the window. Default `{1320, 800}`
    * `:scale` — screen pixels a picture pixel. Default `1`
    * `:backdrop` — drawn behind the screens, as `Cauldron2D.Wx.Text` takes it
  """

  @behaviour :wx_object

  alias Cauldron.{Chat, Paths}
  alias Cauldron.Client.{Fronts, Game, Menus, Stage, Start}
  alias Cauldron.Client.Keys, as: ClientKeys
  alias Cauldron2D.{Atlas, Draw}
  alias Cauldron2D.Client.Look
  alias Cauldron2D.Wx.Client.Screens
  alias Cauldron2D.Wx.{Const, Keys, Text, View}

  require Record

  Record.defrecordp(:wx, Record.extract(:wx, from_lib: "wx/include/wx.hrl"))
  Record.defrecordp(:wxClose, Record.extract(:wxClose, from_lib: "wx/include/wx.hrl"))

  @enter 13
  @escape 27
  @left 314
  @up 315
  @right 316
  @down 317
  @page_up 366
  @page_down 367
  @home 313
  @end_key 312
  @step 0.05
  @settings [:preset, :sfx, :music, :pointer, :fps]
  @title_actions [:settings_menu, :guide, :back, :title]
  @lobby_actions [:team, :watch, :settings_menu, :guide, :chat, :back, :title]
  @chat_kept 8
  @said_most 500

  @doc "Open the window and block until it is closed."
  @spec run(keyword()) :: :ok
  def run(opts) do
    wx = :wx.new()
    client = :wx_object.start_link(__MODULE__, {wx, opts}, [])
    # Blocks until the window closes: that is the app's lifetime, so no timeout.
    :wx_object.call(client, :wait, :infinity)
    :wx.destroy()
    :ok
  end

  @impl :wx_object
  def init({wx, opts}) do
    game = Keyword.fetch!(opts, :game)
    username = Keyword.get(opts, :username, "player")
    props = Map.merge(%{username: username}, Keyword.get(opts, :props, %{}))

    frame =
      :wxFrame.new(wx, Const.id_any(), String.to_charlist(game.title().name),
        size: Keyword.get(opts, :size, {1320, 800})
      )

    sizer = :wxBoxSizer.new(Const.vertical())
    text = Text.new(frame, Keyword.take(opts, [:backdrop]) ++ [owner: self()])
    me = self()
    settings = load_settings(game, username)

    world =
      View.new(frame,
        size: Keyword.get(opts, :view_size, {960, 640}),
        scale: Keyword.get(opts, :scale, 1),
        hud: Keyword.get(opts, :hud, :right),
        hud_size: Keyword.get(opts, :hud_size, 300),
        on_over: fn ended -> send(me, {:play, :over, ended}) end,
        on_closed: fn reason -> send(me, {:play, :closed, reason}) end,
        on_refused: fn reason -> send(me, {:play, :refused, reason}) end,
        on_go: fn to -> send(me, {:play, :go, to}) end,
        on_settings: fn settings -> send(me, {:play, :settings, settings}) end,
        on_key: fn code -> send(me, {:play, :key, code}) end,
        on_pad: fn button -> send(me, {:play, :pad, button}) end,
        on_world: fn id -> send(me, {:play, :world, id}) end
      )

    :wxSizer.add(sizer, Text.window(text), proportion: 1, flag: Const.expand())
    :wxSizer.add(sizer, View.window(world), proportion: 1, flag: Const.expand())
    :wxWindow.hide(View.window(world))
    :wxFrame.setSizer(frame, sizer)
    :wxFrame.connect(frame, :close_window)
    :wxFrame.show(frame)
    Text.focus(text)
    flow = Start.flow(game, props)

    state = %{
      frame: frame,
      sizer: sizer,
      text: text,
      play: world,
      game: game,
      username: username,
      props: props,
      link:
        Keyword.get(opts, :link, fn world ->
          {:local,
           game: game,
           world: world.world,
           name: username,
           props: Map.drop(props, [:username]),
           client_props: props,
           sink: Game.optional(game, :sink, [props], TuningFork.Sink.Speaker),
           chat_room: {:world, to_string(world.id)}}
        end),
      flow: flow,
      keys: ClientKeys.of(game),
      fronts: Fronts.of(game, props),
      front: nil,
      pages: Game.optional(game, :pages, [props], []),
      settings: settings,
      setting: 0,
      screen: :title,
      from: :title,
      worlds: [],
      selected: 0,
      team: nil,
      chosen: nil,
      summary: nil,
      last_view: nil,
      guide_offset: 0,
      page: nil,
      status: "",
      chat?: Stage.chat?(game),
      chat: [],
      chatting: nil,
      waiting: []
    }

    {frame, begin(state)}
  end

  defp begin(%{flow: {:play, id, opts}} = state) do
    if Keyword.get(opts, :title, false), do: to_title(state), else: enter(state, id)
  end

  defp begin(%{flow: {:lobby, opts}} = state) do
    if Keyword.get(opts, :title, true), do: to_title(state), else: to_lobby(state)
  end

  defp begin(state), do: to_title(state)

  defp load_settings(game, username) do
    defaults = %{
      preset: game.keymaps() |> Enum.map(&elem(&1, 0)) |> List.first(),
      sfx: 0.85,
      music: 0.35,
      pointer: true
    }

    saved =
      case File.read(settings_path(game, username)) do
        {:ok, bytes} -> :erlang.binary_to_term(bytes)
        {:error, _} -> %{}
      end

    Stage.with_options(game, Map.merge(defaults, saved))
  rescue
    ArgumentError ->
      Stage.with_options(game, %{preset: nil, sfx: 0.85, music: 0.35, pointer: true})
  end

  defp save_settings(state) do
    path = settings_path(state.game, state.username)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, :erlang.term_to_binary(state.settings))
    state
  end

  defp settings_path(game, username) do
    file = "#{username}.desktop.settings"
    Paths.existing(Paths.config(Game.home(game), file), Paths.config(game.atlas(), file))
  end

  defp draw(state) do
    Text.show(state.text, Screens.draw(state, Text.size(state.text)))
    state
  end

  @impl :wx_object
  def handle_call(:wait, from, state), do: {:noreply, %{state | waiting: [from | state.waiting]}}

  @impl :wx_object
  def handle_event(wx(event: wxClose()), state), do: {:stop, :normal, closing(state)}
  def handle_event(_event, state), do: {:noreply, state}

  @impl :wx_object
  def handle_info({:cauldron_wx_text, :key, code}, state), do: {:noreply, key(code, state)}

  def handle_info({:cauldron_wx_text, :action, action}, state),
    do: {:noreply, action(action, state)}

  def handle_info({:cauldron_wx_text, :char, char}, %{chatting: text} = state)
      when text != nil and char >= 32 and char != 127,
      do:
        {:noreply, draw(%{state | chatting: String.slice(text <> <<char::utf8>>, 0, @said_most)})}

  def handle_info({:cauldron_wx_text, :char, _char}, state), do: {:noreply, state}

  def handle_info({:chat, :lobby, message}, state),
    do:
      {:noreply, redrawn_lobby(%{state | chat: Enum.take(state.chat ++ [message], -@chat_kept)})}

  def handle_info({:play, :key, code}, state), do: {:noreply, front_key(code, state)}
  def handle_info({:play, :pad, button}, state), do: {:noreply, front_pad(button, state)}

  def handle_info({:play, :world, id}, state),
    do:
      {:noreply,
       %{state | chosen: Enum.find(worlds(state), state.chosen, &(to_string(&1.id) == id))}}

  def handle_info({:play, :over, ended}, state), do: {:noreply, to_summary(state, ended)}
  def handle_info({:play, :go, to}, state), do: {:noreply, went(to, state)}

  def handle_info({:play, :settings, settings}, state),
    do: {:noreply, %{state | settings: Map.merge(state.settings, settings)} |> save_settings()}

  def handle_info({:play, :refused, reason}, state),
    do:
      {:noreply,
       state
       |> Map.put(:status, "could not join: " <> Game.refusal_text(state.game, reason))
       |> to_lobby()}

  def handle_info({:play, :closed, _reason}, %{screen: :play} = state),
    do: {:noreply, to_lobby(state)}

  def handle_info(:front_frame, state) do
    if Fronts.showing?(state) do
      Process.send_after(self(), :front_frame, Fronts.frame_ms())
      {:noreply, state |> Fronts.tick(now()) |> show_front()}
    else
      {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp key(code, %{screen: :title} = state), do: title_key(code, state)

  defp key(code, %{screen: :lobby, chatting: text} = state) when text != nil,
    do: chat_key(code, state)

  defp key(code, %{screen: :lobby} = state), do: lobby_key(code, state)
  defp key(code, %{screen: :settings} = state), do: settings_key(code, state)
  defp key(code, %{screen: :summary} = state), do: summary_key(code, state)

  defp key(code, %{screen: screen} = state) when screen in [:guide, :page],
    do: reader_key(code, state)

  defp key(_code, state), do: state

  defp title_key(@enter, state), do: play(state)

  defp title_key(code, state) do
    case client_action(state, code, @title_actions) do
      :settings_menu -> to_settings(state, :title)
      :guide -> to_guide(state, :title)
      leave when leave in [:back, :title] -> quit(state)
      nil -> page_key(code, state)
    end
  end

  defp lobby_key(@down, state), do: select(state, 1)
  defp lobby_key(@up, state), do: select(state, -1)
  defp lobby_key(@page_down, state), do: select(state, Screens.window())
  defp lobby_key(@page_up, state), do: select(state, -Screens.window())
  defp lobby_key(@home, state), do: select(state, -state.selected)
  defp lobby_key(@end_key, state), do: select(state, length(state.worlds) - 1 - state.selected)
  defp lobby_key(@enter, state), do: join_selected(state, team_props(state))

  defp lobby_key(code, state) do
    case client_action(state, code, @lobby_actions) do
      :watch -> join_selected(state, %{spectate: true})
      :team -> cycle_team(state)
      :settings_menu -> to_settings(state, :lobby)
      :guide -> to_guide(state, :lobby)
      :chat when state.chat? -> draw(%{state | chatting: ""})
      :chat -> state
      leave when leave in [:back, :title] -> lobby_back(state)
      nil -> state
    end
  end

  defp chat_key(@enter, state) do
    said = state.chatting |> String.trim() |> String.slice(0, @said_most)
    if said != "", do: Chat.say(:lobby, Game.player_label(state.game, state.username), said)
    draw(%{state | chatting: nil})
  end

  defp chat_key(@escape, state), do: draw(%{state | chatting: nil})
  defp chat_key(8, state), do: draw(%{state | chatting: String.slice(state.chatting, 0..-2//1)})
  defp chat_key(_code, state), do: state

  defp redrawn_lobby(%{screen: :lobby} = state), do: draw(state)
  defp redrawn_lobby(state), do: state

  defp lobby_chat(%{chat?: true, chat: []} = state) do
    Chat.join(:lobby)
    %{state | chat: Enum.take(Chat.history(:lobby), -@chat_kept)}
  end

  defp lobby_chat(state), do: state

  defp lobby_back(state),
    do: if(Start.lobby_backs_to_title?(state.flow), do: to_title(state), else: quit(state))

  defp client_action(state, code, order),
    do: ClientKeys.action(state.keys, Keys.input_key(code), order)

  defp settings_key(code, state) do
    case code do
      @down -> draw(%{state | setting: rem(state.setting + 1, length(@settings))})
      @up -> draw(%{state | setting: Integer.mod(state.setting - 1, length(@settings))})
      @right -> step_setting(state, state.setting, 1)
      @left -> step_setting(state, state.setting, -1)
      @enter -> step_setting(state, state.setting, 1)
      @escape -> back(state)
      _other -> state
    end
  end

  defp summary_key(code, state) do
    case code do
      @enter -> after_summary(state)
      @escape -> to_lobby(state)
      ?Q -> to_title(state)
      _other -> state
    end
  end

  defp reader_key(code, state) do
    case code do
      @down -> draw(%{state | guide_offset: state.guide_offset + 1})
      @up -> draw(%{state | guide_offset: max(0, state.guide_offset - 1)})
      @page_down -> draw(%{state | guide_offset: state.guide_offset + 10})
      @page_up -> draw(%{state | guide_offset: max(0, state.guide_offset - 10)})
      @home -> draw(%{state | guide_offset: 0})
      @escape -> back(state)
      ?Q -> back(state)
      _other -> state
    end
  end

  defp page_key(code, state) do
    case Enum.find(state.pages, &(Keys.code(&1.key) == code)) do
      nil -> state
      page -> draw(%{state | screen: :page, page: page.key, guide_offset: 0, from: :title})
    end
  end

  defp front_key(code, state) do
    if Fronts.showing?(state) do
      case Keys.input_key(code) do
        nil -> state
        name -> front_event({:key, name, []}, state)
      end
    else
      state
    end
  end

  defp front_pad(button, state) do
    case {Fronts.showing?(state), Menus.pad_key(button)} do
      {true, key} when key != nil -> front_event({:key, key, [:pad]}, state)
      _other -> state
    end
  end

  defp front_event(event, state) do
    if Menus.input?(event) do
      {state, reply} = Fronts.event(state, event, state.settings)
      state = take_settings(state, reply.settings)
      go(Map.get(reply, :go), state)
    else
      state
    end
  end

  defp take_settings(%{settings: settings} = state, settings), do: state

  defp take_settings(state, settings) do
    state = %{state | settings: settings} |> save_settings() |> apply_settings()
    state
  end

  defp go(nil, state), do: show_front(state)
  defp go(:play, state), do: play(state)
  defp go({:play, id}, state), do: enter(state, id)
  defp go(:again, state), do: after_summary(state)
  defp go(:lobby, state), do: to_lobby(state)
  defp go(:title, state), do: to_title(state)
  defp go(:settings, state), do: to_settings(state, state.screen)
  defp go(:guide, state), do: to_guide(state, state.screen)
  defp go(:quit, state), do: quit(state)
  defp go(:back, %{screen: :title} = state), do: quit(state)
  defp go(:back, state), do: to_lobby(state)

  defp went(:lobby, state), do: to_lobby(state)
  defp went(:settings, state), do: to_settings(state, :play)
  defp went(:title, state), do: to_title(state)

  defp action(:play, state), do: play(state)
  defp action(:settings, state), do: to_settings(state, state.screen)
  defp action(:guide, state), do: to_guide(state, state.screen)
  defp action(:quit, state), do: quit(state)

  defp action({:page, key}, state),
    do: draw(%{state | screen: :page, page: key, guide_offset: 0, from: :title})

  defp action({:row, index}, %{selected: index} = state),
    do: join_selected(state, team_props(state))

  defp action({:row, index}, state), do: draw(%{state | selected: index})
  defp action(:team, state), do: cycle_team(state)
  defp action({:setting, index}, state), do: draw(%{state | setting: index})
  defp action({:step, index, delta}, state), do: step_setting(state, index, delta)
  defp action(:again, state), do: after_summary(state)
  defp action(_other, state), do: state

  defp quit(state) do
    send(self(), wx(event: wxClose()))
    state
  end

  defp play(%{flow: {:play, id, _opts}} = state), do: enter(state, id)
  defp play(state), do: to_lobby(state)

  defp enter(state, id) do
    worlds = worlds(state)
    world = if id == :first, do: List.first(worlds), else: Enum.find(worlds, &(&1.id == id))

    case world do
      nil ->
        to_lobby(state)

      world ->
        join(
          %{state | worlds: worlds, selected: Enum.find_index(worlds, &(&1 == world))},
          world,
          %{}
        )
    end
  end

  defp worlds(state), do: state.game.worlds(state.props)

  defp to_title(state) do
    state
    |> leave_world()
    |> Map.merge(%{screen: :title, status: ""})
    |> opened_front()
  end

  defp to_lobby(%{flow: {:play, _id, _opts}} = state), do: to_title(state)

  defp to_lobby(state),
    do:
      state
      |> leave_world()
      |> Map.merge(%{screen: :lobby, front: nil})
      |> Map.put(:worlds, worlds(state))
      |> lobby_chat()
      |> show_text()
      |> draw()

  defp to_settings(state, from),
    do: %{state | screen: :settings, from: from, setting: 0, front: nil} |> show_text() |> draw()

  defp to_guide(state, from),
    do:
      %{state | screen: :guide, from: from, guide_offset: 0, front: nil} |> show_text() |> draw()

  defp back(%{from: :play} = state), do: show_play(state)
  defp back(%{from: :lobby} = state), do: to_lobby(state)
  defp back(state), do: to_title(state)

  defp opened_front(state) do
    {state, start?} = Fronts.open(state, front_context(state), now())

    if Fronts.showing?(state) do
      if start?, do: Process.send_after(self(), :front_frame, Fronts.frame_ms())
      state |> show_view() |> show_front()
    else
      state |> show_text() |> draw()
    end
  end

  defp front_context(state) do
    %{
      settings: state.settings,
      username: state.username,
      worlds: worlds(state),
      outcome: state.summary,
      view: state.last_view
    }
  end

  defp show_front(state) do
    if Fronts.showing?(state) do
      atlas = state.game.atlas()
      look = Cauldron.Client.View.given(Look.of(state.game), nil, 0, state.settings.options)
      view = Draw.new(Draw.props(state.game, Fronts.scene(state), look, Look.zoom(state.game)))
      pane = View.pane(state.play, Atlas.fetch(atlas).tile)

      case Draw.picture(view, pane) do
        nil -> :ok
        raster -> View.show(state.play, raster)
      end
    end

    state
  end

  defp select(state, delta) do
    count = max(1, length(state.worlds))

    selected =
      if abs(delta) > 1,
        do: state.selected |> Kernel.+(delta) |> max(0) |> min(count - 1),
        else: Integer.mod(state.selected + delta, count)

    draw(%{state | selected: selected})
  end

  defp team_props(%{team: nil}), do: %{}
  defp team_props(%{team: team}), do: %{team: team}

  defp cycle_team(state) do
    teams = state.worlds |> Enum.at(state.selected, %{}) |> Map.get(:teams, [])
    choices = [nil | teams]
    index = Enum.find_index(choices, &(&1 == state.team)) || 0
    draw(%{state | team: Enum.at(choices, rem(index + 1, length(choices)))})
  end

  defp join_selected(state, extra) do
    case Enum.at(state.worlds, state.selected) do
      nil -> state
      world -> join(state, world, extra)
    end
  end

  defp join(state, world, extra) do
    {kind, opts} = state.link.(world)

    props =
      Keyword.get(opts, :props, %{})
      |> Map.merge(
        Game.optional(
          state.game,
          :join_props,
          [%{username: state.username, settings: state.settings}],
          %{}
        )
      )
      |> Map.merge(extra)
      |> Map.put(:settings, state.settings)

    params =
      Keyword.get(opts, :params, %{})
      |> Map.merge(Map.new(extra, fn {key, value} -> {Atom.to_string(key), value} end))
      |> saved_param(state.settings)
      |> Map.put("preset", to_string(state.settings.preset))

    link =
      {kind,
       opts
       |> Keyword.put(:props, props)
       |> Keyword.put(:params, params)
       |> with_atlas(kind, state.game)
       |> named(kind, state.username)}

    state = %{state | front: nil, summary: nil, last_view: nil}

    :ok =
      View.join(state.play, link,
        opening: Game.optional(state.game, :opening, [world], []),
        watching: Map.get(extra, :spectate, false) == true
      )

    View.levels(state.play, state.settings.sfx, state.settings.music)
    View.configure(state.play, Map.take(state.settings, [:pointer, :fps]))
    %{state | chosen: world, status: ""} |> show_play()
  end

  defp with_atlas(opts, :socket, game), do: Keyword.put_new(opts, :atlas, game.atlas())
  defp with_atlas(opts, :local, _game), do: opts

  defp named(opts, :socket, username),
    do:
      Keyword.update(
        opts,
        :connect,
        %{"username" => username},
        &Map.put_new(&1, "username", username)
      )

  defp named(opts, :local, _username), do: opts

  defp saved_param(params, %{saved: saved}) when is_binary(saved),
    do: Map.put(params, "saved", saved)

  defp saved_param(params, _settings), do: params

  defp show_play(state) do
    state = show_view(state)
    %{state | screen: :play}
  end

  defp show_view(state) do
    :wxWindow.hide(Text.window(state.text))
    :wxWindow.show(View.window(state.play))
    :wxSizer.layout(state.sizer)
    View.focus(state.play)
    state
  end

  defp show_text(state) do
    :wxWindow.hide(View.window(state.play))
    :wxWindow.show(Text.window(state.text))
    :wxSizer.layout(state.sizer)
    Text.focus(state.text)
    state
  end

  defp leave_world(%{screen: screen} = state)
       when screen in [:play, :summary] or
              (screen == :settings and :erlang.map_get(:from, state) == :play) do
    View.leave(state.play)
    state
  end

  defp leave_world(state), do: state

  defp to_summary(state, %{outcome: outcome, view: view}) do
    View.leave(state.play)
    state = %{state | screen: :summary, summary: outcome, last_view: view}
    {state, start?} = Fronts.open(state, front_context(state), now())

    if Fronts.showing?(state) do
      if start?, do: Process.send_after(self(), :front_frame, Fronts.frame_ms())
      show_front(state)
    else
      state |> show_text() |> draw()
    end
  end

  defp after_summary(%{summary: %{next: :same_world}, chosen: world} = state) when world != nil,
    do: join(%{state | screen: :lobby}, world, team_props(state))

  defp after_summary(%{summary: %{next: :next_world}, chosen: world} = state) when world != nil do
    worlds = worlds(state)

    case Enum.find_index(worlds, &(&1.id == world.id)) do
      nil ->
        to_lobby(state)

      index ->
        join(
          %{state | screen: :lobby, worlds: worlds},
          Enum.at(worlds, rem(index + 1, length(worlds))),
          team_props(state)
        )
    end
  end

  defp after_summary(state), do: to_lobby(state)

  defp step_setting(state, index, delta) do
    settings =
      case Enum.at(@settings, index) do
        :preset -> %{state.settings | preset: next_preset(state, delta)}
        :sfx -> %{state.settings | sfx: clamp(state.settings.sfx + delta * @step)}
        :music -> %{state.settings | music: clamp(state.settings.music + delta * @step)}
        :pointer -> %{state.settings | pointer: not state.settings.pointer}
        :fps -> Map.put(state.settings, :fps, next_rate(state, delta))
      end

    state = %{state | settings: settings, setting: index} |> save_settings() |> apply_settings()
    draw(state)
  end

  defp next_rate(state, delta) do
    rates = Game.frame_rates(state.game)
    index = Enum.find_index(rates, &(&1 == Map.get(state.settings, :fps, :auto))) || 0
    Enum.at(rates, Integer.mod(index + delta, length(rates)))
  end

  defp next_preset(state, delta) do
    presets = state.game.keymaps() |> Enum.map(&elem(&1, 0))
    index = Enum.find_index(presets, &(&1 == state.settings.preset)) || 0
    Enum.at(presets, Integer.mod(index + delta, length(presets)))
  end

  defp clamp(value), do: value |> max(0.0) |> min(1.0) |> Float.round(2)

  defp apply_settings(state) do
    View.levels(state.play, state.settings.sfx, state.settings.music)
    View.configure(state.play, Map.take(state.settings, [:preset, :pointer, :fps]))
    state
  end

  defp now, do: System.monotonic_time(:millisecond)

  defp closing(state) do
    state = leave_world(state)
    :wx_object.stop(state.text)
    :wx_object.stop(state.play)
    :wxFrame.destroy(state.frame)
    for from <- state.waiting, do: :wx_object.reply(from, :ok)
    %{state | waiting: []}
  end

  @impl :wx_object
  def terminate(_reason, state) do
    for from <- state.waiting, do: :wx_object.reply(from, :ok)
    :ok
  end
end
