defmodule BeastTest do
  use ExUnit.Case, async: true

  alias Beast.{Boss, Creature, Game, Hero, Moves, Region}

  @tuning Beast.Tuning.new()
  @dt 1 / 50

  defp flat, do: fn {_x, y} -> if y >= 10, do: :solid, else: :open end

  defp standing(changes \\ %{}) do
    hero = Hero.new(:p, "p", {5.0, 10.0}, @tuning)
    Map.merge(%{hero | body: %{hero.body | grounded?: true}}, changes)
  end

  defp press(hero, held, steps \\ 1) do
    Enum.reduce(1..steps, Hero.hold(hero, MapSet.new(held)), fn _step, acc ->
      Hero.step(acc, @dt, flat(), @tuning)
    end)
  end

  test "a press in each blow's recovery runs the combo from jab to cross to kick" do
    hero = standing() |> press([:attack]) |> press([], 9)
    assert {:move, :cross, _t} = press(hero, [:attack]).state

    hero = hero |> press([:attack]) |> press([], 9) |> press([:attack])
    assert {:move, :kick, _t} = hero.state
  end

  test "ducking, the attack strikes low, a press in its recovery sweeps, crouched throughout" do
    hero = standing() |> press([:duck]) |> press([:duck, :attack])
    assert {:move, :low, _t} = hero.state
    assert hero.body.h < 2.0

    hero = hero |> press([], 9) |> press([:attack])
    assert {:move, :sweep, _t} = hero.state
    assert hero.body.h < 2.0
  end

  test "the other direction held in a jab's wind-up turns the beast and the jab" do
    hero = standing() |> press([:attack]) |> press([:left])
    assert {:move, :jab, _t} = hero.state
    assert hero.facing == -1
  end

  test "a direction held in a blow's recovery ends the blow and runs" do
    hero = standing() |> press([:attack])
    data = Moves.data(:jab)
    hero = press(hero, [], ceil((data.windup + data.active) / @dt) + 1)
    assert {:move, :jab, _t} = hero.state
    hero = press(hero, [:left])
    assert hero.state == :free
    assert hero.body.vx < 0
  end

  test "a strike pressed just before a blow's recovery still goes on to the next blow" do
    hero = standing() |> press([:attack]) |> press([], 4) |> press([:attack]) |> press([], 6)
    assert {:move, :cross, _t} = hero.state
  end

  test "holding the attack past a jab charges a heavy blow, let go when charged" do
    held = standing() |> press([:attack], 1 + round((0.6 + Moves.data(:jab).windup + 0.3) / @dt))
    assert {:charge, _t} = held.state
    assert {:move, :heavy, _t} = press(held, []).state
  end

  test "a goblin struck while it raises its club staggers and loses the swing" do
    goblin = %{Creature.new(:goblin, {6, 8}, 1) | state: :windup, t: 0.2}
    assert %{state: :stagger} = Creature.struck(goblin, 1, 4.0, 1)
  end

  defp arrows(archer_x, grid, target) do
    Creature.new(:archer, {archer_x, 9}, 1)
    |> Stream.iterate(&Creature.step(&1, @dt, grid, target.(&1.t), 40.0))
    |> Stream.take(150)
    |> Enum.flat_map(& &1.shots)
  end

  test "an archer drawing turns to loose at a beast that jumped over it" do
    jumped = fn t -> if t < 0.3, do: {13.5, 10.0}, else: {27.5, 10.0} end
    assert [%{vx: vx} | _rest] = arrows(20, flat(), jumped)
    assert vx > 0
  end

  test "an archer goes on standing while no beast is in the world" do
    assert arrows(20, flat(), fn _t -> nil end) == []
  end

  test "an archer with a wall at its back looses at the beast rather than backing into it" do
    walled = fn {x, y} -> if y >= 10 or x <= 0, do: :solid, else: :open end
    assert [%{vx: vx} | _rest] = arrows(2, walled, fn _t -> {5.0, 10.0} end)
    assert vx > 0
  end

  test "the arena's gates shut behind the beast and the boss awakens" do
    {:ok, world} = Game.join(Game.init([]), :p, %{username: "p"})
    gate = Region.arena(world.region)
    hero = world.heroes.p
    world = %{world | heroes: %{p: %{hero | body: %{hero.body | x: gate + 2.0}}}}
    stepped = Game.step(world, @dt)

    assert stepped.gated?
    assert stepped.boss.kind == :wyrm
    assert Region.grid(stepped.region, false, true).({gate, 15}) == :solid
  end

  test "with no beast left in the arena the gates open and the boss is gone until it wakes again" do
    {:ok, world} = Game.join(Game.init([]), :p, %{username: "p"})
    gate = Region.arena(world.region)
    hero = world.heroes.p
    inside = %{world | heroes: %{p: %{hero | body: %{hero.body | x: gate + 2.0}}}}
    awake = Game.step(inside, @dt)
    hurt = %{awake | boss: %{awake.boss | hp: 1}}

    revived = %{hurt | heroes: %{p: Hero.revive(hurt.heroes.p, hurt.tuning)}}
    outside = Game.step(revived, @dt)
    assert outside.gated? == false
    assert outside.boss == nil

    back = Game.step(%{outside | heroes: inside.heroes}, @dt)
    assert back.gated? == true
    assert back.boss.hp == back.boss.max
  end

  test "after its arc the wyrm lies dazed, harmless, its head in reach of a blow from the ground" do
    wyrm = Boss.new(:wyrm, {10, 9}, {0.0, 30.0})
    landed = Boss.step(%{wyrm | state: :arc, t: 1.2, head: {10.5, 5.0}}, @dt, {14.0, 10.0})

    assert landed.state == :stuck
    assert Boss.strike(landed) == nil
    assert Boss.opening?(landed)

    hero = %{standing() | body: %{standing().body | x: landed.x - 1.5}, facing: 1}
    {box, _data} = Hero.strike(%{hero | state: {:move, :jab, 0.07}})
    {l1, t1, r1, b1} = box
    {l2, t2, r2, b2} = Boss.hurtbox(landed)
    assert l1 < r2 and r1 > l2 and t1 < b2 and b1 > t2

    assert Boss.step(%{landed | t: 1.4}, @dt, {14.0, 10.0}).state == :under
  end

  test "every region's opening scene is drawn from the view the game sends" do
    Beast.Art.install()

    for number <- 1..Region.count() do
      {:ok, world} = Game.join(Game.init(region: number), :p, %{username: "p"})
      assert %{layers: [_ | _]} = Beast.Scene.build(Game.view(world, :p), %{})
    end
  end

  test "a beast running into the arena gets wholly past the gates before they shut" do
    {:ok, world} = Game.join(Game.init(region: 3), :p, %{username: "p"})
    gate = Region.arena(world.region)
    {_x, y} = world.region.start
    hero = world.heroes.p
    world = %{world | heroes: %{p: %{hero | body: %{hero.body | x: gate - 2.0, y: y + 1.0}}}}

    ran =
      Enum.reduce(1..50, world, fn _step, acc ->
        acc |> Game.handle_input(:p, %{held: MapSet.new([:right])}) |> Game.step(@dt)
      end)

    assert ran.gated?
    assert ran.heroes.p.body.x - ran.heroes.p.body.w / 2 > gate + 1.0
  end

  test "a winded troll takes double harm" do
    troll = Boss.new(:troll, {10, 10}, {0.0, 30.0})
    assert Boss.struck(%{troll | state: :tired}, 3).hp == troll.max - 6
    assert Boss.struck(troll, 3).hp == troll.max - 3
  end

  test "spikes are stood on, and hurt" do
    {:ok, world} = Game.join(Game.init([]), :p, %{username: "p"})
    [{x, y} | _] = for {at, :spikes} <- world.region.tiles, do: at
    assert Region.grid(world.region, false, false).({x, y}) == :solid

    hero = world.heroes.p
    world = %{world | heroes: %{p: %{hero | body: %{hero.body | x: x + 0.5, y: y / 1, vy: 0.0}}}}
    assert Game.step(world, @dt).heroes.p.health < hero.health
  end
end
