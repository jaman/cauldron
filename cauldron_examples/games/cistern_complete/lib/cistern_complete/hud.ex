defmodule CisternComplete.Hud do
  @moduledoc """
  What is drawn fixed to the pane over a keeper's square, in the game's font: the storm,
  the score, the cistern's gauge, each jar's fill, the rivals, the `+12` of a pour, the
  banner while a storm gathers, the prompts to pour, and the pause menu when it is open.

  Everything is placed against the square's own corners (the square is 256 by 192
  pixels, centred on the pane), so the hud frames the square whatever the pane's size.
  """

  alias Cauldron.Menu
  alias Cauldron2D.Menu.Layout
  alias CisternComplete.{Art, Scene, Yoke}

  @gold {255, 214, 110}
  @water {150, 216, 255}
  @cream {245, 232, 210}
  @ink {28, 16, 22}
  @dim {120, 100, 120}
  @left -128
  @top -96
  @right 128
  @bottom 96
  @cistern 150

  @doc "The hud's `Cauldron2D.Screen` items for `view`, the menu from `look` over them when one is open."
  @spec items(map(), map()) :: [Cauldron2D.Screen.item()]
  def items(%{me: me} = view, look) do
    storm(me) ++
      score(me) ++
      gauge(me) ++
      jars(me, view.capacity) ++
      rivals(view.rivals) ++
      pops(me) ++
      banner(me) ++
      prompt(me, view.capacity) ++ menu(Map.get(look, :menu))
  end

  defp text(words, at, colour, opts \\ []),
    do:
      {:text, :pixel, words, at,
       [anchor: :centre, pivot: :top_left, colour: colour, outline: @ink] ++ opts}

  defp storm(me), do: [text("STORM #{me.level}", {@left + 6, @top + 5}, @gold)]

  defp score(me) do
    words = "SCORE #{me.score}"
    [text(words, {@right - 6 - width(words), @top + 5}, @cream)]
  end

  defp gauge(me) do
    at = {@left + 6, @top + 22}
    fill = min(1.0, me.water / @cistern)

    [
      {:art, :gauge, at, anchor: :centre, pivot: :top_left},
      {:bar, :gauge_water, at, fill, anchor: :centre, pivot: :top_left, direction: :up},
      text("#{me.water}", {@left + 6, @top + 58}, @water)
    ]
  end

  defp jars(me, capacity) do
    present = Map.new(Yoke.jars(me.yoke), &{&1.slot, &1.fill})

    backing =
      {:panel, :frame, {@left + 1, @bottom - 28}, {70, 26},
       anchor: :centre, pivot: :top_left, border: 5}

    [
      backing
      | Enum.flat_map(Enum.with_index([:left, :head, :right]), fn {slot, index} ->
          jar_gauge(Map.get(present, slot), capacity, {@left + 8 + index * 22, @bottom - 13})
        end)
    ]
  end

  defp jar_gauge(nil, _capacity, {x, y}) do
    [
      {:art, :jar_icon, {x, y - 9}, anchor: :centre, pivot: :top_left, alpha: 0.35},
      {:art, :fill_track, {x - 4, y}, anchor: :centre, pivot: :top_left, alpha: 0.35}
    ]
  end

  defp jar_gauge(fill, capacity, {x, y}) do
    [
      {:art, :jar_icon, {x, y - 9}, anchor: :centre, pivot: :top_left},
      {:art, :fill_track, {x - 4, y}, anchor: :centre, pivot: :top_left},
      {:bar, :fill_bar, {x - 3, y + 1}, fill / capacity, anchor: :centre, pivot: :top_left}
    ]
  end

  defp rivals(rivals) do
    rivals
    |> Enum.with_index()
    |> Enum.map(fn {rival, index} ->
      status = if rival.out?, do: "OUT", else: "#{rival.score}"
      words = "#{String.upcase(rival.name)} #{status}"
      colour = if rival.robot?, do: {170, 215, 245}, else: @cream
      text(words, {@right - 6 - width(words), @top + 17 + index * 10}, colour)
    end)
  end

  defp pops(me) do
    for pop <- me.pops do
      {x, y} = Scene.pixel({pop.x, pop.y})
      text(pop.text, {x - div(width(pop.text), 2), y - 14 - pop.age * 18}, @gold)
    end
  end

  defp banner(%{lull: lull, level: level} = me) when lull > 0 do
    {_x, y} = Scene.pixel({8, 4})
    big = "STORM #{level}"

    under =
      if me.water == 0 and level == 1,
        do: "CATCH THE RAIN, POUR IT AT THE GRATE",
        else: "GET READY"

    [
      text(big, {-width(big) - 2, y}, @gold, scale: 2),
      text(under, {-div(width(under), 2), y + 20}, @cream)
    ]
  end

  defp banner(_me), do: []

  defp prompt(%{pouring: pouring}, _capacity) when pouring > 0, do: []

  defp prompt(me, capacity) do
    cond do
      Yoke.water(me.yoke) > 0 and Yoke.over_grate?(me.yoke) ->
        [centred("POUR!", {8, 9.2}, @water)]

      Yoke.all_full?(me.yoke, capacity) and blink?(me.clock) ->
        [centred("JARS FULL - TO THE GRATE!", {8, 4.8}, @gold)]

      true ->
        []
    end
  end

  defp centred(words, at, colour) do
    {x, y} = Scene.pixel(at)
    text(words, {x - div(width(words), 2), y}, colour)
  end

  defp blink?(clock), do: rem(trunc(clock * 3), 2) == 0

  defp menu(nil), do: []

  defp menu(%Menu{} = menu) do
    [{:fill, {0, 0}, :pane, {12, 6, 18, 150}}] ++
      Layout.items(menu, Art.name(),
        font: :pixel,
        panel: {:frame, 5},
        cursor: :cursor,
        slider: {:fill_track, :fill_bar},
        width: 176,
        rows: 7,
        row: 12,
        padding: 10,
        outline: @ink,
        colours: %{
          text: @cream,
          focused: @gold,
          value: @water,
          title: @gold,
          prompt: @gold,
          dim: @dim
        }
      )
  end

  defp width(words),
    do: Cauldron2D.Font.width(Cauldron2D.Atlas.font!(Art.name(), :pixel), words)
end
