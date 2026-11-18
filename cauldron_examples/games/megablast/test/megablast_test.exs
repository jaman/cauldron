defmodule MegablastTest do
  use ExUnit.Case, async: true

  alias Megablast.{Boss, Game, Ship, Shop, Stages, Tuning, Weapons}

  @tuning Tuning.new()

  test "a boss's core is armoured until its parts are broken" do
    boss = Boss.new(Stages.design(:hive_mother), {13.0, 0.0})
    assert {_boss, :rang} = Boss.strike(boss, :core, 5)

    {boss, :broken} = Boss.strike(boss, :left_sac, 99)
    {boss, :broken} = Boss.strike(boss, :right_sac, 99)
    assert {boss, :struck} = Boss.strike(boss, :core, 5)
    assert {_boss, :beaten} = Boss.strike(boss, :core, 999)
  end

  test "a chain of kills grows the multiplier, and it lapses when the kills stop" do
    ship = Ship.new(:p, "p", {13.0, 0.0}, @tuning, false)
    chained = Enum.reduce(1..9, ship, fn _kill, acc -> Ship.credit(acc, 100, 0, @tuning) end)

    assert chained.score == 100 * 4 + 100 * 2 * 5
    assert Ship.multiplier(chained, @tuning) == 3

    lane = Megablast.Lane.new()
    lapsed = Ship.fly(chained, 2.0, %{depth: 0.0, scroll: 0.0, lane: lane, tuning: @tuning})
    assert lapsed.chain == 0
  end

  test "the shop sells a weapon's next level at its price, and no further than its last" do
    pilot = %{credits: 1000, kit: Weapons.start(), shields: 1, lives: 3}
    assert Shop.price(:main, pilot.kit) == 60

    pilot =
      Enum.reduce(1..3, pilot, fn _level, acc ->
        {:ok, bought} = Shop.buy(acc, :main, 3)
        bought
      end)

    assert pilot.kit.main == 4
    assert pilot.credits == 1000 - 60 - 120 - 200
    assert {:refused, ^pilot} = Shop.buy(pilot, :main, 3)
  end

  test "losing a ship costs a level of every weapon, none below its first" do
    kit = %{Weapons.start() | main: 3, laser: 1, bombs: 0}
    assert %{main: 2, laser: 0, bombs: 1} = Weapons.lost(kit)
  end

  test "the guardian comes half way up the first stage" do
    {:ok, world} = Game.join(Game.init([]), :p, %{username: "p"})
    world = %{world | pilots: %{p: %{world.pilots.p | hurt: 999.0}}}
    {at, _design, _hp} = Stages.stage(1).guardian
    seconds = (at + 1) / Cauldron.Tuning.get(@tuning, :scroll)
    flown = Enum.reduce(1..round(seconds * 50), world, fn _tick, w -> Game.step(w, 1 / 50) end)

    assert flown.phase == :boss
    assert flown.boss.design.name == "GUARDIAN"
  end
end
