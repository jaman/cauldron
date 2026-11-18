defmodule Cauldron2D.ProjectilesTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Projectiles

  defp shot(fields), do: Map.merge(%{x: 0.0, y: 0.0, vx: 0.0, vy: 0.0}, Map.new(fields))

  test "a straight shot moves by its velocity, an arcing one falls after it moves" do
    assert %{x: 1.0, y: 2.0, age: 0.5} = Projectiles.move(shot(vx: 2.0, vy: 4.0), 0.5)

    arc = Projectiles.move(shot(vx: 2.0, vy: -4.0, motion: {:arc, 10.0}), 0.5)
    assert {arc.x, arc.y, arc.vy} == {1.0, -2.0, 1.0}
  end

  test "a homing shot eases its velocity toward its speed at the target, by turn a second" do
    missile = shot(vx: 0.0, vy: -10.0, motion: {:homing, 20.0, 2.0})
    moved = Projectiles.move(missile, 0.25, {10.0, 0.0})

    assert {moved.vx, moved.vy} == {10.0, -5.0}
    assert {moved.x, moved.y} == {2.5, -1.25}
    assert Projectiles.move(missile, 0.25, nil).y == -2.5
  end

  test "step drops shots out of time and those the game no longer keeps" do
    shots = [shot(ttl: 1.0, age: 0.9), shot(ttl: 1.0), shot(x: 5.0)]
    kept = Projectiles.step(shots, 0.2, keep?: &(&1.x < 4.0))
    assert kept == [shot(ttl: 1.0, age: 0.2)]
  end

  test "a hit removes a shot; a piercing shot goes on and hits each thing once, in order" do
    things = %{a: 3, b: 3}

    find = fn things, shot ->
      Enum.find_value([:a, :b], fn id ->
        if things[id] > 0 and not Projectiles.struck?(shot, id), do: {id, id}
      end)
    end

    hit = fn things, shot, id -> Map.update!(things, id, &(&1 - shot.damage)) end

    shots = [shot(damage: 3), shot(damage: 1, pierce?: true)]
    assert {things, [piercing]} = Projectiles.resolve(shots, things, find, hit)
    assert things == %{a: 0, b: 2}
    assert piercing.struck == [:b]

    assert {%{a: 0, b: 2}, [^piercing]} = Projectiles.resolve([piercing], things, find, hit)
  end
end
