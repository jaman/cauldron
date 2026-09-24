defmodule Parade.Client do
  @moduledoc """
  The `Cauldron2D.Client.Game` for the parade: a courtyard of 32-pixel tiles walked by
  knights drawn at 32 by 48, to show what detailed art looks like in a terminal.

      mix parade

  Holding `1` to `4` aims an emanation, a cone or a burst — bless, bane, a gale blast and
  an acidic burst — showing the area faintly while you turn, and letting go casts it
  there. Bless keeps up with the knight who cast it and bane with the knight nearest them
  when it was cast; the gale and the burst stay where they land. `G` marks every area out
  in whole squares, the way a table plays them, rather than at its true reach.

  A right click walks the knight to that tile, around the pillars; the left button is the
  view's, for dragging it round.

  It opens isometric. WASD or the arrows walk, `Tab` changes the view, `Q`/`E` turn,
  `\\`/`Z` and `/`/`C` tilt or pitch, `T` toggles pictures against cells, `B` cycles the
  glyph sets, `M` mouse look, `+`/`-` zoom, `?` the hints, `^Q` quits. A drag with the
  mouse turns the view wherever it turns freely: the eye in first person and mode 7, the
  isometric view here, which the courtyard offers at sixteen facings. On a controller the
  left stick walks, `Start` changes the view and the bumpers zoom.
  """

  @behaviour Cauldron2D.Client.Game

  alias Cauldron2D.Input.Pad
  alias Parade.{Art, Game, Legend, Spell}

  @impl true
  def title, do: %{name: "PARADE", tagline: "detailed figures, drawn in cells"}

  @impl true
  def atlas, do: Art.install()

  @pad_spells %{gale: [:y], bless: [:a], bane: [:b], acid: [:back]}

  @impl true
  def actions, do: [:up, :down, :left, :right, :squares, :go | Spell.kinds()]

  @impl true
  def keymaps do
    [
      arrows:
        %{
          up: [:up, :w],
          down: [:down, :s],
          left: [:left, :a],
          right: [:right, :d],
          squares: [:g],
          go: [{:mouse, :right}]
        }
        |> Map.merge(spell_keys())
    ]
  end

  defp spell_keys do
    Spell.kinds()
    |> Enum.with_index(1)
    |> Map.new(fn {kind, index} -> {kind, [:"#{index}"]} end)
  end

  @impl true
  def toggles, do: [:squares]

  @impl true
  def holds, do: Enum.map([:up, :down, :left, :right] ++ Spell.kinds(), &{&1, 400})

  @impl true
  def start, do: {:play, :courtyard}

  @impl true
  def look,
    do: %{
      projection: :iso,
      projections: [:iso, :oblique, :mode7, :first_person, :top],
      facings: 16,
      density: %{iso: 16, oblique: 16, top: 16, mode7: 6, first_person: 6}
    }

  @impl true
  def chat?, do: false

  @impl true
  def padmap(_props), do: Map.merge(Pad.default_map(actions()), @pad_spells)

  @impl true
  def client_keys do
    %{
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
    %{projection: :start, display: :x, zoom_in: :right_bumper, zoom_out: :left_bumper}
  end

  @impl true
  def worlds(_props) do
    [%{id: :courtyard, name: "The courtyard", world: {Game, [hz: 30]}, players: 0, humans: []}]
  end

  @impl true
  def scene(%{me: nil} = view) do
    {width, height} = Legend.size()

    %{
      focus: {width / 2, height / 2},
      bounds: Legend.size(),
      cell: &Legend.cell/1,
      movers: Enum.map(view.movers, &mover(&1, view.elapsed)),
      volumes: view.volumes,
      labels: []
    }
  end

  def scene(%{me: me} = view) do
    %{
      focus: {me.mover.x, me.mover.y},
      bounds: Legend.size(),
      cell: &Legend.cell/1,
      eye: Art.walker(me.mover.colour, false),
      movers: Enum.map(view.movers, &mover(&1, view.elapsed)),
      volumes: view.volumes,
      labels: way(me.route)
    }
  end

  defp way([]), do: []

  defp way(route) do
    {last, steps} = List.pop_at(route, -1)

    Enum.map(steps, &{"·", &1, {255, 230, 120}}) ++ [{"×", last, {255, 230, 120}}]
  end

  defp mover(mover, elapsed),
    do:
      {Art.walker(mover.colour, Game.walking?(mover, elapsed)), {mover.x, mover.y}, mover.heading}

  @impl true
  def hud(%{me: nil}), do: [["watching"]]

  def hud(%{me: me} = view) do
    [
      [{me.name, {232, 180, 137}}, {"  #{position(me.mover)}", nil}],
      [{"hold to aim, let go to cast  ·  right click to walk", {150, 150, 165}}],
      spells(),
      [{"G  #{marking(view)}", {150, 150, 165}}]
    ]
  end

  defp spells do
    Spell.kinds()
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {kind, index} ->
      [{"#{index} ", {150, 150, 165}}, {"#{Spell.name(kind)}  ", Spell.colour(kind)}]
    end)
  end

  defp marking(%{marking: :squares}), do: "marked out in squares"
  defp marking(_view), do: "marked out at true reach"

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
      {"the courtyard",
       [
         %{art: :walker_crimson, name: "you", text: "walk with the arrows; Tab changes the view"},
         %{art: :walker_forest, name: "knight", text: "crosses the yard on its own"},
         %{art: :pillar, name: "pillar", text: "two storeys of stone"},
         %{
           art: :walker_amber,
           name: "spells",
           text: "hold 1-4 to aim, let go to cast; G marks it out in squares"
         },
         %{
           art: :walker_plum,
           name: "walking",
           text: "right click a tile and the knight finds its way there"
         }
       ]}
    ]
  end
end
