defmodule Beast.Menus do
  @moduledoc """
  The game's menus as `Cauldron.Menu` pages: the title's, the pause menu's, and the
  pages both reach. Requests the title's menu sends are `{:go, move}`, a
  `Cauldron.Front` move. The options page lists the terminal's display rows and the
  key bindings only in a build for this machine (`Mix.target()` `:host`); a phone has
  neither; on a phone it lists instead which hand the on-screen controls are laid out
  for. The title has no QUIT on iOS or tvOS, where an app does not close itself.
  """

  alias Cauldron.Menu
  alias Cauldron.Menu.Item
  @keyboard Mix.target() == :host
  @quits Mix.target() not in [:ios, :tvos]
  @phone Mix.target() in [:ios, :android]

  @sounds %{move: :menu_move, change: :menu_move, choose: :menu_choose, back: :menu_back}
  @actions %{attack: :choose}

  @doc "The title's menu."
  @spec title(map()) :: Menu.t()
  def title(settings) do
    pages = %{
      main: %{
        title: "",
        items:
          [
            Item.action("BEGIN THE JOURNEY", {:request, {:go, {:play, :journey}}}),
            Item.page("HOW TO FIGHT", :how),
            Item.page("OPTIONS", :options)
          ] ++ quit_rows(),
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
        title: "RESTING",
        items: [
          Item.action("GO ON", :close),
          Item.page("HOW TO FIGHT", :how),
          Item.page("OPTIONS", :options),
          Item.action("TO THE TITLE", {:confirm, "LEAVE THE JOURNEY?", :leave})
        ]
      }
    }

    Menu.open(Map.merge(shared(), pages), settings, sounds: @sounds, actions: @actions)
  end

  defp shared do
    %{
      options: %{
        title: "OPTIONS",
        items:
          [
            Item.slider("MUSIC", [:music], {0.0, 1.0}, step: 0.1, default: 0.8),
            Item.slider("EFFECTS", [:sfx], {0.0, 1.0}, step: 0.1, default: 0.8),
            Item.toggle("SHAKE", [:options, :shake], default: true)
          ] ++ keyboard_rows() ++ phone_rows()
      },
      controls: %{
        title: "CONTROLS",
        items: [
          Item.binding("LEFT", :left),
          Item.binding("RIGHT", :right),
          Item.binding("JUMP", :jump),
          Item.binding("DUCK", :duck),
          Item.binding("STRIKE", :attack),
          Item.binding("ROLL", :dodge)
        ]
      },
      how: %{
        title: "HOW TO FIGHT",
        items: [
          Item.page("MOVING", :how_moving),
          Item.page("STRIKES", :how_strikes),
          Item.page("CREATURES", :how_creatures),
          Item.page("BOSSES", :how_bosses),
          Item.page("THE JOURNEY", :how_journey),
          Item.gap(),
          Item.action("BACK", :back)
        ]
      },
      how_moving: %{
        title: "MOVING",
        items: [
          Item.note("LEFT AND RIGHT RUN."),
          Item.note("JUMP LEAPS: HOLD IT TO GO HIGH,"),
          Item.note("LET GO EARLY FOR A SHORT HOP."),
          Item.note("DUCK CROUCHES LOW: ARROWS AND"),
          Item.note("HIGH BLOWS PASS OVER YOU."),
          Item.note("ROLL DASHES FORWARD. NOTHING"),
          Item.note("HURTS YOU WHILE YOU ROLL: ROLL"),
          Item.note("THROUGH BLOWS YOU CANNOT DUCK."),
          Item.gap(),
          Item.action("BACK", :back)
        ]
      },
      how_strikes: %{
        title: "STRIKES",
        items: [
          Item.note("STRIKE: A JAB. STRIKE AGAIN AS IT"),
          Item.note("ENDS FOR A CROSS, AND AGAIN AS"),
          Item.note("THAT ENDS FOR A KICK. A PRESS"),
          Item.note("JUST BEFORE THE END COUNTS TOO."),
          Item.note("HOLD STRIKE AFTER A JAB, LET GO"),
          Item.note("FOR A HEAVY BLOW: FOUR TIMES THE"),
          Item.note("HARM, THROWS FOES FAR."),
          Item.note("STRIKE IN THE AIR: FLYING KICK."),
          Item.note("DUCK AND STRIKE: A LOW JAB, AND"),
          Item.note("STRIKE AGAIN FOR A LOW SWEEP."),
          Item.note("BLOWS BREAK ORBS AND SEEDS."),
          Item.gap(),
          Item.action("BACK", :back)
        ]
      },
      how_creatures: %{
        title: "CREATURES",
        items: [
          Item.note("EVERY CREATURE SHOWS ITS BLOW"),
          Item.note("BEFORE IT STRIKES. HIT IT THEN"),
          Item.note("AND IT STAGGERS."),
          Item.note("CRAWLERS SHIVER, THEN LUNGE."),
          Item.note("BATS HOVER OVER YOU, THEN DIVE."),
          Item.note("GOBLINS RAISE THEIR CLUBS."),
          Item.note("ARCHERS DRAW: DUCK THE ARROW."),
          Item.gap(),
          Item.action("BACK", :back)
        ]
      },
      how_bosses: %{
        title: "BOSSES",
        items: [
          Item.note("THE GATES SHUT BEHIND YOU. EACH"),
          Item.note("BOSS LEAVES AN OPENING: A CHIME"),
          Item.note("RINGS WHEN IT DOES. STRIKE THEN."),
          Item.note("WYRM: HIT ITS HEAD WHILE DAZED."),
          Item.note("TROLL: JUMP SWEEPS AND WAVES,"),
          Item.note("ROLL ITS CHARGE, HIT IT WINDED."),
          Item.note("SPIRIT: DODGE THE GLOWING ROOTS,"),
          Item.note("STRIKE ITS FACE WHEN IT OPENS."),
          Item.note("MAGE: BREAK HIS ORBS, CLIMB,"),
          Item.note("HIT HIM AS LIGHTNING COMES."),
          Item.gap(),
          Item.action("BACK", :back)
        ]
      },
      how_journey: %{
        title: "THE JOURNEY",
        items: [
          Item.note("A STANDING STONE KEEPS YOUR"),
          Item.note("PLACE: FALL AND YOU RISE AT"),
          Item.note("THE LAST ONE YOU TOUCHED."),
          Item.note("FRUIT HEALS. THE KEY OPENS"),
          Item.note("THE LAND'S DOORS. BEAT THE"),
          Item.note("BOSS AND THE WAY ON OPENS."),
          Item.gap(),
          Item.action("BACK", :back)
        ]
      }
    }
  end

  if @quits do
    defp quit_rows,
      do: [Item.action("QUIT", {:confirm, "LEAVE THE BEAST?", {:request, {:go, :quit}}})]
  else
    defp quit_rows, do: []
  end

  if @phone do
    defp phone_rows, do: Cauldron2D.Native.Settings.menu_items(&String.upcase/1)
  else
    defp phone_rows, do: []
  end

  if @keyboard do
    defp keyboard_rows,
      do:
        Cauldron2D.Drafter.Client.Settings.menu_items(Beast.Client, &String.upcase/1) ++
          [Item.gap(), Item.page("CONTROLS", :controls)]
  else
    defp keyboard_rows, do: []
  end
end
