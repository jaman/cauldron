defmodule Megablast.Menus do
  @moduledoc """
  The game's menus as `Cauldron.Menu` pages: the title's, the pause menu's, and the
  pages both reach. Requests the title's menu sends are `{:go, move}`, a
  `Cauldron.Front` move.
  """

  alias Cauldron.Menu
  alias Cauldron.Menu.Item

  @sounds %{move: :menu_move, change: :menu_move, choose: :menu_choose, back: :menu_back}
  @actions %{fire: :choose}

  @doc "The title's menu."
  @spec title(map()) :: Menu.t()
  def title(settings) do
    pages = %{
      main: %{
        title: "",
        items: [
          Item.action("LAUNCH", {:request, {:go, {:play, :lane}}}),
          Item.page("HOW TO FLY", :how),
          Item.page("OPTIONS", :options),
          Item.action("QUIT", {:confirm, "ABANDON THE LANE?", {:request, {:go, :quit}}})
        ],
        back: :stay
      }
    }

    Menu.open(Map.merge(shared(), pages), settings, sounds: @sounds, actions: @actions)
  end

  @doc "The pause menu."
  @spec pause(map()) :: Menu.t()
  def pause(settings) do
    pages = %{
      main: %{
        title: "PAUSED",
        items: [
          Item.action("RESUME", :close),
          Item.page("HOW TO FLY", :how),
          Item.page("OPTIONS", :options),
          Item.action("ABANDON", {:confirm, "ABANDON THE LANE?", :leave})
        ]
      }
    }

    Menu.open(Map.merge(shared(), pages), settings, sounds: @sounds, actions: @actions)
  end

  defp shared do
    %{
      options: %{
        title: "OPTIONS",
        items: [
          Item.slider("MUSIC", [:music], {0.0, 1.0}, step: 0.1, default: 0.8),
          Item.slider("EFFECTS", [:sfx], {0.0, 1.0}, step: 0.1, default: 0.8),
          Item.toggle("SHAKE", [:options, :shake], default: true),
          Item.gap(),
          Item.page("CONTROLS", :controls)
        ]
      },
      controls: %{
        title: "CONTROLS",
        items: [
          Item.binding("LEFT", :left),
          Item.binding("RIGHT", :right),
          Item.binding("THRUST", :thrust),
          Item.binding("BRAKE", :brake),
          Item.binding("FIRE", :fire),
          Item.binding("BOMB", :bomb)
        ]
      },
      how: %{
        title: "HOW TO FLY",
        items: [
          Item.note("HOLD FIRE. STEER WITH THE ARROWS."),
          Item.note("KILLS IN QUICK SUCCESSION CHAIN:"),
          Item.note("EVERY FIVE ADD TO THE MULTIPLIER."),
          Item.note("GATHER THE GREEN CREDITS."),
          Item.note("BREAK A BOSS'S PARTS FIRST - ITS"),
          Item.note("CORE IS ARMOURED UNTIL THEN."),
          Item.note("THE TRADER SELLS GUNS BETWEEN"),
          Item.note("STAGES. A BOMB CLEARS THE SKY."),
          Item.gap(),
          Item.action("BACK", :back)
        ]
      }
    }
  end
end
