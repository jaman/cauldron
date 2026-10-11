defmodule Cauldron2D.Wx.Client do
  @moduledoc """
  The window that puts a game's worlds in front of one player: a title, a lobby of
  worlds, settings, the world, a summary, the guide and the game's own pages, from a
  `Cauldron2D.Client.Game` — the desktop's twin of the terminal's
  `Cauldron2D.Drafter.Client`.

      Cauldron2D.Wx.Client.run(game: MyGame.Client, username: "alice")

  The world is a `Cauldron2D.Wx.View` joined through a link the `:link` function gives
  for the chosen world: without one, a local link to the world's process — a name on this
  node, or `{module, opts}` for a world of the player's own, started for them and
  stopped when they leave. Settings — the key preset, the effects and music levels,
  whether the pointer aims — are kept per player under
  `Cauldron2D.Paths.config(atlas, "<player>.desktop.settings")`.

  ## Keys

  Title: `Enter` play (into the lobby, or straight into the first world for a game
  whose `lobby?/0` is false), `s` settings, `h` guide, a page's key, `q` or `Esc` quit.
  Lobby: `↑`/`↓`, `PgUp`/`PgDn`, `Home`/`End`, `Enter` join, `w` watch, `t` team, `s`
  settings, `h` guide, `Esc` title. Settings: `↑`/`↓` choose, `←`/`→` change, `Esc`
  back. World: the game's keys, `p` pauses a world of the player's own, `Tab` settings
  with the world left where it is, `Esc` or `q` leaves. Summary: `Enter` again or on,
  as the outcome's `:next` says, `Esc` lobby. Guide and pages: `↑`/`↓`, `Esc` back.
  Every item on a screen can be clicked instead.

  ## Options

    * `:game` — the module. Required
    * `:username` — the player's name. Default `"player"`
    * `:props` — the props the game's `worlds/1`, `pages/1` and `sink/1` are given.
      Default `%{}`
    * `:link` — a function from a world to the link the view joins with, `{:local,
      opts}` or `{:socket, opts}`. Default: a local link to the world's process
    * `:size` — the window. Default `{1320, 800}`
    * `:scale` — pixels a sheet pixel in the world. Default `2`
    * `:backdrop` — drawn behind the screens, as `Cauldron2D.Wx.Text` takes it
  """

  @behaviour :wx_object

  alias Cauldron2D.Client.Game
  alias Cauldron2D.Paths
  alias Cauldron2D.Wx.Client.Screens
  alias Cauldron2D.Wx.{Const, Keys, Text, View}

  require Record

  Record.defrecordp(:wx, Record.extract(:wx, from_lib: "wx/include/wx.hrl"))
  Record.defrecordp(:wxClose, Record.extract(:wxClose, from_lib: "wx/include/wx.hrl"))

  @enter 13
  @escape 27
  @tab 9
  @left 314
  @up 315
  @right 316
  @down 317
  @page_up 366
  @page_down 367
  @home 313
  @end_key 312
  @step 0.05
  @settings [:preset, :sfx, :music, :pointer]

  @doc "Open the window and block until it is closed."
  @spec run(keyword()) :: :ok
  def run(opts) do
    wx = :wx.new()
    client = :wx_object.start_link(__MODULE__, {wx, opts}, [])
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
        keymap: keymap(game, settings),
        steering: Game.optional(game, :steering, [], []),
        size: {960, 640},
        scale: Keyword.get(opts, :scale, 2),
        hud: :right,
        hud_size: 300,
        zoom: true,
        pointer: settings.pointer,
        on_over: fn over -> send(me, {:play, :over, over}) end,
        on_closed: fn reason -> send(me, {:play, :closed, reason}) end,
        on_refused: fn reason -> send(me, {:play, :refused, reason}) end,
        on_key: fn code -> send(me, {:play, :key, code}) end
      )

    :wxSizer.add(sizer, Text.window(text), proportion: 1, flag: Const.expand())
    :wxSizer.add(sizer, View.window(world), proportion: 1, flag: Const.expand())
    :wxWindow.hide(View.window(world))
    :wxFrame.setSizer(frame, sizer)
    :wxFrame.connect(frame, :close_window)
    :wxFrame.show(frame)
    Text.focus(text)

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
           game: game, world: world.world, name: username, props: Map.drop(props, [:username])}
        end),
      lobby?: Game.optional(game, :lobby?, [], true),
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
      guide_offset: 0,
      page: nil,
      status: "",
      waiting: []
    }

    {frame, draw(state)}
  end

  defp load_settings(game, username) do
    defaults = %{
      preset: game.keymaps() |> Enum.map(&elem(&1, 0)) |> List.first(),
      sfx: 0.85,
      music: 0.35,
      pointer: true
    }

    case File.read(settings_path(game, username)) do
      {:ok, bytes} -> Map.merge(defaults, :erlang.binary_to_term(bytes, [:safe]))
      {:error, _} -> defaults
    end
  rescue
    ArgumentError -> %{preset: nil, sfx: 0.85, music: 0.35, pointer: true}
  end

  defp save_settings(state) do
    path = settings_path(state.game, state.username)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, :erlang.term_to_binary(state.settings))
    state
  end

  defp settings_path(game, username),
    do: Paths.config(game.atlas(), "#{username}.desktop.settings")

  defp keymap(game, settings) do
    game.keymaps()
    |> Enum.find_value(%{}, fn {name, map} -> if name == settings.preset, do: map end)
    |> Keys.wx_keymap()
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

  def handle_info({:cauldron_wx_text, :char, _char}, state), do: {:noreply, state}
  def handle_info({:play, :key, code}, state), do: {:noreply, play_key(code, state)}
  def handle_info({:play, :over, over}, state), do: {:noreply, to_summary(state, over)}

  def handle_info({:play, :refused, reason}, state),
    do:
      {:noreply,
       state
       |> Map.put(:status, "could not join: " <> Game.refusal_text(state.game, reason))
       |> to_lobby()}

  def handle_info({:play, :closed, _reason}, %{screen: :play} = state),
    do: {:noreply, to_lobby(state)}

  def handle_info(_message, state), do: {:noreply, state}

  defp key(code, %{screen: :title} = state), do: title_key(code, state)
  defp key(code, %{screen: :lobby} = state), do: lobby_key(code, state)
  defp key(code, %{screen: :settings} = state), do: settings_key(code, state)
  defp key(code, %{screen: :summary} = state), do: summary_key(code, state)

  defp key(code, %{screen: screen} = state) when screen in [:guide, :page],
    do: reader_key(code, state)

  defp key(_code, state), do: state

  defp title_key(code, state) do
    case code do
      @enter -> play(state)
      ?S -> to_settings(state, :title)
      ?H -> to_guide(state, :title)
      ?Q -> quit(state)
      @escape -> quit(state)
      _other -> page_key(code, state)
    end
  end

  defp lobby_key(@down, state), do: select(state, 1)
  defp lobby_key(@up, state), do: select(state, -1)
  defp lobby_key(@page_down, state), do: select(state, Screens.window())
  defp lobby_key(@page_up, state), do: select(state, -Screens.window())
  defp lobby_key(@home, state), do: select(state, -state.selected)
  defp lobby_key(@end_key, state), do: select(state, length(state.worlds) - 1 - state.selected)
  defp lobby_key(@enter, state), do: join_selected(state, team_props(state))
  defp lobby_key(?W, state), do: join_selected(state, %{spectate: true})
  defp lobby_key(?T, state), do: cycle_team(state)
  defp lobby_key(?S, state), do: to_settings(state, :lobby)
  defp lobby_key(?H, state), do: to_guide(state, :lobby)
  defp lobby_key(@escape, state), do: to_title(state)
  defp lobby_key(?Q, state), do: to_title(state)
  defp lobby_key(_code, state), do: state

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

  defp play_key(code, state) do
    case code do
      @escape -> to_lobby(state)
      ?Q -> to_lobby(state)
      @tab -> to_settings(state, :play)
      ?P -> pause(state)
      _other -> state
    end
  end

  defp pause(state) do
    View.pause(state.play)
    state
  end

  defp quit(state) do
    send(self(), wx(event: wxClose()))
    state
  end

  defp play(%{lobby?: false} = state) do
    case worlds(state) do
      [world | _] -> join(%{state | worlds: [world], selected: 0}, world, %{})
      [] -> to_lobby(state)
    end
  end

  defp play(state), do: to_lobby(state)

  defp worlds(state), do: state.game.worlds(state.props)

  defp to_title(state),
    do:
      state |> leave_world() |> Map.merge(%{screen: :title, status: ""}) |> show_text() |> draw()

  defp to_lobby(%{lobby?: false} = state), do: to_title(state)

  defp to_lobby(state),
    do:
      state
      |> leave_world()
      |> Map.put(:screen, :lobby)
      |> Map.put(:worlds, worlds(state))
      |> show_text()
      |> draw()

  defp to_settings(state, from), do: draw(%{state | screen: :settings, from: from, setting: 0})
  defp to_guide(state, from), do: draw(%{state | screen: :guide, from: from, guide_offset: 0})

  defp back(%{from: :play} = state), do: show_play(state)
  defp back(%{from: :lobby} = state), do: to_lobby(state)
  defp back(state), do: to_title(state)

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

    params =
      Keyword.get(opts, :params, %{})
      |> Map.merge(Map.new(extra, fn {key, value} -> {Atom.to_string(key), value} end))

    link = {kind, opts |> Keyword.put(:props, props) |> Keyword.put(:params, params)}
    :ok = View.join(state.play, link, opening: Game.optional(state.game, :opening, [world], []))
    View.levels(state.play, state.settings.sfx, state.settings.music)
    %{state | chosen: world, status: ""} |> show_play()
  end

  defp show_play(state) do
    :wxWindow.hide(Text.window(state.text))
    :wxWindow.show(View.window(state.play))
    :wxSizer.layout(state.sizer)
    View.focus(state.play)
    %{state | screen: :play}
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

  defp to_summary(state, over) do
    View.leave(state.play)
    state |> Map.merge(%{screen: :summary, summary: over}) |> show_text() |> draw()
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
      end

    state = %{state | settings: settings, setting: index} |> save_settings() |> apply_settings()
    draw(state)
  end

  defp next_preset(state, delta) do
    presets = state.game.keymaps() |> Enum.map(&elem(&1, 0))
    index = Enum.find_index(presets, &(&1 == state.settings.preset)) || 0
    Enum.at(presets, Integer.mod(index + delta, length(presets)))
  end

  defp clamp(value), do: value |> max(0.0) |> min(1.0) |> Float.round(2)

  defp apply_settings(state) do
    View.levels(state.play, state.settings.sfx, state.settings.music)
    View.pointer(state.play, state.settings.pointer)
    View.keymap(state.play, keymap(state.game, state.settings))
    state
  end

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
