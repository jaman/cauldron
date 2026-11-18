defmodule Megablast.Game do
  @moduledoc """
  Five stages up a living lane, flown by one or more pilots together: waves of creatures,
  turrets in the rock, a guardian half way up each stage and a boss at its end, credits
  to gather, and the trader's shop between stages.

  This is a `Cauldron.Game`. Its step is a pipeline over the world: the view climbs,
  the ships fly and fire, things come in (`Megablast.Spawn`), everything moves and
  fires, strikes are settled (`Megablast.Combat`), and the phase moves on
  (`Megablast.Progress`). A world whose `impact` (`Cauldron.Impact`) is frozen holds
  still — the hit-stop of a boss part broken or a ship lost — while its blasts play on.

  ## Options

    * `:seed` — kept for replays; the lane itself is the same every time
    * `:stage` — the stage to start on. Default `1`
    * `:tuning` — overrides on `Megablast.Tuning`'s defaults
  """

  @behaviour Cauldron.Game

  alias Cauldron.{Impact, Tuning}
  alias Cauldron2D.Projectiles
  alias Megablast.{Boss, Combat, Foe, Lane, Progress, Ship, Shop, Spawn, Stages, Weapons}

  @behind 10.0
  @ahead 22.0
  @blast_seconds 0.5

  @impl true
  def init(opts) do
    number = Keyword.get(opts, :stage, 1)
    lane = Lane.new(Stages.stage(number).walls)

    %{
      pilots: %{},
      stage: number,
      phase: :flying,
      lane: lane,
      depth: 0.0,
      start: 0.0,
      wave: 0,
      guarded?: false,
      final?: false,
      boss: nil,
      foes: [],
      shots: [],
      bullets: [],
      pickups: [],
      blasts: [],
      turret_step: Lane.turret_step(lane, -14.0),
      serial: 0,
      impact: Impact.new(),
      timer: 0.0,
      clock: 0.0,
      tuning: Megablast.Tuning.new(Keyword.get(opts, :tuning, [])),
      events: []
    }
  end

  @impl true
  def join(world, id, props) do
    ship =
      Ship.new(
        id,
        Map.get(props, :username, "pilot"),
        {Lane.middle(world.lane), world.depth + 4.0},
        world.tuning,
        Map.get(props, :robot?, false)
      )

    {:ok, put_in(world.pilots[id], ship)}
  end

  @impl true
  def leave(world, id), do: %{world | pilots: Map.delete(world.pilots, id)}

  @impl true
  def handle_input(world, id, %{held: held}) do
    if Map.has_key?(world.pilots, id),
      do: update_in(world.pilots[id], &Ship.hold(&1, held)),
      else: world
  end

  @impl true
  def step(%{impact: %{frozen: frozen}} = world, dt) when frozen > 0,
    do: %{world | impact: Impact.step(world.impact, dt), blasts: age(world.blasts, dt)}

  def step(world, dt) do
    {world, events} =
      {%{world | clock: world.clock + dt}, []}
      |> climb(dt)
      |> fly(dt)
      |> fire(dt)
      |> bombs()
      |> Spawn.step()
      |> move(dt)
      |> guns(dt)
      |> Combat.shots()
      |> Combat.ships()
      |> Combat.gather()
      |> cull()
      |> Progress.step(dt)

    world
    |> Map.update!(:pilots, fn pilots ->
      Map.new(pilots, fn {id, ship} -> {id, Ship.settle(ship, dt)} end)
    end)
    |> Map.merge(%{blasts: age(world.blasts, dt), impact: Impact.step(world.impact, dt)})
    |> Map.update!(:events, &(Enum.reverse(events) ++ &1))
  end

  defp scroll(%{phase: :boss} = world), do: Tuning.get(world.tuning, :boss_scroll)
  defp scroll(%{phase: :shop}), do: 0.0
  defp scroll(world), do: Tuning.get(world.tuning, :scroll)

  defp climb({world, events}, dt),
    do: {%{world | depth: world.depth - scroll(world) * dt}, events}

  defp fly({world, events}, dt) do
    context = %{depth: world.depth, scroll: scroll(world), lane: world.lane, tuning: world.tuning}

    {%{
       world
       | pilots: Map.new(world.pilots, fn {id, ship} -> {id, Ship.fly(ship, dt, context)} end)
     }, events}
  end

  defp fire({%{phase: phase} = world, events}, _dt) when phase in [:shop, :clear, :won],
    do: {world, events}

  defp fire({world, events}, dt) do
    Enum.reduce(world.pilots, {world, events}, fn {id, ship}, {w, e} ->
      {ship, shots} = Ship.trigger(ship, dt, w.tuning)
      fired = Enum.map(shots, &Map.put(&1, :by, id))
      e = if fired == [], do: e, else: [{:fire, {ship.x, ship.y}} | e]
      {%{w | pilots: Map.put(w.pilots, id, ship), shots: fired ++ w.shots}, e}
    end)
  end

  defp bombs({%{phase: phase} = world, events}) when phase in [:shop, :won], do: {world, events}

  defp bombs({world, events}) do
    Enum.reduce(world.pilots, {world, events}, fn {id, ship}, {w, e} ->
      case Ship.bomb(ship) do
        {ship, true} ->
          Combat.bomb({%{w | pilots: Map.put(w.pilots, id, ship)}, e}, id, view_span(w))

        {_ship, false} ->
          {w, e}
      end
    end)
  end

  defp move({world, events}, dt) do
    context = %{depth: world.depth, target: target(world), fury: fury(world)}
    shots = Projectiles.step(world.shots, dt, target: &homing_target(world, &1))
    bullets = Projectiles.step(world.bullets, dt)
    pickups = Enum.map(world.pickups, &%{&1 | y: &1.y + 1.2 * dt, age: &1.age + dt})
    boss = world.boss && Boss.move(world.boss, dt, world.depth)

    {%{
       world
       | foes: Enum.map(world.foes, &Foe.move(&1, dt, context)),
         shots: shots,
         bullets: bullets,
         pickups: pickups,
         boss: boss
     }, events}
  end

  defp homing_target(world, %{motion: {:homing, _speed, _turn}} = shot), do: nearest(world, shot)
  defp homing_target(_world, _shot), do: nil

  defp nearest(world, shot) do
    candidates =
      Enum.map(world.foes, &{&1.x, &1.y}) ++
        if(world.boss,
          do: for(p <- Boss.pieces(world.boss), not p.armoured?, do: {p.x, p.y}),
          else: []
        )

    Enum.min_by(candidates, fn {x, y} -> (x - shot.x) ** 2 + (y - shot.y) ** 2 end, fn -> nil end)
  end

  defp guns({%{phase: phase} = world, events}, _dt) when phase in [:shop, :clear, :won],
    do: {world, events}

  defp guns({world, events}, dt) do
    context = %{depth: world.depth, target: target(world), fury: fury(world)}
    speed = Tuning.get(world.tuning, :bullet_speed)
    span = view_span(world)

    {foes, bullets} =
      Enum.map_reduce(world.foes, world.bullets, fn foe, acc ->
        {foe, fired} = Foe.fire(foe, dt, context, speed, span)
        {foe, fired ++ acc}
      end)

    {boss, boss_bullets} =
      if world.boss,
        do: Boss.fire(world.boss, dt, context.target, speed * fury(world)),
        else: {nil, []}

    {%{world | foes: foes, bullets: boss_bullets ++ bullets, boss: boss}, events}
  end

  defp cull({world, events}) do
    {top, bottom} = {world.depth - @ahead, world.depth + @behind}
    inside? = fn thing -> thing.y > top and thing.y < bottom end
    open? = fn thing -> inside?.(thing) and Lane.open?(world.lane, thing.x, thing.y) end

    {%{
       world
       | foes:
           Enum.filter(world.foes, &(inside?.(&1) or (&1.kind == :turret and &1.y <= bottom))),
         shots: Enum.filter(world.shots, &(inside?.(&1) and &1.y > world.depth - 12)),
         bullets: Enum.filter(world.bullets, open?),
         pickups: Enum.filter(world.pickups, &(inside?.(&1) and &1.age < 9.0))
     }, events}
  end

  defp target(world) do
    case for({_id, ship} <- world.pilots, not ship.out?, do: ship) do
      [] -> nil
      ships -> ships |> Enum.min_by(& &1.y) |> then(&{&1.x, &1.y})
    end
  end

  defp fury(world), do: 1.0 + (world.stage - 1) * 0.12

  defp view_span(world), do: {world.depth - 11.0, world.depth + 9.0}

  defp age(blasts, dt),
    do: Cauldron.Effects.step(blasts, dt, @blast_seconds)

  @impl true
  def view(world, id) do
    me = Map.get(world.pilots, id)

    %{
      me: me,
      others: for({other, ship} <- world.pilots, other != id, do: ship),
      lane: world.lane,
      depth: world.depth,
      stage: Stages.stage(world.stage),
      through: Progress.through(world),
      phase: world.phase,
      timer: world.timer,
      foes: world.foes,
      boss:
        world.boss &&
          %{
            name: world.boss.design.name,
            health: Boss.health(world.boss),
            pieces: Boss.pieces(world.boss),
            hit: world.boss.hit
          },
      shots: world.shots,
      bullets: world.bullets,
      pickups: world.pickups,
      blasts: world.blasts,
      shake: world.impact.shake,
      clock: world.clock,
      multiplier: me && Ship.multiplier(me, world.tuning),
      wares: me && wares(me),
      drones: me && Weapons.drones(me.kit, {me.x, me.y})
    }
  end

  defp wares(ship),
    do: for(ware <- Shop.wares(), do: Map.put(ware, :price, Shop.price(ware.id, ship.kit)))

  @impl true
  def drain_events(world), do: {Enum.reverse(world.events), %{world | events: []}}

  @doc "The outcome for the pilot of `view`: `nil` while they fly, or the summary once they are out or the lane is won."
  @spec outcome(map()) :: map() | nil
  def outcome(%{me: %{out?: true} = me, stage: stage}), do: summary(me, stage, false)
  def outcome(%{me: %{} = me, phase: :won, stage: stage}), do: summary(me, stage, true)
  def outcome(_view), do: nil

  defp summary(me, stage, won?) do
    %{
      title: if(won?, do: "THE QUEEN IS DEAD", else: "SHIP LOST"),
      lines: ["#{me.score} points", "reached #{stage.name}"],
      next: :same_world,
      score: me.score,
      stage: stage.number,
      won?: won?
    }
  end
end
