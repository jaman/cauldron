defmodule Greenware.Menus do
  @moduledoc "The title's and the pause menu's pages, and the options and controls they share."

  alias Cauldron.Menu
  alias Cauldron.Menu.Item
  alias Greenware.Progress

  @sounds %{
    move: :ui_move,
    change: :ui_move,
    choose: :ui_choose,
    back: :ui_back,
    open: :ui_move,
    refuse: :ui_refuse
  }
  @actions %{interact: :choose, back: :back}

  def title(settings) do
    play =
      if Progress.exists?() do
        [Item.action("CONTINUE", {:request, {:go, :continue}})]
      else
        []
      end

    pages = %{
      main: %{
        title: "",
        items:
          play ++
            [
              Item.action(
                "NEW GAME",
                {:confirm, "START AGAIN? THE OLD MENDING WILL BE LOST.",
                 {:request, {:go, :new_game}}}
              ),
              Item.page("HOW TO MEND", :how),
              Item.page("OPTIONS", :options),
              Item.page("CONTROLS", :controls),
              Item.page("CREDITS", :credits),
              Item.action("QUIT", {:confirm, "LEAVE THE BAKE?", {:request, {:go, :quit}}})
            ],
        back: :stay
      }
    }

    Menu.open(Map.merge(shared(), pages), settings, sounds: @sounds, actions: @actions)
  end

  def pause(settings) do
    pages = %{
      main: %{
        title: "",
        items: [
          Item.action("RESUME", :close),
          Item.action("LEAVE THE MEND", {:request, :leave_mend}),
          Item.action(
            "RESTART SCENE",
            {:confirm, "START THIS SCENE AGAIN?", {:request, :restart_scene}}
          ),
          Item.page("HOW TO MEND", :how),
          Item.page("OPTIONS", :options),
          Item.page("CONTROLS", :controls),
          Item.action("TITLE SCREEN", {:confirm, "LEAVE THE BAKE? IT WILL REMEMBER.", :leave})
        ]
      }
    }

    Menu.open(Map.merge(shared(), pages), settings, sounds: @sounds, actions: @actions)
  end

  @doc """
  A tap or a click on a menu at `rect` (design pixels), moving the cursor to the row
  and choosing it. Returns what `Cauldron.Menu.event/3` returns.
  """
  def click(menu, at, settings, {x, y, width}, rows \\ 6) do
    {px, py} = fraction_point(at)

    if px >= x and px <= x + width and py >= y and py <= y + 18 + rows * 22 do
      target = ((py - (y + 30)) / 22) |> floor() |> max(0) |> min(rows - 1)
      current = Enum.find_index(Cauldron.Menu.rows(menu), & &1.focused?) || 0
      menu = move(menu, target - current, settings)
      Cauldron.Menu.event(menu, {:key, :enter}, settings)
    else
      %{menu: menu, settings: settings}
    end
  end

  defp move(menu, 0, _settings), do: menu

  defp move(menu, count, settings) when count > 0 do
    Enum.reduce(1..count, menu, fn _, menu ->
      Cauldron.Menu.event(menu, {:key, :down}, settings).menu
    end)
  end

  defp move(menu, count, settings) do
    Enum.reduce(1..-count, menu, fn _, menu ->
      Cauldron.Menu.event(menu, {:key, :up}, settings).menu
    end)
  end

  defp fraction_point({x, y}) when x >= 0 and x <= 1.02 and y >= 0 and y <= 1.02,
    do: {x * 640, y * 360}

  defp fraction_point({x, y}), do: {x / 80 * 640, y / 45 * 360}

  def summary(settings) do
    pages = %{
      main: %{
        title: "",
        items: [
          Item.action(
            "PLAY AGAIN",
            {:confirm, "BEGIN THE STORY AGAIN?", {:request, {:go, :new_game}}}
          ),
          Item.action("TITLE", {:request, {:go, :title}})
        ],
        back: :stay
      }
    }

    Menu.open(pages, settings, sounds: @sounds, actions: @actions)
  end

  defp shared do
    %{
      options: %{
        title: "OPTIONS",
        items: [
          Item.slider("MUSIC", [:music], {0.0, 1.0}, step: 0.1, default: 0.7),
          Item.slider("SOUND", [:sfx], {0.0, 1.0}, step: 0.1, default: 0.8),
          Item.choice(
            "TEXT SPEED",
            [:options, :text_speed],
            [{:slow, "SLOW"}, {:normal, "NORMAL"}, {:fast, "FAST"}],
            default: :normal
          ),
          Item.toggle("GUIDED MEND", [:options, :guided], default: false),
          Item.toggle("REDUCED MOTION", [:options, :reduced_motion], default: false),
          Item.gap(),
          Item.page("CONTROLS", :controls),
          Item.action("BACK", :back)
        ]
      },
      controls: %{
        title: "CONTROLS",
        items: [
          Item.binding("MOVE CURSOR LEFT", :left),
          Item.binding("MOVE CURSOR RIGHT", :right),
          Item.binding("MOVE CURSOR UP", :up),
          Item.binding("MOVE CURSOR DOWN", :down),
          Item.binding("INTERACT / MEND", :interact),
          Item.binding("TEST THE MEND", :test),
          Item.binding("RESET THE CLAY", :reset),
          Item.binding("UNDO A STROKE", :undo),
          Item.binding("CAT HINT", :hint),
          Item.gap(),
          Item.action("BACK", :back)
        ]
      },
      how: %{
        title: "HOW TO MEND",
        items: [
          Item.note("YOU ARE GREENWARE, A CLAY MENDER."),
          Item.note("THE WORLD IS DRYING OUT. FIX WHAT YOU CAN."),
          Item.note(""),
          Item.note("CLICK THE BROKEN THING TO OPEN THE MEND."),
          Item.note("1 THUMB PRESSES CLAY IN."),
          Item.note("2 PIN CARVES CLAY AWAY."),
          Item.note("3 PADDLE FLATTENS. 4 SPONGE SMOOTHS."),
          Item.note("5 WIRE ADDS STRENGTH ACROSS A CRACK."),
          Item.note("6 WATER SOFTENS. 7 HEAT FIRES."),
          Item.note(""),
          Item.note("SHAPE WHILE WET, THEN FIRE."),
          Item.note("PRESS ENTER (OR TEST) TO SEE IF IT HOLDS."),
          Item.note("THE CAT KNOWS MORE THAN IT SAYS. H."),
          Item.note(""),
          Item.note("MOUSE OR TOUCH: PICK A TOOL, THEN DRAG THE CLAY."),
          Item.gap(),
          Item.action("BACK", :back)
        ]
      },
      credits: %{
        title: "CREDITS",
        items: [
          Item.note("GREENWARE"),
          Item.note("A CAULDRON GAME"),
          Item.note(""),
          Item.note("DESIGN, CODE AND CLAY: THE GREENWARE TEAM"),
          Item.note("ART MADE WITH NXDIFFUSION STUDIO"),
          Item.note("MUSIC MADE WITH ACE-STEP"),
          Item.note("ENGINE: CAULDRON 2D"),
          Item.note("TITLE FACE: BASKERVILLE"),
          Item.note("BODY FACE: AMERICAN TYPEWRITER"),
          Item.note(""),
          Item.note("THANK YOU FOR MENDING."),
          Item.gap(),
          Item.action("BACK", :back)
        ]
      }
    }
  end
end
