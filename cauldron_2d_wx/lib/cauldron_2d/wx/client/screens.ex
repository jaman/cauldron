defmodule Cauldron2D.Wx.Client.Screens do
  @moduledoc """
  What `Cauldron2D.Wx.Client`'s screens look like, as items `Cauldron2D.Wx.Text` draws:
  the title, the lobby, the settings, the summary, the guide and a game's own pages,
  from the client's state. Pure: nothing here touches wx.

      Cauldron2D.Wx.Client.Screens.draw(state, {width, height})

  An item is `{x, y, text, colour, size, action}`; `action` is what a click on it does,
  as the client reads it, or `nil`.
  """

  alias Cauldron2D.Client.{Game, Hud}

  @type item ::
          {integer() | {:centre, integer()}, integer(), String.t(), {byte(), byte(), byte()},
           :small | :normal | :big | :title, term()}

  @ink {228, 231, 243}
  @dim {150, 156, 178}
  @accent {127, 214, 255}
  @warm {255, 208, 96}
  @margin 60
  @line 30
  @window 12

  @doc "The items for the screen the state is on."
  @spec draw(map(), {pos_integer(), pos_integer()}) :: [item()]
  def draw(state, size) do
    screen(state, size) ++ status(state, size)
  end

  @doc "How many arenas the lobby lists at once."
  @spec window() :: pos_integer()
  def window, do: @window

  defp screen(%{screen: :title} = state, size), do: title(state, size)
  defp screen(%{screen: :lobby} = state, size), do: lobby(state, size)
  defp screen(%{screen: :settings} = state, size), do: settings(state, size)
  defp screen(%{screen: :summary} = state, size), do: summary(state, size)
  defp screen(%{screen: :guide} = state, size), do: guide(state, size)
  defp screen(%{screen: :page} = state, size), do: page(state, size)
  defp screen(_state, _size), do: []

  defp status(%{status: ""}, _size), do: []

  defp status(%{status: status}, {_width, height}),
    do: [{@margin, height - @line - 10, status, @warm, :normal, nil}]

  defp title(state, {width, height}) do
    title = state.game.title()
    centre = div(width, 2)

    [
      {{:centre, centre}, div(height, 4), title.name, @accent, :title, :play},
      {{:centre, centre}, div(height, 4) + 70, Map.get(title, :tagline, ""), @dim, :normal, nil},
      {{:centre, centre}, div(height, 2), "Enter  play  ·  as #{state.username}", @ink, :big,
       :play},
      {{:centre, centre}, div(height, 2) + 50, "s  settings", @ink, :normal, :settings},
      {{:centre, centre}, div(height, 2) + 80, "h  guide", @ink, :normal, :guide},
      {{:centre, centre}, div(height, 2) + 110, "q  quit", @ink, :normal, :quit}
    ] ++
      for {page, index} <- Enum.with_index(state.pages) do
        {{:centre, centre}, div(height, 2) + 150 + index * @line, "#{page.key}  #{page.hint}",
         @dim, :normal, {:page, page.key}}
      end
  end

  defp lobby(state, {_width, _height}) do
    first =
      state.selected
      |> Kernel.-(div(@window, 2))
      |> max(0)
      |> min(max(length(state.arenas) - @window, 0))

    shown = state.arenas |> Enum.drop(first) |> Enum.take(@window)
    chosen = Enum.at(state.arenas, state.selected)

    header = [
      {@margin, 40, "Arenas  ·  #{state.username}", @accent, :big, nil},
      {@margin, 90, "↑↓ choose   Enter join   w watch   t team   s settings   h guide   Esc back",
       @dim, :small, nil}
    ]

    rows =
      for {arena, offset} <- Enum.with_index(shown), index = first + offset do
        marker = if index == state.selected, do: "▶ ", else: "  "
        colour = if index == state.selected, do: @ink, else: @dim

        {@margin, 130 + offset * @line, marker <> arena_line(arena), colour, :normal,
         {:row, index}}
      end

    header ++ rows ++ chosen_lines(state, chosen, 130 + @window * @line + 20)
  end

  defp arena_line(arena) do
    kind =
      case Map.get(arena, :kind) do
        {text, _rgb} -> "  ·  #{text}"
        text when is_binary(text) -> "  ·  #{text}"
        _none -> ""
      end

    map = if Map.get(arena, :map), do: "  ·  #{arena.map}", else: ""
    "#{arena.name}#{kind}  ·  #{Map.get(arena, :players, 0)} playing#{map}"
  end

  defp chosen_lines(_state, nil, _y), do: []

  defp chosen_lines(state, arena, y) do
    note = if Map.get(arena, :note), do: [{@margin, y, arena.note, @dim, :normal, nil}], else: []
    teams = Map.get(arena, :teams, [])

    team =
      if teams == [] do
        []
      else
        chosen = if state.team, do: "team #{state.team}", else: "any team"

        [
          {@margin, y + @line, "t  #{chosen}  (#{Enum.map_join(teams, ", ", &to_string/1)})",
           @ink, :normal, :team}
        ]
      end

    note ++ team
  end

  @settings [:preset, :sfx, :music, :pointer]

  defp settings(state, {_width, _height}) do
    presets = state.game.keymaps() |> Enum.map(&elem(&1, 0))

    keymap =
      state.game.keymaps()
      |> Enum.find_value(%{}, fn {name, map} -> if name == state.settings.preset, do: map end)

    rows =
      for {key, index} <- Enum.with_index(@settings) do
        marker = if index == state.setting, do: "▶ ", else: "  "
        colour = if index == state.setting, do: @ink, else: @dim

        {@margin, 130 + index * @line, marker <> setting_text(key, state.settings, presets),
         colour, :normal, {:setting, index}}
      end

    arrows =
      for index <- 0..(length(@settings) - 1),
          do: {@margin + 420, 130 + index * @line, "◀  ▶", @accent, :normal, {:step, index, 1}}

    keys =
      for {{action, specs}, index} <- Enum.with_index(Enum.sort(keymap)) do
        {@margin, 130 + (length(@settings) + 1 + index) * @line,
         "#{String.pad_trailing(to_string(action), 16)} #{Enum.map_join(specs, ", ", &key_text/1)}",
         @dim, :small, nil}
      end

    [
      {@margin, 40, "Settings", @accent, :big, nil},
      {@margin, 90, "↑↓ choose   ←→ change   Esc back", @dim, :small, nil}
    ] ++ rows ++ arrows ++ keys
  end

  defp setting_text(:preset, settings, _presets), do: "keys          #{settings.preset}"
  defp setting_text(:sfx, settings, _presets), do: "effects       #{round(settings.sfx * 100)}%"

  defp setting_text(:music, settings, _presets),
    do: "music         #{round(settings.music * 100)}%"

  defp setting_text(:pointer, settings, _presets),
    do: "pointer aims  #{if settings.pointer, do: "yes", else: "no"}"

  defp key_text({:mouse, button}), do: "mouse #{button}"
  defp key_text({key, mods}), do: Enum.map_join(mods, "+", &to_string/1) <> "+" <> to_string(key)
  defp key_text(key), do: to_string(key)

  defp summary(%{summary: nil}, _size), do: []

  defp summary(%{summary: summary}, {width, height}) do
    centre = div(width, 2)

    [{{:centre, centre}, div(height, 4), summary.title, @accent, :title, nil}] ++
      Enum.with_index(summary.lines, fn line, index ->
        {{:centre, centre}, div(height, 4) + 80 + index * @line, line, @ink, :normal, nil}
      end) ++
      [{{:centre, centre}, height - 120, "Enter  again     Esc  lobby", @dim, :normal, :again}]
  end

  defp guide(state, {_width, height}) do
    entries =
      for {heading, items} <- Game.optional(state.game, :guide, [], []),
          entry <- [{:heading, heading} | items],
          do: entry

    rows = div(height - 160, @line)
    shown = entries |> Enum.drop(state.guide_offset) |> Enum.take(rows)

    [
      {@margin, 40, "Guide  ·  #{state.game.title().name}", @accent, :big, nil},
      {@margin, 90, "↑↓ scroll   Esc back", @dim, :small, nil}
    ] ++
      Enum.with_index(shown, fn
        {:heading, heading}, index ->
          {@margin, 130 + index * @line, heading, @accent, :normal, nil}

        entry, index ->
          {@margin, 130 + index * @line, "#{String.pad_trailing(entry.name, 20)} #{entry.text}",
           @ink, :normal, nil}
      end)
  end

  defp page(state, {_width, _height}) do
    case Enum.find(state.pages, &(&1.key == state.page)) do
      nil ->
        []

      page ->
        [
          {@margin, 40, page.title, @accent, :big, nil},
          {@margin, 90, "Esc back", @dim, :small, nil}
        ] ++
          Enum.with_index(page.render.(), fn row, index ->
            {@margin, 130 + index * @line, Hud.text(row), @ink, :normal, nil}
          end)
    end
  end
end
