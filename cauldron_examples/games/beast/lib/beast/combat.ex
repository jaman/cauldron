defmodule Beast.Combat do
  @moduledoc """
  Every blow in a region and what it costs, each answering the world and its events,
  newest first.

    * `blows/1` — the beasts' active blows on creatures and the boss: once a blow, thrown
      back by its weight, the world held still a moment and shaken (`Cauldron.Impact`);
      a blow also breaks the orbs and seeds it meets (arrows and shockwaves it cannot)
    * `wounds/1` — creatures' and the boss's attacks, and missiles, on the beasts
    * `ground/1` — spikes, and falling out of the world: a fall brings a beast back at
      its last standing stone
    * `finds/1` — fruit that heals, the key that opens the region's doors, and the
      standing stones that keep a beast's place
  """

  alias Beast.{Boss, Creature, Hero, Region}
  alias Cauldron.{Impact, Tuning}
  alias Cauldron2D.{Box, BoxBody}

  @fruit 2
  @breakable [:orb, :seed]

  @doc "The world after the beasts' blows land."
  @spec blows({map(), [term()]}) :: {map(), [term()]}
  def blows({world, events}) do
    Enum.reduce(world.heroes, {world, events}, fn {id, _hero}, acc -> blow(acc, id) end)
  end

  defp blow({world, _events} = acc, id) do
    hero = Map.fetch!(world.heroes, id)

    case Hero.strike(hero) do
      nil ->
        acc

      {box, data} ->
        acc |> creatures_struck(id, box, data) |> boss_struck(id, box, data) |> broken(box)
    end
  end

  defp broken({world, events}, box) do
    {hit, flying} =
      Enum.split_with(
        world.missiles,
        &(&1.kind in @breakable and Box.overlap?(box, Box.around({&1.x, &1.y}, 0.3)))
      )

    {%{world | missiles: flying}, Enum.map(hit, &{:thud, {&1.x, &1.y}}) ++ events}
  end

  defp creatures_struck({world, events}, id, box, data) do
    hero = Map.fetch!(world.heroes, id)

    struck =
      Enum.filter(world.creatures, fn c ->
        c.state != :dead and not MapSet.member?(hero.landed, c.id) and
          Box.overlap?(box, BoxBody.box(c.body))
      end)

    Enum.reduce(struck, {world, events}, fn creature, {w, e} ->
      hit = Creature.struck(creature, data.damage, data.knock, hero.facing)
      landed = Map.update!(w.heroes, id, &%{&1 | landed: MapSet.put(&1.landed, creature.id)})

      w = %{
        w
        | creatures: replace(w.creatures, hit),
          heroes: landed,
          impact: Impact.freeze(w.impact, stop(w, data))
      }

      at = {creature.body.x, creature.body.y - creature.body.h / 2}
      e = if hit.state == :dead, do: [{:kill, at} | e], else: [{:thud, at} | e]
      {score(w, id, hit), e}
    end)
  end

  defp score(world, id, %{state: :dead, kind: kind}),
    do: %{
      world
      | heroes:
          Map.update!(
            world.heroes,
            id,
            &Map.update(&1, :score, Creature.worth(kind), fn s -> s + Creature.worth(kind) end)
          )
    }

  defp score(world, _id, _creature), do: world

  defp boss_struck({%{boss: nil} = world, events}, _id, _box, _data), do: {world, events}

  defp boss_struck({world, events}, id, box, data) do
    hero = Map.fetch!(world.heroes, id)
    hurtbox = Boss.hurtbox(world.boss)

    cond do
      hurtbox == nil or MapSet.member?(hero.landed, :boss) or not Box.overlap?(box, hurtbox) ->
        {world, events}

      Boss.armoured?(world.boss) ->
        {mark(world, id), [{:clang, centre(hurtbox)} | events]}

      true ->
        boss = Boss.struck(world.boss, data.damage)

        world = %{
          mark(world, id)
          | boss: boss,
            impact: world.impact |> Impact.freeze(stop(world, data) * 1.6) |> Impact.shake(0.25)
        }

        {world,
         [
           if(boss.state == :dead, do: {:felled, centre(hurtbox)}, else: {:thud, centre(hurtbox)})
           | events
         ]}
    end
  end

  defp mark(world, id),
    do: %{
      world
      | heroes: Map.update!(world.heroes, id, &%{&1 | landed: MapSet.put(&1.landed, :boss)})
    }

  defp stop(world, data), do: Tuning.get(world.tuning, :stop) * (1 + data.damage / 2)

  @doc "The world after attacks and missiles reach the beasts."
  @spec wounds({map(), [term()]}) :: {map(), [term()]}
  def wounds({world, events}) do
    attacks =
      for(c <- world.creatures, strike = Creature.strike(c), do: {strike, c.body.x}) ++
        if(world.boss && Boss.strike(world.boss),
          do: [{Boss.strike(world.boss), world.boss.x}],
          else: []
        )

    Enum.reduce(world.heroes, {world, events}, fn {id, hero}, acc ->
      if Hero.open?(hero), do: wounded(acc, id, hero, attacks), else: acc
    end)
  end

  defp wounded({world, events}, id, hero, attacks) do
    body = BoxBody.box(hero.body)
    attack = Enum.find(attacks, fn {{box, _damage}, _x} -> Box.overlap?(box, body) end)
    missile = Enum.find(world.missiles, &Box.overlap?(Box.around({&1.x, &1.y}, 0.3), body))

    cond do
      attack ->
        hurt({world, events}, id, hero, attack |> elem(0) |> elem(1), side(elem(attack, 1), hero))

      missile ->
        hurt(
          {%{world | missiles: List.delete(world.missiles, missile)}, events},
          id,
          hero,
          missile.damage,
          side(missile.x, hero)
        )

      true ->
        {world, events}
    end
  end

  defp hurt({world, events}, id, hero, damage, from) do
    hurt = Hero.wound(hero, damage, from, world.tuning)

    world = %{
      world
      | heroes: Map.put(world.heroes, id, hurt),
        impact: world.impact |> Impact.shake(0.3) |> Impact.freeze(0.08)
    }

    {world,
     [
       if(hurt.state == :dead,
         do: {:fallen, id},
         else: {:wounded, {hero.body.x, hero.body.y - 1.3}}
       )
       | events
     ]}
  end

  defp side(x, hero), do: if(x < hero.body.x, do: -1, else: 1)

  @doc "The world after spikes and falls."
  @spec ground({map(), [term()]}) :: {map(), [term()]}
  def ground({world, events}) do
    Enum.reduce(world.heroes, {world, events}, fn {id, hero}, {w, e} ->
      cond do
        hero.body.y > w.region.height + 3 ->
          {revive(w, id, hero), [{:fall, id} | e]}

        Hero.open?(hero) and
            Region.spikes?(w.region, BoxBody.tiles(%{hero.body | y: hero.body.y + 0.05})) ->
          hurt({w, e}, id, %{hero | body: %{hero.body | vy: -14.0}}, 2, -hero.facing)

        true ->
          {w, e}
      end
    end)
  end

  @doc "The world with any beast that has fallen dead brought back at its standing stone."
  @spec revive(map(), term(), map()) :: map()
  def revive(world, id, hero),
    do: %{world | heroes: Map.put(world.heroes, id, Hero.revive(hero, world.tuning))}

  @doc "The world after the beasts find fruit, the key and standing stones."
  @spec finds({map(), [term()]}) :: {map(), [term()]}
  def finds({world, events}) do
    Enum.reduce(world.heroes, {world, events}, fn {id, hero}, acc ->
      acc |> fruit(id, hero) |> key(hero) |> stone(id, hero)
    end)
  end

  defp fruit({world, events}, id, hero) do
    case Enum.find(world.fruit, &BoxBody.covers?(hero.body, &1)) do
      nil ->
        {world, events}

      at ->
        healed = %{hero | health: min(Tuning.get(world.tuning, :health), hero.health + @fruit)}

        {%{
           world
           | fruit: List.delete(world.fruit, at),
             heroes: Map.put(world.heroes, id, healed)
         }, [{:eat, at} | events]}
    end
  end

  defp key({world, events}, hero) do
    case Enum.find(world.keys, &BoxBody.covers?(hero.body, &1)) do
      nil ->
        {world, events}

      at ->
        {%{world | keys: List.delete(world.keys, at), doors_open?: true}, [{:key, at} | events]}
    end
  end

  defp stone({world, events}, id, hero) do
    case Enum.find(world.region.stones, &BoxBody.covers?(hero.body, &1)) do
      {x, y} = at ->
        kept = %{hero | stone: {x + 0.5, y + 1.0}}

        if kept.stone == hero.stone,
          do: {world, events},
          else: {%{world | heroes: Map.put(world.heroes, id, kept)}, [{:stone, at} | events]}

      _none ->
        {world, events}
    end
  end

  defp centre({l, t, r, b}), do: {(l + r) / 2, (t + b) / 2}

  defp replace(list, item), do: Enum.map(list, &if(&1.id == item.id, do: item, else: &1))
end
