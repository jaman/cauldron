defmodule Megablast.Hud do
  @moduledoc """
  What is drawn fixed to the pane over the lane, in the game's font: the score and
  chain, the credits, the stage and how far up it the ship is, shields, ships and bombs,
  a boss's name and health, the cards at a stage's start and end, the warning as a boss
  comes, the trader's shop between stages, and the pause menu when it is open.
  """

  alias Cauldron2D.Atlas
  alias Cauldron2D.Menu.Layout
  alias Megablast.Art

  @chrome {200, 220, 255}
  @gold {255, 214, 110}
  @cyan {110, 230, 255}
  @pink {255, 90, 170}
  @green {110, 240, 150}
  @ink {6, 4, 16}

  @doc "The hud's `Cauldron2D.Screen` items for `view`, the menu in `look` over them when one is open."
  @spec items(map(), map()) :: [Cauldron2D.Screen.item()]
  def items(%{me: nil}, _look), do: []

  def items(view, look) do
    score(view) ++
      credits(view) ++
      stage(view) ++
      ship(view.me) ++
      boss(view.boss) ++ cards(view) ++ shop(view) ++ menu(Map.get(look, :menu))
  end

  defp text(words, at, anchor, colour, opts \\ []),
    do: {:text, :pixel, words, at, [anchor: anchor, colour: colour, outline: @ink] ++ opts}

  defp score(view) do
    chain =
      if view.me.chain > 0,
        do: [text("CHAIN #{view.me.chain}  x#{view.multiplier}", {6, 18}, :top_left, @pink)],
        else: []

    [text("SCORE #{pad(view.me.score)}", {6, 6}, :top_left, @chrome)] ++ chain
  end

  defp credits(view) do
    [
      {:art, :credit, {-46, 2}, anchor: :top_right},
      text("#{view.me.credits}", {-6, 6}, :top_right, @green)
    ]
  end

  defp stage(view) do
    [
      text("STAGE #{view.stage.number}", {-6, 18}, :top_right, @cyan),
      {:art, :bar_track, {-46, 30}, anchor: :top_right, pivot: :top_left},
      {:bar, :bar_shield, {-45, 31}, view.through, anchor: :top_right, pivot: :top_left}
    ]
  end

  defp ship(me) do
    shields = me.shields / 3

    [
      text("SHIELD", {6, -16}, :bottom_left, @cyan),
      {:art, :bar_track, {52, -15}, anchor: :bottom_left},
      {:bar, :bar_shield, {53, -16}, min(1.0, shields), anchor: :bottom_left},
      text("SHIPS #{me.lives}   BOMBS #{me.kit.bombs}", {6, -4}, :bottom_left, @chrome)
    ]
  end

  defp boss(nil), do: []

  defp boss(boss) do
    [
      text(boss.name, {0, 30}, :top, @pink),
      {:art, :boss_track, {0, 42}, anchor: :top},
      {:bar, :bar_boss, {-60, 43}, boss.health, anchor: :top, pivot: :top_left}
    ]
  end

  defp cards(%{phase: :flying, through: through, stage: stage} = view) when through < 0.06 do
    big("STAGE #{stage.number}", -18, @gold, view.clock) ++ [centred(stage.name, 6, @chrome)]
  end

  defp cards(%{phase: :boss, boss: %{health: health} = boss, clock: clock}) when health >= 1.0 do
    if rem(trunc(clock * 3), 2) == 0,
      do: big("WARNING", -18, @pink, clock) ++ [centred(boss.name, 6, @gold)],
      else: []
  end

  defp cards(%{phase: :clear, stage: stage, clock: clock}),
    do:
      big("STAGE CLEAR", -18, @gold, clock) ++
        [centred("#{stage.name} IS BEHIND YOU", 6, @chrome)]

  defp cards(%{phase: :won, clock: clock}),
    do: big("THE QUEEN IS DEAD", -18, @gold, clock) ++ [centred("THE LANE IS CLEAN", 6, @chrome)]

  defp cards(_view), do: []

  defp big(words, y, colour, _clock) do
    width = width(words) * 2

    [
      {:text, :pixel, words, {-div(width, 2), y},
       anchor: :centre, pivot: :top_left, colour: colour, shadow: @ink, scale: 2}
    ]
  end

  defp centred(words, y, colour) do
    {:text, :pixel, words, {-div(width(words), 2), y},
     anchor: :centre, pivot: :top_left, colour: colour, outline: @ink}
  end

  defp shop(%{phase: :shop, me: me, wares: wares, timer: timer}) do
    box = {-150, -88}

    [
      {:fill, {0, 0}, :pane, {4, 2, 12, 170}},
      {:panel, :frame, box, {300, 176}, anchor: :centre, pivot: :top_left, border: 5},
      {:art, :trader, {-140, -78}, anchor: :centre, pivot: :top_left},
      text("THE TRADER", {-66, -78}, :centre, @gold, pivot: :top_left),
      text("WELCOME, PILOT. CREDITS BUY", {-66, -64}, :centre, @chrome, pivot: :top_left),
      text("WHAT THE LANE WILL NOT GIVE.", {-66, -54}, :centre, @chrome, pivot: :top_left),
      text("CREDITS #{me.credits}", {-140, -6}, :centre, @green, pivot: :top_left),
      text("#{max(0, round(timer))} S", {-140, 6}, :centre, @cyan, pivot: :top_left)
    ] ++ wares(wares, me) ++ ready(me)
  end

  defp shop(_view), do: []

  defp wares(wares, me) do
    wares
    |> Enum.with_index()
    |> Enum.flat_map(fn {ware, index} ->
      y = -36 + index * 11
      colour = ware_colour(ware, me, index)

      cursor =
        if index == me.cursor,
          do: [{:art, :cursor, {-74, y}, anchor: :centre, pivot: :top_left}],
          else: []

      cursor ++
        [text(ware.name, {-62, y}, :centre, colour, pivot: :top_left), price(ware, y, colour)]
    end)
  end

  defp price(%{id: :launch}, y, colour),
    do: text("GO", {140 - width("GO"), y}, :centre, colour, pivot: :top_left)

  defp price(%{price: nil}, y, _colour),
    do: text("SOLD OUT", {140 - width("SOLD OUT"), y}, :centre, {90, 90, 110}, pivot: :top_left)

  defp price(%{price: price}, y, colour),
    do: text("#{price}", {140 - width("#{price}"), y}, :centre, colour, pivot: :top_left)

  defp ware_colour(_ware, me, index) when index == me.cursor, do: @gold
  defp ware_colour(%{price: nil}, _me, _index), do: {90, 90, 110}
  defp ware_colour(%{id: :launch}, _me, _index), do: @cyan
  defp ware_colour(%{price: price}, me, _index) when price > me.credits, do: {130, 110, 140}
  defp ware_colour(_ware, _me, _index), do: @chrome

  defp ready(%{ready?: true}), do: [centred("WAITING FOR THE OTHERS", 74, @cyan)]
  defp ready(_me), do: []

  defp menu(nil), do: []

  defp menu(menu) do
    [{:fill, {0, 0}, :pane, {4, 2, 12, 150}}] ++
      Layout.items(menu, Art.name(),
        font: :pixel,
        panel: {:frame, 5},
        cursor: :cursor,
        slider: {:bar_track, :bar_shield},
        width: 180,
        rows: 7,
        row: 12,
        padding: 10,
        outline: @ink,
        colours: %{text: @chrome, focused: @gold, value: @cyan, title: @gold, prompt: @gold}
      )
  end

  defp pad(score), do: score |> Integer.to_string() |> String.pad_leading(7, "0")

  defp width(words), do: Cauldron2D.Font.width(Atlas.font!(Art.name(), :pixel), words)
end
