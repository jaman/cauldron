defmodule Town.Client do
  @moduledoc """
  The `Cauldron2D.Client.Game` for the town: what the terminal client needs to put a
  villager of the player's own in front of them, in any of the client's projections.

      mix town

  It opens in the town, isometric. WASD or the arrows walk, turned with the view; the
  left mouse button (or space) picks and sends, the right button, `x` or `Esc` cancels,
  `r` cycles the measuring rule and `l` bounds the range. The client's own keys are
  bound as the drafter demo had them: `Tab` changes the view, `Q`/`E` turn, `\\`/`Z` and
  `/`/`C` tilt or pitch, `T` toggles pictures against cells and `B` cycles the glyph
  sets, `H` swaps the villagers between their plain and hero looks, `M` mouse look,
  `+`/`-` zoom, `?` the hints, `^Q` quits. On a controller the left
  stick walks, the right stick aims or looks, `A` picks, `B` cancels, `Start` changes
  the view, `X` toggles cells, the bumpers zoom and the triggers tilt or pitch.
  """

  @behaviour Cauldron2D.Client.Game

  alias Cauldron2D.Input.Pad
  alias Town.{Art, Game, Legend, Rules}

  @impl true
  def title, do: %{name: "TOWN", tagline: "walk around, look about"}

  @impl true
  def atlas, do: Art.install()

  @impl true
  def actions, do: [:up, :down, :left, :right, :pick, :cancel, :ruler, :range]

  @impl true
  def keymaps do
    [
      arrows: %{
        up: [:up, :w],
        down: [:down, :s],
        left: [:left, :a],
        right: [:right, :d],
        pick: [:" ", {:mouse, :left}],
        cancel: [:escape, :x, {:mouse, :right}],
        ruler: [:r],
        range: [:l]
      }
    ]
  end

  @impl true
  def toggles, do: []

  @impl true
  def holds, do: [up: 400, down: 400, left: 400, right: 400]

  @impl true
  def start, do: {:play, :town}

  @impl true
  def look, do: %{projection: :iso, projections: [:iso, :first_person], hero?: false}

  @impl true
  def chat?, do: false

  @impl true
  def padmap(_props) do
    Map.merge(Pad.default_map(actions()), %{pick: [:a], cancel: [:b]})
  end

  @impl true
  def client_keys do
    %{
      {:look, :hero?} => :h,
      back: nil,
      title: nil,
      settings: nil,
      settings_menu: nil,
      talk: nil,
      team: nil,
      watch: nil,
      chat: nil,
      guide: nil,
      projection: :tab,
      turn_left: :q,
      turn_right: :e,
      tilt_up: [:"\\", :z],
      tilt_down: [:/, :c],
      display: :t,
      glyphs: :b,
      mouse_look: :m
    }
  end

  @impl true
  def client_pad do
    %{
      projection: :start,
      display: :x,
      zoom_in: :right_bumper,
      zoom_out: :left_bumper,
      turn_left: nil,
      turn_right: nil
    }
  end

  @impl true
  def worlds(_props) do
    [%{id: :town, name: "The town", world: {Game, [hz: 30]}, players: 0, humans: []}]
  end

  @impl true
  def scene(view), do: scene(view, %{hero?: false})

  @impl true
  def scene(%{me: nil} = view, look) do
    style = if Map.get(look, :hero?, false), do: :hero, else: :plain
    {width, height} = Legend.size()

    %{
      focus: {width / 2, height / 2},
      bounds: Legend.size(),
      cell: &Legend.cell/1,
      movers: Enum.map(view.movers, &mover(&1, view.elapsed, style)),
      labels: []
    }
  end

  def scene(%{me: me} = view, look) do
    style = if Map.get(look, :hero?, false), do: :hero, else: :plain

    %{
      focus: {me.mover.x, me.mover.y},
      bounds: Legend.size(),
      cell: &Legend.cell/1,
      eye: Art.villager(me.mover.tunic, false, style),
      movers: Enum.map(view.movers, &mover(&1, view.elapsed, style)),
      labels: labels(view)
    }
  end

  defp mover(mover, elapsed, style),
    do:
      {Art.villager(mover.tunic, Game.walking?(mover, elapsed), style), {mover.x, mover.y},
       mover.heading}

  defp labels(%{me: %{selected?: true, way: {path, distance}, aim: aim}, ruler: ruler}) do
    steps = for tile <- path, do: {"·", Game.centre(tile), {255, 230, 120}}
    [{Rules.label(ruler, distance), Game.centre(Game.tile(aim)), {255, 255, 255}} | steps]
  end

  defp labels(%{me: %{selected?: true}}), do: [{"?", {0, 0}, {120, 120, 120}}] |> Enum.take(0)
  defp labels(_view), do: []

  @impl true
  def hud(%{me: nil}), do: [["watching"]]

  def hud(%{me: me, ruler: ruler, range: range}) do
    [
      [{"#{me.name}", {245, 235, 200}}, {"  #{position(me.mover)}", nil}],
      [{"rule #{ruler}", {180, 200, 255}}, {"  range #{range || "unbounded"}", nil}],
      [
        {if(me.selected?, do: "selected: point, then pick", else: "pick yourself to plan a way"),
         {150, 150, 165}}
      ]
    ]
  end

  defp position(%{x: x, y: y}), do: "(#{Float.round(x, 1)}, #{Float.round(y, 1)})"

  @impl true
  def listener(%{me: nil}), do: nil
  def listener(%{me: me}), do: {me.mover.x, me.mover.y}

  @impl true
  def sounds, do: fn _ -> nil end

  @impl true
  def music, do: []

  @impl true
  def cue(_view, _screen), do: nil

  @impl true
  def guide do
    [
      {"the town",
       [
         %{art: :villager_blue, name: "you", text: "walk with the arrows; v changes the view"},
         %{art: :villager_green, name: "villager", text: "wanders between the paved tiles"},
         %{art: :plaster_ground_s, name: "house", text: "a door on the side nearest the road"},
         %{art: :tree, name: "tree", text: "not for walking through"}
       ]}
    ]
  end
end
