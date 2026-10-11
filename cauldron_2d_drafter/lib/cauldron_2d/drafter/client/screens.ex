defmodule Cauldron2D.Drafter.Client.Screens do
  @moduledoc """
  The screens `Cauldron2D.Drafter.Client` draws, as functions from its state to drafter
  elements: `title/1`, `lobby/1`, `settings/1`, `guide/1`, `page/2`, `world/1` and
  `summary/1`.

  The title, the lobby and the settings show their keys; the world shows its key hints
  only when `help?` is set, as a block of lines at the bottom, and the frames a second
  the world sends only when `fps?` is set. Nothing on any screen
  takes focus except the lobby chat while it is being typed into.
  """

  import Drafter.App

  alias Cauldron2D.Client.{Game, Hud}
  alias Cauldron2D.Drafter.Client
  alias Cauldron2D.Drafter.Client.Settings
  alias Cauldron2D.Drafter.Surface

  @doc "The title screen: the game's name, its tagline and the menu."
  @spec title(map()) :: term()
  def title(%{game: game} = state) do
    info = game.title()

    vertical(
      [
        label(""),
        digits(info.name, align: :center),
        label(Map.get(info, :tagline, ""), align: :center),
        label(""),
        label("Enter  play", align: :center),
        label("#{key_text(state, :settings_menu)}  settings", align: :center),
        label("#{key_text(state, :guide)}  guide", align: :center),
        label("#{key_text(state, :title)}  quit", align: :center),
        label("", flex: 1)
      ] ++ page_hints(state),
      gap: 1
    )
  end

  defp page_hints(%{pages: [_ | _] = pages}) do
    buttons =
      for page <- pages,
          do:
            button("#{page.hint}  #{page.key}",
              id: :"page_#{page.key}",
              on_click: {:page, page.key},
              compact: true,
              width: String.length(page.hint) + 4
            )

    [horizontal([label("", flex: 1) | buttons], gap: 1)]
  end

  defp page_hints(_state), do: []

  defp key_text(state, action), do: state |> Map.get(:keys, %{}) |> Map.get(action) |> key_name()

  defp key_name(nil), do: ""
  defp key_name([key | _]), do: key_name(key)
  defp key_name(:escape), do: "Esc"
  defp key_name(:tab), do: "Tab"
  defp key_name(:enter), do: "Enter"
  defp key_name(key), do: Atom.to_string(key)

  @doc "A page the game added, by its key: its title, what it renders, and the way back."
  @spec page(map(), atom()) :: term()
  def page(%{pages: pages}, key) do
    page = Enum.find(pages, &(&1.key == key))

    vertical(
      [header(page.title), label("") | Enum.map(page.render.(), &run_label/1)] ++
        [label("", flex: 1), rule(), label("Esc or q  back", style: %{fg: :bright_black})],
      gap: 0
    )
  end

  @doc "The lobby: worlds to join, who is in the chosen one, the chat, and the keys."
  @spec lobby(map()) :: term()
  def lobby(%{game: game} = state) do
    worlds = Client.worlds(state)

    vertical(
      [
        header("#{game.title().name}  ·  #{self_label(state)}"),
        horizontal(
          [
            vertical(
              [
                columns_row(worlds),
                rule()
                | world_rows(worlds, state.lobby.selected) ++ team_row(worlds, state.lobby, state)
              ],
              flex: 1
            ),
            vertical(chosen_rows(worlds, state.lobby.selected, state), width: 30)
          ],
          flex: 1,
          gap: 2
        )
      ] ++ chat_box(state) ++ [label(lobby_hints(state), style: %{fg: :bright_black})]
    )
  end

  defp chat_box(%{chat?: false}), do: []

  defp chat_box(state) do
    [
      rule(),
      scrollable(chat_rows(state.lobby.messages), height: 5, focusable: false),
      text_input(
        id: :chat_input,
        bind: :chat_text,
        on_submit: :chat_submit,
        placeholder: "#{key_text(state, :chat)} to chat"
      )
    ]
  end

  defp lobby_hints(state) do
    [
      "Enter  join",
      hint(state, :watch, "watch"),
      hint(state, :team, "team"),
      hint(state, :settings_menu, "settings"),
      hint(state, :guide, "guide"),
      if(Map.get(state, :chat?, true), do: hint(state, :chat, "chat"), else: nil),
      hint(state, :title, "title"),
      "PgUp PgDn  page",
      "click  choose, again to join"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("     ")
  end

  defp hint(state, action, text) do
    case key_text(state, action) do
      "" -> nil
      key -> key <> "  " <> text
    end
  end

  @lobby_window 12
  @name_width 18
  @kind_width 18
  @flying_width 10
  @map_width 30
  @dim %{fg: :bright_black}

  @doc "How many worlds the lobby lists at once; the window slides to keep the selection in view."
  @spec lobby_window() :: pos_integer()
  def lobby_window, do: @lobby_window

  @world_rows_from 3

  @doc "The index of the world drawn on screen row `y` of the lobby, or `nil` for a row that is none."
  @spec world_at([map()], non_neg_integer(), non_neg_integer()) :: non_neg_integer() | nil
  def world_at([], _selected, _y), do: nil

  def world_at(worlds, selected, y) do
    {first, shown} = window(worlds, selected)
    top = @world_rows_from + if(first > 0, do: 1, else: 0)
    index = first + y - top
    if y >= top and index < first + shown, do: index, else: nil
  end

  defp window(worlds, selected) do
    count = length(worlds)
    first = selected |> Kernel.-(div(@lobby_window, 2)) |> min(count - @lobby_window) |> max(0)
    {first, min(@lobby_window, count - first)}
  end

  defp columns_row(worlds) do
    kind =
      if kinds?(worlds), do: [{String.pad_trailing("Kind", @kind_width), %{bold: true}}], else: []

    label(
      [{"  " <> String.pad_trailing("Worlds", @name_width), %{bold: true}}] ++
        kind ++
        [{String.pad_trailing("Players", @flying_width), %{bold: true}}, {"Map", %{bold: true}}]
    )
  end

  defp kinds?(worlds), do: Enum.any?(worlds, &Map.has_key?(&1, :kind))

  defp world_rows([], _selected), do: [label("no worlds are open", style: @dim)]

  defp world_rows(worlds, selected) do
    {first, shown} = window(worlds, selected)
    rows = worlds |> Enum.with_index() |> Enum.slice(first, shown)

    more(first, "▲") ++
      Enum.map(rows, &world_row(&1, selected, kinds?(worlds))) ++
      more(length(worlds) - first - shown, "▼")
  end

  defp world_row({world, index}, selected, kinds?) do
    chosen? = index == selected
    marker = if chosen?, do: "▶ ", else: "  "
    name_style = if chosen?, do: %{fg: :cyan, bold: true}, else: %{bold: true}
    {kind, kind_colour} = kind_of(world)
    players = Map.get(world, :players, 0)
    players_style = if players > 0, do: %{fg: {111, 227, 154}}, else: @dim

    label(
      [{marker <> fit(world.name, @name_width), name_style}] ++
        if(kinds?, do: [{fit(kind, @kind_width), %{fg: kind_colour}}], else: []) ++
        [
          {fit(players_text(players), @flying_width), players_style},
          {fit(Map.get(world, :map, ""), @map_width), if(chosen?, do: %{}, else: @dim)}
        ]
    )
  end

  defp fit(text, width), do: text |> String.slice(0, width - 1) |> String.pad_trailing(width)

  defp players_text(0), do: "nobody"
  defp players_text(1), do: "1 player"
  defp players_text(n), do: "#{n} players"

  defp kind_of(world) do
    case Map.get(world, :kind) do
      {text, {_, _, _} = colour} -> {text, colour}
      text when is_binary(text) -> {text, {200, 200, 210}}
      _none -> {"", @dim.fg}
    end
  end

  defp more(0, _arrow), do: []
  defp more(count, arrow), do: [label("  #{arrow} #{count} more", style: @dim)]

  defp team_row(worlds, %{selected: selected, team: team}, state) do
    case Enum.at(worlds, selected) do
      %{teams: [_ | _] = teams} ->
        [
          label(""),
          label([
            {"team: ", %{}},
            {to_string(team || "any"), %{fg: :cyan, bold: true}},
            {"   #{key_text(state, :team)} cycles through #{Enum.join(teams, ", ")}", @dim}
          ])
        ]

      _ ->
        []
    end
  end

  defp chosen_rows(worlds, selected, state) do
    case Enum.at(worlds, selected) do
      nil ->
        []

      world ->
        {kind, kind_colour} = kind_of(world)
        teams = Map.get(world, :teams, [])

        [
          label(world.name, style: %{fg: :cyan, bold: true}),
          rule(),
          label(Map.get(world, :map, "")),
          label(kind, style: %{fg: kind_colour}),
          label(Map.get(world, :note) || "", style: @dim),
          label(if(teams == [], do: "no teams", else: "teams " <> Enum.join(teams, ", ")),
            style: @dim
          ),
          label(""),
          label("Players", style: %{bold: true})
        ] ++
          player_rows(world, state) ++
          [
            label(""),
            label(
              Enum.join(
                ["Enter  join", hint(state, :watch, "watch")] |> Enum.reject(&is_nil/1),
                "     "
              ),
              style: @dim
            )
          ]
    end
  end

  defp player_rows(%{humans: humans}, %{game: game}) when is_list(humans) do
    case humans |> Enum.map(&player_label(game, &1)) |> Enum.sort() do
      [] -> [label("  nobody yet", style: @dim)]
      names -> Enum.map(names, &label("  #{&1}"))
    end
  end

  defp player_rows(world, _state) do
    case Map.get(world, :players, 0) do
      0 -> [label("  nobody yet", style: @dim)]
      1 -> [label("  1 player")]
      count -> [label("  #{count} players")]
    end
  end

  @doc """
  The player's own name as the header shows it: the username, and after it in
  parentheses how the game's `player_label/1` writes them when that differs.
  """
  @spec self_label(map()) :: String.t()
  def self_label(%{game: game, username: username}) do
    case player_label(game, username) do
      ^username -> username
      seen_as -> "#{username} (#{seen_as})"
    end
  end

  @doc "How the game writes the player `id`: its `player_label/1`, else the id as text."
  @spec player_label(module(), term()) :: String.t()
  def player_label(game, id) do
    if Code.ensure_loaded?(game) and function_exported?(game, :player_label, 1),
      do: game.player_label(id),
      else: plain_label(id)
  end

  defp plain_label(id) when is_binary(id), do: id
  defp plain_label(id) when is_atom(id), do: Atom.to_string(id)
  defp plain_label(id), do: inspect(id)

  defp chat_rows(messages) do
    Enum.map(messages, fn %{from: from, text: text} -> label("#{from}: #{text}") end)
  end

  @doc "Settings: every item on its own row, the cursor on one of them, and the keys that move and change it."
  @spec settings(map()) :: term()
  def settings(%{game: game, settings: settings, selected: selected, rebinding: rebinding}) do
    rows =
      Enum.map(Settings.items(game), fn item ->
        item_row(item, item == selected, rebinding, settings, game)
      end)

    vertical(
      [header("Settings") | rows] ++
        [
          rule(),
          label(
            "↑ ↓  choose     ← →  change     Enter  add a key or mouse button     Backspace  remove the last     Esc  back (saves)",
            style: %{fg: :bright_black}
          )
        ],
      gap: 0
    )
  end

  defp item_row({:action, action}, _selected?, action, _settings, _game),
    do:
      label("▶   #{action}: press a key or mouse button to add…  (Esc cancels)",
        style: %{fg: :yellow, bold: true}
      )

  defp item_row(item, selected?, _rebinding, settings, game) do
    marker = if selected?, do: "▶ ", else: "  "
    style = if selected?, do: %{fg: :cyan, bold: true}, else: %{}
    label(marker <> item_text(item, settings, game), style: style)
  end

  defp item_text(:preset, settings, game),
    do: "Controls   " <> preset_text(Settings.presets(game), settings.preset)

  defp item_text({:action, action}, settings, _game),
    do: "  #{action}: #{Settings.keys_text(settings, action)}"

  defp item_text(:pointer, settings, _game),
    do: "Pointer steering   #{if settings.pointer, do: "on", else: "off"}"

  defp item_text(:sfx, settings, _game), do: "Effects   " <> bar(settings.sfx)
  defp item_text(:music, settings, _game), do: "Music     " <> bar(settings.music)

  defp item_text(:display, %{display: :auto}, _game),
    do: "Display   pixels where the terminal has them, else glyphs"

  defp item_text(:display, %{display: display}, _game),
    do: "Display   " <> Atom.to_string(display)

  defp item_text(:fps, %{fps: :auto}, _game), do: "Frame rate   auto (the terminal's best)"

  defp item_text(:fps, %{fps: fps}, _game),
    do: "Frame rate   " <> Integer.to_string(fps) <> " fps"

  defp preset_text(presets, current) do
    Enum.map_join(presets, "   ", fn preset ->
      if preset == current, do: "[#{preset}]", else: " #{preset} "
    end)
  end

  defp bar(level) do
    filled = round(level * 10)

    String.duplicate("█", filled) <>
      String.duplicate("░", 10 - filled) <> " #{round(level * 100)}%"
  end

  @doc """
  The game's guide: the entries of `guide/0` one a row, each art drawn on a surface down
  the left beside its name and text, from `state.guide.offset` for `state.guide.rows`
  rows.
  """
  @spec guide(map()) :: term()
  def guide(%{game: game, settings: settings, guide: %{offset: offset, rows: rows}}) do
    lines = guide_rows(game)
    window = Enum.slice(lines, offset, rows)

    movers =
      for {{:entry, %{art: art}}, index} <- Enum.with_index(window),
          do: {art, {0.5, offset + index}}

    surface =
      {:cauldron_surface,
       [
         id: :guide_art,
         atlas: game.atlas(),
         focus: {1.0, offset + rows / 2},
         cell: fn _ -> :void end,
         movers: movers,
         mode: Settings.surface_mode(settings),
         on_geometry: :guide_geometry,
         width: 4
       ]}

    vertical([
      header("Guide  ·  #{game.title().name}"),
      horizontal(
        [surface, vertical(Enum.map(window, &guide_line/1) ++ [label("", flex: 1)], flex: 1)],
        flex: 1,
        gap: 1
      ),
      label("↑ ↓  scroll     PgUp PgDn  page     Home End  ends     Esc  back",
        style: %{fg: :bright_black}
      )
    ])
  end

  @doc "How many rows the game's guide runs to, headings and gaps included."
  @spec guide_length(module()) :: non_neg_integer()
  def guide_length(game), do: game |> guide_rows() |> length()

  defp guide_rows(game) do
    game.guide()
    |> Enum.map(fn {heading, entries} ->
      [{:heading, heading} | Enum.map(entries, &{:entry, &1})]
    end)
    |> Enum.intersperse([:blank])
    |> List.flatten()
  end

  defp guide_line({:heading, text}), do: label(text, style: %{bold: true})

  defp guide_line({:entry, %{name: name, text: text}}),
    do: label([{String.pad_trailing(name, 20), %{bold: true}}, {text, %{}}])

  defp guide_line(:blank), do: label("")

  @doc "The summary the game gave when play ended for this player, and the way back."
  @spec summary(map()) :: term()
  def summary(%{summary: %{title: title, lines: lines}} = state) do
    vertical(
      [label(""), label(title, align: :center, style: %{bold: true}), label("")] ++
        Enum.map(lines, &label(&1, align: :center)) ++
        [label(""), label(summary_keys(state), align: :center, style: %{fg: :bright_black})],
      gap: 0
    )
  end

  defp summary_keys(%{summary: %{next: :same_world}} = state) do
    "Enter  " <>
      Client.next_world(state).name <> " again     Esc  lobby     q  title"
  end

  defp summary_keys(%{summary: %{next: :next_world}} = state) do
    case Client.next_world(state) do
      nil -> "Enter  lobby     q  title"
      world -> "Enter  next: " <> world.name <> "     Esc  lobby     q  title"
    end
  end

  defp summary_keys(_state), do: "Enter  lobby     q  title"

  @doc "The world: the world with the game's hud beside or under it, and the hints when asked."
  @spec play(map()) :: term()
  def play(%{view: nil, game: game, joined: world}) do
    vertical(
      [label("", flex: 1)] ++
        Enum.map(Game.optional(game, :opening, [world], []), &run_label(&1, align: :center)) ++
        [label("", flex: 1)]
    )
  end

  def play(%{game: game, view: view, settings: settings} = state) do
    scene = Client.scene(state)
    look = Client.look(state)

    surface =
      {:cauldron_surface,
       [
         id: :play,
         atlas: game.atlas(),
         focus: Client.focus(state, scene),
         zoom: Map.get(state, :zoom, 1),
         cell: scene.cell,
         movers: scene.movers,
         labels: Map.get(scene, :labels, []),
         volumes: Map.get(scene, :volumes, []),
         layers: Map.get(scene, :layers, []),
         mode: Settings.surface_mode(settings),
         projection: look.projection,
         facing: look.facing,
         facings: Map.get(look, :facings, 4),
         tilt: look.tilt,
         heading: Map.get(scene, :heading) || look.heading,
         pitch: look.pitch,
         density: Map.get(look, :density),
         eye: Client.eye_height(game, scene),
         picture: Map.get(scene, :picture),
         native: Map.get(scene, :native),
         native_scale: Map.get(scene, :native_scale, :fit),
         picture_format: Map.get(scene, :picture_format, :rgba),
         swap: Map.get(scene, :swap, false),
         on_geometry: :play_geometry,
         image_throttle: {1, :tick},
         image_priority: :normal,
         flex: 1
       ]}

    vertical(
      hud_layout(Hud.layout(game.hud(view)), surface) ++
        paused_row(state) ++
        talk_rows(state) ++
        fps_row(state) ++ zoom_row(state) ++ help(state, play_hints(game, state))
    )
  end

  defp paused_row(state) do
    if Client.paused?(state),
      do: [label("paused  ·  p resumes", style: %{fg: :yellow}, align: :center)],
      else: []
  end

  @doc "A row of runs as one label, with any label options."
  @spec run_label(Hud.row(), keyword()) :: term()
  def run_label(row, opts \\ []) do
    label(for({text, style} <- Hud.runs(row), do: {text, run_style(style)}), opts)
  end

  defp run_style(style) do
    case Map.get(style, :fg) do
      nil -> Map.delete(style, :fg)
      name when is_atom(name) -> style
      {r, g, b} -> %{style | fg: {r, g, b}}
    end
  end

  defp fps_row(%{fps?: true, fps: %{shown: shown}}),
    do: [label("#{shown || "…"} frames/s from the world", style: %{fg: :bright_black})]

  defp fps_row(_state), do: []

  defp zoom_row(state) do
    case Enum.reject(
           [
             look_note(Client.look(state)),
             drawing_note(state),
             zoom_note(Map.get(state, :zoom, 1)),
             pan_note(Map.get(state, :pan, {0.0, 0.0}))
           ],
           &is_nil/1
         ) do
      [] ->
        []

      notes ->
        [
          label(Enum.join(notes, "  ·  ") <> "  ·  #{key_text(state, :zoom_reset)} back",
            style: %{fg: :bright_black}
          )
        ]
    end
  end

  defp look_note(%{projection: projection}) when projection in [:top, :picture], do: nil

  defp look_note(%{projection: :iso, facing: facing, tilt: tilt} = look) do
    turn = iso_turn(facing, Map.get(look, :facings, 4))
    "isometric  ·  #{turn}  ·  tilt #{round(:math.atan(tilt / 2) * 180 / :math.pi())}°"
  end

  defp look_note(%{projection: :oblique}), do: "oblique"

  defp look_note(%{projection: :mode7} = look) do
    heading = Integer.mod(round(look.heading * 180 / :math.pi()), 360)
    "mode 7  ·  heading #{heading}°  ·  pitch #{Float.round(look.pitch / 1, 2)}"
  end

  defp look_note(%{projection: :first_person} = look) do
    heading = Integer.mod(round(look.heading * 180 / :math.pi()), 360)
    mouse = if look.mouse_look?, do: "  ·  mouse look", else: ""
    "first person  ·  heading #{heading}°  ·  pitch #{Float.round(look.pitch / 1, 2)}#{mouse}"
  end

  defp iso_turn(facing, 4), do: "facing #{facing}"
  defp iso_turn(facing, facings), do: "facing #{round(facing * 360 / facings)}°"

  defp drawing_note(%{settings: %{display: :auto}} = state) do
    if Client.look(state).projection in [:top, :picture],
      do: nil,
      else: picture_note(Surface.protocol(%Surface{mode: nil}))
  end

  defp drawing_note(%{settings: %{display: :glyphs}}), do: "glyphs"
  defp drawing_note(%{settings: %{display: set}}), do: "#{set} cells"
  defp drawing_note(_state), do: nil

  defp picture_note(nil), do: "glyphs"
  defp picture_note(protocol), do: "picture (#{protocol})"

  defp zoom_note(1), do: nil
  defp zoom_note(zoom), do: "zoom " <> zoom_text(zoom)

  defp pan_note({px, py}) when px == 0 and py == 0, do: nil
  defp pan_note(_pan), do: "panned"

  @doc "A zoom as text: `2×`, `1/2×`."
  @spec zoom_text(number()) :: String.t()
  def zoom_text(zoom) when zoom >= 1, do: "#{round(zoom)}×"
  def zoom_text(zoom), do: "1/#{round(1 / zoom)}×"

  defp hud_layout(%{left: [], bottom: rows}, surface), do: [surface | hud_rows(rows)]

  defp hud_layout(%{left: column, width: width, bottom: rows}, surface) do
    [
      horizontal([vertical(hud_rows(column), width: width, gap: 0), surface], gap: 1, flex: 1)
      | hud_rows(rows)
    ]
  end

  defp hud_rows(rows), do: Enum.map(rows, &run_label/1)

  defp talk_rows(%{talking?: true} = state) do
    said_rows(state) ++
      [
        horizontal(
          [
            label("say:", style: %{fg: :yellow}),
            text_input(id: :talk_input, bind: :talk_text, on_submit: :talk_submit, flex: 1)
          ],
          gap: 1
        )
      ]
  end

  defp talk_rows(%{chat?: false}), do: []
  defp talk_rows(state), do: said_rows(state)

  defp said_rows(%{talk: talk}) do
    talk
    |> Enum.take(-2)
    |> Enum.map(fn %{from: from, text: text} ->
      label(from <> ": " <> text, style: %{fg: :yellow})
    end)
  end

  defp play_hints(game, %{settings: settings} = state) do
    keys =
      Enum.map_join(game.actions(), "     ", fn action ->
        "#{Settings.keys_text(settings, action)}  #{action}"
      end)

    chrome = [
      hint(state, :hints, "hints"),
      if(Map.get(state, :chat?, true), do: hint(state, :talk, "talk"), else: nil),
      hint(state, :fps, "frames/s"),
      hint(state, :settings, "settings"),
      hint(state, :back, "lobby"),
      hint(state, :title, "lobby"),
      "^Q  quit"
    ]

    view = [
      hint(state, :zoom_in, "zoom in"),
      hint(state, :zoom_out, "zoom out"),
      "wheel  zoom" <> if(Map.get(state, :watching?, false), do: " at the pointer", else: ""),
      hint(state, :zoom_reset, "back"),
      if(Map.get(state, :watching?, false), do: "arrows / drag  pan", else: nil)
    ]

    look = [
      hint(state, :projection, "view"),
      hint(state, :turn_left, "turn left"),
      hint(state, :turn_right, "turn right"),
      hint(state, :tilt_up, "tilt up"),
      hint(state, :tilt_down, "tilt down"),
      hint(state, :display, "picture / cells"),
      hint(state, :glyphs, "glyph set"),
      hint(state, :mouse_look, "mouse look")
    ]

    [keys, joined(chrome), joined(view), joined(look ++ look_hints(state))]
  end

  defp look_hints(state) do
    for {:look, key} = action <- Map.keys(Map.get(state, :keys, %{})),
        do: hint(state, action, key |> Atom.to_string() |> String.trim_trailing("?"))
  end

  defp joined(hints), do: hints |> Enum.reject(&is_nil/1) |> Enum.join("     ")

  defp help(%{help?: true}, lines),
    do: [rule() | Enum.map(lines, &label(&1, style: %{fg: :bright_black}))]

  defp help(_state, _lines), do: []
end
