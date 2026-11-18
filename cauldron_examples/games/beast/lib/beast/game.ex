defmodule Beast.Game do
  @moduledoc """
  The beast's journey across four regions (`Beast.Region`) to the mage who made it.
  One or more beasts travel together; each region's creatures wait where its map puts
  them, its doors open to its key, and its arena's gates shut behind the first beast wholly
  past them and open again when the boss falls, and the way on with them. When no beast is left
  in the arena — each brought back at a standing stone outside it — the gates open, and
  the boss and the creatures it called are gone until a beast goes in again, when the
  boss wakes whole. Past the fourth boss the journey is over.

  This is a `Cauldron.Game`. A step is a pipeline: the beasts move and act, the ground
  and what they find have their say, the arena shuts or opens, the creatures and the
  boss move and attack, missiles fly, blows and wounds are settled
  (`Beast.Combat`), and the dead are cleared away. A world whose `impact`
  (`Cauldron.Impact`) is frozen holds still — the weight of a blow landing — while its
  puffs play on.

  ## Options

    * `:region` — the region to start in. Default `1`
    * `:tuning` — overrides on `Beast.Tuning`'s defaults
  """

  @behaviour Cauldron.Game

  alias Beast.{Boss, Combat, Creature, Hero, Region}
  alias Cauldron.{Impact, Tuning}
  alias Cauldron2D.{BoxBody, Projectiles}

  @dead_seconds 0.6
  @down_seconds 1.6
  @missile_seconds 5.0

  @impl true
  def init(opts) do
    tuning = Beast.Tuning.new(Keyword.get(opts, :tuning, []))
    region = Region.load(Keyword.get(opts, :region, 1))

    enter(
      %{
        heroes: %{},
        tuning: tuning,
        events: [],
        clock: 0.0,
        impact: Impact.new(),
        phase: :play,
        serial: 0
      },
      region
    )
  end

  defp enter(world, region) do
    {creatures, serial} =
      Enum.map_reduce(region.creatures, world.serial, fn {kind, at}, n ->
        {Creature.new(kind, at, n), n + 1}
      end)

    Map.merge(world, %{
      region: region,
      creatures: creatures,
      serial: serial,
      boss: nil,
      beaten?: false,
      gated?: false,
      called_from: nil,
      doors_open?: region.doors == [],
      keys: region.keys,
      fruit: region.fruit,
      missiles: []
    })
  end

  @impl true
  def join(world, id, props) do
    {x, y} = world.region.start

    {:ok,
     put_in(
       world.heroes[id],
       Hero.new(id, Map.get(props, :username, "beast"), {x + 0.5, y + 1.0}, world.tuning)
     )}
  end

  @impl true
  def leave(world, id), do: %{world | heroes: Map.delete(world.heroes, id)}

  @impl true
  def handle_input(world, id, %{held: held}) do
    if Map.has_key?(world.heroes, id),
      do: update_in(world.heroes[id], &Hero.hold(&1, held)),
      else: world
  end

  @impl true
  def step(%{impact: %{frozen: frozen}} = world, dt) when frozen > 0,
    do: %{world | impact: Impact.step(world.impact, dt), clock: world.clock + dt * 0.25}

  def step(world, dt) do
    {world, events} =
      {%{world | clock: world.clock + dt, impact: Impact.step(world.impact, dt)}, []}
      |> heroes(dt)
      |> Combat.ground()
      |> Combat.finds()
      |> arena()
      |> creatures(dt)
      |> boss(dt)
      |> missiles(dt)
      |> Combat.blows()
      |> Combat.wounds()
      |> felled()
      |> revive()
      |> onward()
      |> clear()

    %{world | events: Enum.reverse(events) ++ world.events}
  end

  defp grid(world), do: Region.grid(world.region, world.doors_open?, world.gated?)

  defp heroes({world, events}, dt) do
    grid = grid(world)

    {%{
       world
       | heroes:
           Map.new(world.heroes, fn {id, hero} ->
             {id, Hero.step(hero, dt, grid, world.tuning)}
           end)
     }, events}
  end

  defp arena({%{beaten?: true} = world, events}), do: {world, events}

  defp arena({%{gated?: true} = world, events}) do
    if in_arena?(world),
      do: {world, events},
      else:
        {%{
           world
           | gated?: false,
             boss: nil,
             missiles: [],
             creatures: Enum.reject(world.creatures, &(&1.id >= world.called_from))
         }, events}
  end

  defp arena({world, events}) do
    if in_arena?(world) do
      gate = Region.arena(world.region)
      {right, _y} = world.region.exit || {world.region.width - 1, 0}
      boss = Boss.new(world.region.boss, world.region.boss_at, {gate + 1.0, right + 1.0})

      {%{
         world
         | gated?: true,
           boss: boss,
           called_from: world.serial,
           impact: Impact.shake(world.impact, 0.5)
       }, [{:awaken, world.region.boss} | events]}
    else
      {world, events}
    end
  end

  defp in_arena?(world) do
    gate = Region.arena(world.region)
    Enum.any?(world.heroes, fn {_id, hero} -> hero.body.x - hero.body.w / 2 > gate + 1.0 end)
  end

  defp creatures({world, events}, dt) do
    grid = grid(world)
    gravity = Tuning.get(world.tuning, :gravity)

    {creatures, missiles} =
      Enum.map_reduce(world.creatures, world.missiles, fn creature, acc ->
        stepped = Creature.step(creature, dt, grid, nearest(world, creature.body.x), gravity)
        {stepped, stepped.shots ++ acc}
      end)

    loosed = if length(missiles) > length(world.missiles), do: [:loose | events], else: events
    {%{world | creatures: creatures, missiles: missiles}, loosed}
  end

  defp boss({%{boss: nil} = world, events}, _dt), do: {world, events}

  defp boss({world, events}, dt) do
    boss = Boss.step(world.boss, dt, nearest(world, world.boss.x))

    {spawned, serial} =
      Enum.map_reduce(boss.spawns, world.serial, fn {kind, at}, n ->
        {Creature.new(kind, at, n), n + 1}
      end)

    events =
      Enum.map(boss.shots, &{:cast, {&1.x, &1.y}}) ++
        telegraph(world.boss, boss) ++ opened(world.boss, boss) ++ events

    {%{
       world
       | boss: boss,
         missiles: boss.shots ++ world.missiles,
         creatures: spawned ++ world.creatures,
         serial: serial
     }, events}
  end

  defp opened(before, boss) do
    if Boss.opening?(boss) and not Boss.opening?(before),
      do: [{:opening, {boss.x, boss.y}}],
      else: []
  end

  defp telegraph(%{state: same}, %{state: same}), do: []
  defp telegraph(_before, %{state: state} = boss), do: [{:boss, state, {boss.x, boss.y}}]

  defp missiles({world, events}, dt) do
    grid = grid(world)
    gravity = Tuning.get(world.tuning, :gravity)

    flown =
      world.missiles
      |> Enum.map(&Map.merge(&1, %{motion: motion(&1.kind, gravity), ttl: @missile_seconds}))
      |> Projectiles.step(dt,
        target: &chest(world, &1),
        keep?: &(grid.({floor(&1.x), floor(&1.y)}) != :solid and inside?(world.region, &1))
      )

    {%{world | missiles: flown}, events}
  end

  defp motion(:seed, gravity), do: {:arc, gravity * 0.35}
  defp motion(:orb, _gravity), do: {:homing, 3.5, 1.2}
  defp motion(_kind, _gravity), do: :straight

  defp chest(world, missile) do
    case nearest(world, missile.x) do
      nil -> nil
      {x, y} -> {x, y - 1.3}
    end
  end

  defp inside?(region, %{x: x, y: y}),
    do: x > -2 and x < region.width + 2 and y < region.height + 2

  defp nearest(world, x) do
    live = for {_id, hero} <- world.heroes, hero.state != :dead, do: hero

    case live do
      [] -> nil
      heroes -> heroes |> Enum.min_by(&abs(&1.body.x - x)) |> then(&{&1.body.x, &1.body.y})
    end
  end

  defp felled({%{boss: %{state: :dead, t: t}} = world, events})
       when t >= 1.5 and not world.beaten?,
       do:
         {%{world | beaten?: true, gated?: false, boss: nil, missiles: []},
          [{:beaten, world.region.boss} | events]}

  defp felled(acc), do: acc

  defp revive({world, events}) do
    Enum.reduce(world.heroes, {world, events}, fn
      {id, %{state: :dead, down: down} = hero}, {w, e} when down >= @down_seconds ->
        {Combat.revive(w, id, hero), [{:revive, id} | e]}

      _other, acc ->
        acc
    end)
  end

  defp onward({%{beaten?: true, region: %{exit: {ex, ey}}} = world, events}) do
    if Enum.any?(world.heroes, fn {_id, hero} -> BoxBody.covers?(hero.body, {ex, ey}) end),
      do: next_region(world, events),
      else: {world, events}
  end

  defp onward(acc), do: acc

  defp next_region(%{region: %{number: number}} = world, events) do
    if number >= Region.count() do
      {%{world | phase: :won}, [:won | events]}
    else
      region = Region.load(number + 1)
      {x, y} = region.start

      heroes =
        Map.new(world.heroes, fn {id, hero} ->
          {id,
           %{
             hero
             | body: BoxBody.new({x + 0.5, y + 1.0}, {0.8, 2.6}),
               stone: {x + 0.5, y + 1.0},
               key?: false
           }}
        end)

      {enter(%{world | heroes: heroes}, region), [{:region, number + 1} | events]}
    end
  end

  defp clear({world, events}) do
    {%{
       world
       | creatures: Enum.reject(world.creatures, &(&1.state == :dead and &1.t >= @dead_seconds))
     }, events}
  end

  @impl true
  def view(world, id) do
    region = world.region

    %{
      me: Map.get(world.heroes, id),
      others: for({other, hero} <- world.heroes, other != id, do: hero),
      region:
        Map.take(region, [
          :number,
          :name,
          :id,
          :width,
          :height,
          :tiles,
          :outdoor?,
          :rock,
          :backdrop,
          :start,
          :exit,
          :gates,
          :doors,
          :stones
        ]),
      doors_open?: world.doors_open?,
      gated?: world.gated?,
      beaten?: world.beaten?,
      creatures: world.creatures,
      boss: world.boss,
      boss_name: Boss.name(region.boss),
      missiles: world.missiles,
      fruit: world.fruit,
      keys: world.keys,
      clock: world.clock,
      shake: world.impact.shake,
      phase: world.phase,
      health: Tuning.get(world.tuning, :health)
    }
  end

  @impl true
  def drain_events(world), do: {Enum.reverse(world.events), %{world | events: []}}

  @doc "The outcome for the beast of `view`: `nil` until the journey is over."
  @spec outcome(map()) :: map() | nil
  def outcome(%{phase: :won, me: me}) when me != nil,
    do: %{
      title: "ZELEK FALLS",
      lines: ["the beast is free"],
      next: :same_world,
      score: Map.get(me, :score, 0),
      deaths: me.deaths,
      won?: true
    }

  def outcome(_view), do: nil
end
