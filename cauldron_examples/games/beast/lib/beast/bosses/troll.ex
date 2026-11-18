defmodule Beast.Bosses.Troll do
  @moduledoc """
  The cave troll in the well. It lumbers after the beast and picks its blow by how far
  off the beast is: close, it draws back (`:sweep_windup`) and sweeps low (`:sweep`) —
  jump it; further, it raises both fists (`:slam_windup`) and slams (`:slam`), sending a
  shockwave along the ground each way — jump them; far, it lowers its head
  (`:charge_windup`) and charges (`:charge`) — roll through it — and is left winded
  (`:tired`), when blows do it double harm.
  """

  @doc false
  def init(_at), do: %{hp: 40, max: 40, state: :walk, rest: 1.0}

  @doc false
  def think(%{state: :walk} = boss, dt, {tx, _ty}) do
    facing = if tx < boss.x, do: -1, else: 1
    distance = abs(tx - boss.x)
    rest = boss.rest - dt

    cond do
      rest > 0 -> %{boss | x: boss.x + facing * 2.2 * dt, facing: facing, rest: rest}
      distance < 3 -> %{boss | state: :sweep_windup, t: 0.0, facing: facing}
      distance < 8 -> %{boss | state: :slam_windup, t: 0.0, facing: facing}
      true -> %{boss | state: :charge_windup, t: 0.0, facing: facing}
    end
  end

  def think(%{state: :sweep_windup, t: t} = boss, _dt, _target) when t >= 0.6,
    do: %{boss | state: :sweep, t: 0.0}

  def think(%{state: :sweep, t: t} = boss, _dt, _target) when t >= 0.25, do: rest(boss, 0.7)

  def think(%{state: :slam_windup, t: t} = boss, _dt, _target) when t >= 0.8,
    do: %{boss | state: :slam, t: 0.0, shots: waves(boss)}

  def think(%{state: :slam, t: t} = boss, _dt, _target) when t >= 0.4, do: rest(boss, 0.8)

  def think(%{state: :charge_windup, t: t} = boss, _dt, _target) when t >= 0.5,
    do: %{boss | state: :charge, t: 0.0}

  def think(%{state: :charge} = boss, dt, _target) do
    {left, right} = boss.arena
    x = boss.x + boss.facing * 14.0 * dt

    if boss.t >= 1.4 or x < left + 1.5 or x > right - 1.5,
      do: %{boss | state: :tired, t: 0.0, x: x |> max(left + 1.5) |> min(right - 1.5)},
      else: %{boss | x: x}
  end

  def think(%{state: :tired, t: t} = boss, _dt, _target) when t >= 1.3, do: rest(boss, 0.5)
  def think(boss, _dt, _target), do: boss

  defp rest(boss, seconds), do: %{boss | state: :walk, t: 0.0, rest: seconds}

  defp waves(boss) do
    for direction <- [-1, 1],
        do: %{
          x: boss.x + direction * 1.5,
          y: boss.ground - 0.4,
          vx: direction * 9.0,
          vy: 0.0,
          kind: :wave,
          damage: 2
        }
  end

  @doc false
  def strike(%{state: :sweep} = boss) do
    far = boss.x + boss.facing * 3.2
    {{min(boss.x, far), boss.ground - 1.0, max(boss.x, far), boss.ground}, 2}
  end

  def strike(%{state: :charge} = boss),
    do: {{boss.x - 1.4, boss.ground - 3.4, boss.x + 1.4, boss.ground}, 2}

  def strike(_boss), do: nil

  @doc false
  def hurtbox(boss), do: {boss.x - 1.3, boss.ground - 3.6, boss.x + 1.3, boss.ground}

  @doc false
  def armoured?(_boss), do: false

  @doc false
  def weakness(%{state: :tired}), do: 2
  def weakness(_boss), do: 1

  @doc false
  def wounded(boss), do: boss

  @doc false
  def opening?(%{state: :tired}), do: true
  def opening?(_boss), do: false
end
