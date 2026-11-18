defmodule Beast.Scene do
  @moduledoc """
  A region drawn from a beast's view, from the side: the painted layers behind, standing
  on the ground the beast starts on (on the plain, its grass down to that ground), the
  rock — its lit top where open air is above
  it — ledges, spikes, shut doors and gates, the way on once the boss falls, the standing
  stones, fruit and key, the creatures and the boss in the picture of what they are doing
  (and the warnings of their attacks), missiles, and the beasts in theirs. The hud is
  `Beast.Hud`'s.

  The beast's pictures face right and the creatures' left; each is turned to face the
  way it goes. A blow's five frames keep time with its parts (`Beast.Moves`): the first
  two over its wind-up, the third while it strikes, the last two over its recovery.
  """

  alias Beast.{Art, Boss, Creature, Hero, Hud, Moves}
  alias Cauldron.Impact
  alias Cauldron2D.{BoxBody, Camera, Parallax}

  @body_colour {90, 200, 255, 220}
  @strike_colour {255, 70, 70, 230}

  @doc "The scene for `view` and the client's `look`."
  @spec build(map(), map()) :: map()
  def build(view, look) do
    region = view.region

    %{
      focus: focus(view),
      bounds: {region.width, region.height},
      cell: cell(view),
      layers: layers(region),
      movers: movers(view),
      screen: Hud.items(view, look),
      outlines: outlines(view, look),
      subject: :beast
    }
  end

  defp outlines(view, %{boxes?: true}) do
    heroes = Enum.reject([view.me | view.others], &is_nil/1)

    for(hero <- heroes, do: {BoxBody.box(hero.body), @body_colour}) ++
      for(hero <- heroes, {box, _data} <- List.wrap(Hero.strike(hero)), do: {box, @strike_colour}) ++
      for(c <- view.creatures, c.state != :dead, do: {BoxBody.box(c.body), @body_colour}) ++
      for(
        c <- view.creatures,
        {box, _damage} <- List.wrap(Creature.strike(c)),
        do: {box, @strike_colour}
      ) ++
      boss_outlines(view.boss)
  end

  defp outlines(_view, _look), do: []

  defp boss_outlines(nil), do: []

  defp boss_outlines(boss) do
    for({box, colour} <- [{Boss.hurtbox(boss), @body_colour}], box != nil, do: {box, colour}) ++
      for({box, _damage} <- List.wrap(Boss.strike(boss)), do: {box, @strike_colour})
  end

  defp focus(%{me: nil, region: region}), do: {region.width / 2, region.height / 2}

  defp focus(%{me: me, region: region} = view) do
    {x, y} = {me.body.x, me.body.y - 3.0}
    {x, y} = Camera.within({x, y}, {0.0, 0.0, region.width, region.height - 0.5}, {12.0, 6.0})
    {dx, dy} = Impact.offset(view.shake, view.clock)
    {x + dx, y + dy}
  end

  defp cell(view) do
    region = view.region
    doors = if view.doors_open?, do: MapSet.new(), else: MapSet.new(region.doors)
    gates = if view.gated?, do: MapSet.new(region.gates), else: MapSet.new()

    fn {x, y} = at ->
      cond do
        MapSet.member?(doors, at) -> {:door, [], nil}
        MapSet.member?(gates, at) -> {:gate, [], nil}
        true -> tile(region, at, Map.get(region.tiles, at), Map.get(region.tiles, {x, y - 1}))
      end
    end
  end

  defp tile(region, {x, y}, :rock, above) do
    n = :erlang.phash2({x, y}, 64)
    index = if above == :rock, do: 4 + rem(n, 12), else: rem(n, 4)
    {Art.fallback(:"#{region.rock}_#{index}", :platform), [], nil}
  end

  defp tile(_region, _at, :platform, _above), do: :void
  defp tile(_region, _at, :spikes, _above), do: :void
  defp tile(_region, _at, _open, _above), do: :void

  defp layers(region) do
    {_x, start} = region.start
    ground = start + 1

    back = [
      Parallax.panorama(
        name: :sky,
        art: Art.fallback(:"#{region.backdrop}_sky_tile", :frame),
        size: {32, 9},
        at: {0, 0},
        cover: true,
        factor: {0.06, 0.0},
        void: :opaque
      ),
      Parallax.panorama(
        name: :far,
        art: Art.fallback(:"#{region.backdrop}_far_tile", :frame),
        size: {32, 16},
        at: {0, ground - 8},
        wrap: :x,
        factor: {0.35, 1.0}
      )
    ]

    if region.id == :plain,
      do:
        back ++
          [
            Parallax.panorama(
              name: :near,
              art: Art.fallback(:plain_near_tile, :frame),
              size: {32, 16},
              at: {0, ground - 7},
              wrap: :x,
              factor: {0.8, 1.0}
            )
          ],
      else: back
  end

  defp movers(view) do
    ledges(view.region) ++
      Enum.map(view.region.stones, &stand(:stone, &1)) ++
      Enum.map(view.fruit, &stand(:fruit, &1)) ++
      Enum.map(view.keys, &stand(:key, &1)) ++
      way_on(view) ++
      Enum.flat_map(view.creatures, &creature(&1, view.clock)) ++
      boss(view.boss, view.clock) ++
      Enum.map(view.missiles, &missile/1) ++
      Enum.flat_map(view.others, &hero(&1, view.clock)) ++ hero(view.me, view.clock)
  end

  defp ledges(region) do
    for {at, kind} <- region.tiles, kind in [:platform, :spikes], do: stand(kind, at)
  end

  defp stand(art, {x, y}), do: {art, {x / 1, y / 1}}

  defp way_on(%{beaten?: true, region: %{exit: {x, y}}}), do: [{:exit, {x / 1, y / 1}}]
  defp way_on(_view), do: []

  defp creature(%{state: :dead, t: t}, _clock) when t > 0.3, do: []

  defp creature(c, clock) do
    art =
      case {c.kind, c.state} do
        {:goblin, state} when state in [:windup, :swing] -> Art.fallback(:goblin_raise, :goblin)
        {:archer, :windup} -> Art.fallback(:archer_draw, :archer)
        {kind, _state} -> kind
      end

    shiver =
      if c.state == :windup and c.kind == :crawler, do: :math.sin(clock * 60.0) * 0.06, else: 0.0

    [{art, {c.body.x - 0.5 + shiver, c.body.y - 1.0}, facing(-c.facing), tint(c.hit, c.state)}]
  end

  defp tint(_hit, :dead), do: %{tint: :hurt}
  defp tint(hit, _state) when hit > 0, do: %{tint: :flash}
  defp tint(_hit, _state), do: %{}

  defp boss(nil, _clock), do: []

  defp boss(%{kind: :wyrm} = boss, _clock) do
    warning =
      if boss.state in [:under, :rise, :stuck],
        do: [{:dust, {boss.x - 0.5, boss.ground - 1.0}}],
        else: []

    head =
      if boss.head,
        do: [
          {:wyrm, {elem(boss.head, 0) - 0.5, elem(boss.head, 1) + 1.5}, facing(-boss.facing),
           tint(boss.hit, boss.state)}
        ],
        else: []

    warning ++ head
  end

  defp boss(%{kind: :troll} = boss, _clock) do
    art =
      if boss.state in [:slam_windup, :slam], do: Art.fallback(:troll_raise, :troll), else: :troll

    [{art, {boss.x - 0.5, boss.ground - 1.0}, facing(-boss.facing), tint(boss.hit, boss.state)}]
  end

  defp boss(%{kind: :spirit} = boss, _clock) do
    art = if boss.state == :open, do: Art.fallback(:spirit_open, :spirit), else: :spirit
    roots = columns(boss.state, boss.spot, boss.ground, :roots_windup, :roots, :root)
    [{art, {boss.x - 0.5, boss.ground - 1.0}, nil, tint(boss.hit, boss.state)} | roots]
  end

  defp boss(%{kind: :mage} = boss, clock) do
    art = if boss.state == :cast, do: Art.fallback(:mage_cast, :mage), else: :mage
    hidden? = boss.state == :vanish and rem(trunc(clock * 20), 2) == 0
    pillar = columns(boss.state, boss.spot, boss.ground, :pillar_windup, :pillar, :pillar)

    if(hidden?,
      do: [],
      else: [
        {art, {boss.x - 0.5, boss.y - 1.0}, facing(-boss.facing), tint(boss.hit, boss.state)}
      ]
    ) ++ pillar
  end

  defp columns(warning, x, ground, warning, _strike, _art) when is_number(x),
    do: [{:glow, {x - 0.5, ground - 1.0}}]

  defp columns(strike, x, ground, _warning, strike, art) when is_number(x),
    do: for(dy <- 1..4, do: {art, {x - 0.5, ground - dy}})

  defp columns(_state, _x, _ground, _warning, _strike, _art), do: []

  defp missile(%{kind: kind} = m) do
    art = Map.fetch!(%{arrow: :arrow, orb: :orb, seed: :seed, wave: :wave}, kind)
    {art, {m.x - 0.5, m.y - 0.5}, if(m.vx < 0, do: :math.pi(), else: 0.0)}
  end

  defp hero(nil, _clock), do: []

  defp hero(hero, clock) do
    blink? = Hero.untouchable?(hero) and hero.state != :dead and rem(trunc(clock * 16), 2) == 0
    tint = if hero.state == :dead, do: %{tint: :hurt}, else: %{}

    if blink?,
      do: [],
      else: [{pose(hero), {hero.body.x - 0.5, hero.body.y - 1.0}, facing(hero.facing), tint}]
  end

  defp pose(%{state: {:move, move, t}}) when move in [:jab, :cross],
    do: frame(:hero_punch, move, t)

  defp pose(%{state: {:move, :heavy, t}}), do: frame(:hero_punch, :heavy, t)

  defp pose(%{state: {:move, move, t}}) when move in [:low, :sweep],
    do: frame(:hero_sweep, move, t, Art.fallback(:hero_duck, :hero))

  defp pose(%{state: {:move, move, t}}), do: frame(:hero_kick, move, t)
  defp pose(%{state: {:charge, _t}}), do: Art.fallback(:hero_charge, :hero)
  defp pose(%{state: {:dodge, _t}}), do: Art.fallback(:hero_roll, :hero)
  defp pose(%{state: {:hurt, _t}}), do: Art.fallback(:hero_hurt, :hero)
  defp pose(%{state: :dead}), do: Art.fallback(:hero_hurt, :hero)
  defp pose(%{body: %{grounded?: false}}), do: Art.fallback(:hero_jump, :hero)
  defp pose(%{ducking?: true}), do: Art.fallback(:hero_duck, :hero)
  defp pose(%{body: %{vx: vx}}) when vx != 0, do: Art.fallback(:hero_run, :hero)
  defp pose(_hero), do: :hero

  defp frame(strip, move, t, fallback \\ :hero) do
    n = Cauldron.Moves.frame(Moves.data(move), t, {2, 1, 2}) + 1
    Art.fallback(:"#{strip}_#{n}", fallback)
  end

  defp facing(1), do: 0.0
  defp facing(_left), do: :math.pi()
end
