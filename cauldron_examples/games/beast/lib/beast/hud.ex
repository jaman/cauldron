defmodule Beast.Hud do
  @moduledoc """
  What is drawn fixed to the pane over the region, in the game's font: the beast's
  hearts, its score, the key once found, the region's name as it is entered, the boss's
  name and health while it fights — with how to beat it (`Beast.Boss.hint/1`) for its
  first seconds awake — the end of the journey, and the pause menu.
  """

  alias Beast.Art
  alias Cauldron2D.Atlas
  alias Cauldron2D.Menu.Layout

  @bone {240, 228, 200}
  @blood {230, 60, 70}
  @gold {255, 214, 110}
  @ink {14, 6, 8}
  @hint_seconds 8.0

  @doc "The hud's `Cauldron2D.Screen` items for `view`, the menu in `look` over them when one is open."
  @spec items(map(), map()) :: [Cauldron2D.Screen.item()]
  def items(%{me: nil}, _look), do: []

  def items(view, look) do
    hearts(view.me.health, view.health) ++
      [text("#{view.me.score}", {-6, 6}, :top_right, @bone)] ++
      key(view) ++ card(view) ++ boss(view) ++ won(view) ++ menu(Map.get(look, :menu))
  end

  defp text(words, at, anchor, colour, opts \\ []),
    do: {:text, :pixel, words, at, [anchor: anchor, colour: colour, outline: @ink] ++ opts}

  defp hearts(health, most) do
    for n <- 0..(div(most, 2) - 1) do
      art =
        cond do
          health >= (n + 1) * 2 -> :heart
          health == n * 2 + 1 -> :heart_half
          true -> :heart_empty
        end

      {:art, art, {6 + n * 10, 6}, anchor: :top_left}
    end
  end

  defp key(%{doors_open?: true, region: %{doors: [_ | _]}}),
    do: [{:art, :key, {-30, 18}, anchor: :top_right}]

  defp key(_view), do: []

  defp card(%{me: %{body: %{x: x}}, region: %{start: {sx, _sy}} = region}) when abs(x - sx) < 8,
    do: [big(region.name, -40, @gold)]

  defp card(_view), do: []

  defp boss(%{boss: nil}), do: []

  defp boss(%{boss: boss, boss_name: name}) do
    [
      text(name, {0, -26}, :bottom, @blood),
      {:art, :boss_track, {0, -14}, anchor: :bottom},
      {:bar, :bar_boss, {-60, -15}, boss.hp / boss.max, anchor: :bottom, pivot: :bottom_left}
    ] ++ hint(boss)
  end

  defp hint(%{fought: fought, kind: kind}) when fought < @hint_seconds,
    do: [text(Beast.Boss.hint(kind), {0, -38}, :bottom, @bone)]

  defp hint(_boss), do: []

  defp won(%{phase: :won}),
    do: [big("ZELEK FALLS", -20, @gold), centred("THE BEAST IS FREE", 6, @bone)]

  defp won(_view), do: []

  defp big(words, y, colour) do
    width = width(words) * 2

    {:text, :pixel, words, {-div(width, 2), y},
     anchor: :centre, pivot: :top_left, colour: colour, shadow: @ink, scale: 2}
  end

  defp centred(words, y, colour),
    do:
      {:text, :pixel, words, {-div(width(words), 2), y},
       anchor: :centre, pivot: :top_left, colour: colour, outline: @ink}

  defp menu(nil), do: []

  defp menu(menu) do
    [{:fill, {0, 0}, :pane, {10, 4, 6, 150}}] ++
      Layout.items(menu, Art.name(),
        font: :pixel,
        panel: {:frame, 5},
        cursor: :cursor,
        slider: {:slider_track, :slider_fill},
        width: 224,
        rows: 7,
        row: 12,
        padding: 10,
        outline: @ink,
        colours: %{text: @bone, focused: @gold, value: @blood, title: @gold, prompt: @gold}
      )
  end

  defp width(words), do: Cauldron2D.Font.width(Atlas.font!(Art.name(), :pixel), words)
end
