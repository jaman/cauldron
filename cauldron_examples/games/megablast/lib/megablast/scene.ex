defmodule Megablast.Scene do
  @moduledoc """
  The lane drawn from a pilot's view: the stage's backdrop creeping behind, the rock
  walls, credit bubbles, creatures and turrets (white while struck), the boss's pieces,
  bullets and shots, the ships (blinking while untouchable) with their drones and
  flames, and the blasts. The view shakes when the world says so. The hud is
  `Megablast.Hud`'s.

  Everything in play is at the middle of its picture, whatever the picture's size.
  """

  alias Cauldron.Impact
  alias Cauldron2D.{Atlas, Parallax}
  alias Megablast.{Art, Hud, Lane}

  @lift 2.0
  @tile 16

  @doc "The scene for `view` and the client's `look`."
  @spec build(map(), map()) :: map()
  def build(view, look) do
    atlas = Atlas.fetch(Art.name())

    %{
      focus: focus(view),
      bounds: :unbounded,
      cell: Lane.cells(view.lane),
      layers: layers(view),
      movers: movers(view, atlas),
      screen: Hud.items(view, look),
      subject: :ship
    }
  end

  defp focus(view) do
    {x, y} = {Lane.middle(view.lane), view.depth + @lift}
    {dx, dy} = Impact.offset(view.shake * 1.25, view.clock)
    {x + dx, y + dy}
  end

  defp layers(view) do
    [
      Parallax.panorama(
        name: :backdrop,
        art: :"#{view.stage.backdrop}_tile",
        size: {10, 40},
        wrap: :both,
        factor: {0.0, 0.3},
        void: :opaque
      )
    ]
  end

  defp movers(view, atlas) do
    put = &placed(atlas, &1, &2, &3)

    Enum.map(view.pickups, &put.(:credit, &1, nil)) ++
      Enum.map(view.foes, &put.(&1.kind, &1, flash(&1.hit))) ++
      boss(view.boss, put) ++
      Enum.map(view.bullets, &put.(:bullet, &1, nil)) ++
      Enum.map(view.shots, &put.(&1.kind, &1, nil)) ++
      Enum.flat_map(view.others, &ship(&1, view, put)) ++
      ship(view.me, view, put) ++ Enum.map(view.blasts, &blast(&1, put))
  end

  defp boss(nil, _put), do: []

  defp boss(boss, put) do
    for piece <- boss.pieces,
        do: put.(piece.art, piece, if(piece.name == :core, do: flash(boss.hit), else: nil))
  end

  defp ship(nil, _view, _put), do: []
  defp ship(%{out?: true}, _view, _put), do: []

  defp ship(ship, view, put) do
    blink? = ship.hurt > 0 and rem(trunc(view.clock * 14), 2) == 0

    drones =
      for {x, y} <- Megablast.Weapons.drones(ship.kit, {ship.x, ship.y}),
          do: put.(:addon, %{x: x, y: y}, nil)

    flame = if ship.flame?, do: [put.(:retro, %{x: ship.x, y: ship.y + 1.0}, nil)], else: []

    body =
      if blink?,
        do: [],
        else: [put.(Art.ship(ship.bank), ship, if(ship.hurt > 0, do: :hurt, else: nil))]

    flame ++ drones ++ body
  end

  defp blast(blast, put) do
    frame = Cauldron.Effects.frame(blast, 4, 8) + 1
    art = if blast.size == :big, do: :"big_blast_#{frame}", else: :"blast_#{frame}"
    put.(art, blast, nil)
  end

  defp flash(hit) when hit > 0, do: :flash
  defp flash(_hit), do: nil

  defp placed(atlas, art, %{x: x, y: y}, tint) do
    {_width, height} = Atlas.entry(atlas, art).size
    at = {x - 0.5, y - 1.0 + height / (2 * @tile)}

    case tint do
      nil -> {art, at}
      tint -> {art, at, nil, %{tint: tint}}
    end
  end
end
