defmodule Beast.Bosses.Mage do
  @moduledoc """
  Zelek, the mage who made the beast. He stands on one perch of his hall
  (`:appear`), casts two slow orbs that drift after the beast (`:cast`), calls lightning
  where the beast stands — the floor flickers first (`:pillar_windup`) — and vanishes to
  another perch (`:vanish`). Struck three times on a perch, he vanishes at once; raging,
  he calls a bat as he goes. While he calls the lightning he cannot move: that is the
  time to reach him.
  """

  @doc false
  def init({x, y}),
    do: %{
      hp: 50,
      max: 50,
      state: :appear,
      perches: [{x, y}, {x - 8, y - 4}, {x + 8, y - 4}, {x, y - 8}],
      perch: 0,
      spot: nil
    }

  @doc false
  def think(%{state: :appear, t: t} = boss, _dt, _target) when t >= 0.5,
    do: %{boss | state: :cast, t: 0.0}

  def think(%{state: :cast, t: t} = boss, _dt, _target) when t >= 1.1,
    do: %{boss | state: :pillar_windup, t: 0.0, shots: orbs(boss)}

  def think(%{state: :pillar_windup, t: t} = boss, _dt, _target) when t >= 1.0,
    do: %{boss | state: :pillar, t: 0.0}

  def think(%{state: :pillar_windup, spot: nil} = boss, _dt, {tx, _ty}), do: %{boss | spot: tx}
  def think(%{state: :pillar, t: t} = boss, _dt, _target) when t >= 0.35, do: vanish(boss)
  def think(%{state: :vanish, t: t} = boss, _dt, _target) when t >= 0.45, do: appear(boss)
  def think(boss, _dt, _target), do: boss

  defp vanish(boss) do
    spawns =
      if Beast.Boss.raging?(boss), do: [{:bat, {round(boss.x), round(boss.y) - 3}}], else: []

    %{boss | state: :vanish, t: 0.0, spot: nil, hits: 0, spawns: spawns}
  end

  defp appear(boss) do
    perch = rem(boss.perch + 1 + rem(round(boss.hp), 2), length(boss.perches))
    {x, y} = Enum.at(boss.perches, perch)
    %{boss | state: :appear, t: 0.0, perch: perch, x: x, y: y}
  end

  defp orbs(boss) do
    for vx <- [-3.0, 3.0],
        do: %{x: boss.x + vx / 3, y: boss.y - 2.0, vx: vx, vy: -1.0, kind: :orb, damage: 1}
  end

  @doc false
  def strike(%{state: :pillar, spot: x}) when is_number(x),
    do: {{x - 0.7, -1.0e6, x + 0.7, 1.0e6}, 2}

  def strike(_boss), do: nil

  @doc false
  def hurtbox(%{state: :vanish}), do: nil
  def hurtbox(boss), do: {boss.x - 0.6, boss.y - 2.6, boss.x + 0.6, boss.y}

  @doc false
  def armoured?(_boss), do: false

  @doc false
  def weakness(_boss), do: 1

  @doc false
  def wounded(%{hits: hits} = boss) when hits >= 3, do: vanish(boss)
  def wounded(boss), do: boss

  @doc false
  def opening?(%{state: state}), do: state in [:pillar_windup, :pillar]
end
