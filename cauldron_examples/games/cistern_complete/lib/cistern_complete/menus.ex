defmodule CisternComplete.Menus do
  @moduledoc """
  The game's menus as `Cauldron.Menu` pages: the title's, the pause menu's, and the
  pages both reach — the options, the controls, and how to play. Requests the title's
  menu sends are `{:go, move}`, a `Cauldron.Front` move.
  """

  alias Cauldron.Menu
  alias Cauldron.Menu.Item

  @sounds %{move: :menu_move, change: :menu_move, choose: :menu_choose, back: :menu_back}
  @actions %{pour: :choose}

  @doc "The title's menu."
  @spec title(map()) :: Menu.t()
  def title(settings) do
    pages = %{
      main: %{
        title: "",
        items: [
          Item.action("PLAY", {:request, {:go, {:play, :solo}}}),
          Item.action("VERSUS THE ROBOT", {:request, {:go, {:play, :versus}}}),
          Item.page("HOW TO PLAY", :how),
          Item.page("OPTIONS", :options),
          Item.action("QUIT", {:confirm, "LEAVE THE TOWN?", {:request, {:go, :quit}}})
        ],
        back: :stay
      }
    }

    Menu.open(Map.merge(shared(), pages), settings, sounds: @sounds, actions: @actions)
  end

  @doc "The pause menu, opened during play."
  @spec pause(map()) :: Menu.t()
  def pause(settings) do
    pages = %{
      main: %{
        title: "PAUSED",
        items: [
          Item.action("RESUME", :close),
          Item.page("HOW TO PLAY", :how),
          Item.page("OPTIONS", :options),
          Item.action("QUIT TO TITLE", {:confirm, "LEAVE THIS STORM?", :leave})
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
          Item.toggle("FLASHING", [:options, :flashing], default: true),
          Item.gap(),
          Item.page("CONTROLS", :controls)
        ]
      },
      controls: %{
        title: "CONTROLS",
        items: [
          Item.binding("WALK LEFT", :left),
          Item.binding("WALK RIGHT", :right),
          Item.binding("POUR", :pour)
        ]
      },
      how: %{
        title: "HOW TO PLAY",
        items: [
          Item.note("WALK UNDER THE RINGS TO"),
          Item.note("CATCH THE RAIN IN YOUR JARS."),
          Item.note("A JAR HOLDS FIVE. A DROP IN A"),
          Item.note("FULL JAR SPILLS - A MISS!"),
          Item.note("POUR AT THE GRATE TO SCORE."),
          Item.note("THREE FULL JARS SCORE DOUBLE"),
          Item.note("AND SEND YOUR RIVAL A GUST."),
          Item.note("HAIL BREAKS JARS - DODGE IT."),
          Item.note("FLICKERING LIGHT? STEP ASIDE!"),
          Item.gap(),
          Item.action("BACK", :back)
        ]
      }
    }
  end
end
