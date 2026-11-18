defmodule Beast.Bosses.Wyrm do
  @moduledoc """
  The sand wyrm of the red plain. It swims under the ground after the beast, a trail of
  dust above it (`:under`); stops and the ground shakes (`:rise`); erupts straight up
  (`:erupt`), striking a column; arcs through the air to dive again (`:arc`); and lies
  dazed where it lands, its head in the ground (`:stuck`), harmless, until it burrows
  again. It can be hurt only while it is out of the ground, and most safely while dazed.
  Raging, it hunts faster and is dazed for less.
  """

  alias Beast.Boss

  @doc false
  def init(_at), do: %{hp: 30, max: 30, state: :under, head: nil}

  @doc false
  def think(%{state: :under} = boss, dt, {tx, _ty}) do
    hunt = if Boss.raging?(boss), do: 0.9, else: 1.4
    {left, right} = boss.arena

    x =
      clamp(boss.x + sign(tx - boss.x) * min(abs(tx - boss.x), 5.0 * dt), left + 1.5, right - 1.5)

    if boss.t >= hunt, do: %{boss | x: x, state: :rise, t: 0.0}, else: %{boss | x: x}
  end

  def think(%{state: :rise} = boss, _dt, _target) when boss.t >= 0.4,
    do: %{boss | state: :erupt, t: 0.0}

  def think(%{state: :rise} = boss, _dt, _target), do: boss

  def think(%{state: :erupt} = boss, _dt, {tx, _ty}) when boss.t >= 0.55,
    do: %{
      boss
      | state: :arc,
        t: 0.0,
        facing: if(tx < boss.x, do: -1, else: 1),
        head: {boss.x, boss.ground - 4.0}
    }

  def think(%{state: :erupt} = boss, _dt, _target),
    do: %{boss | head: {boss.x, boss.ground - 4.0 * min(1.0, boss.t / 0.2)}}

  def think(%{state: :arc} = boss, _dt, _target) when boss.t >= 1.2,
    do: %{boss | state: :stuck, t: 0.0, head: {boss.x, boss.ground - 1.5}}

  def think(%{state: :stuck} = boss, _dt, _target) do
    dazed = if Boss.raging?(boss), do: 1.0, else: 1.4
    if boss.t >= dazed, do: %{boss | state: :under, t: 0.0, head: nil}, else: boss
  end

  def think(%{state: :arc} = boss, dt, _target) do
    {left, right} = boss.arena
    x = clamp(boss.x + boss.facing * 6.0 * dt, left + 1.0, right - 1.0)
    rise = :math.sin(boss.t / 1.2 * :math.pi()) * 5.0
    %{boss | x: x, head: {x, boss.ground - 1.0 - rise}}
  end

  @doc false
  def strike(%{state: :erupt, t: t} = boss) when t < 0.3,
    do: {{boss.x - 1.0, boss.ground - 5.0, boss.x + 1.0, boss.ground}, 2}

  def strike(%{state: :arc, head: {x, y}}), do: {{x - 1.0, y - 1.0, x + 1.0, y + 1.0}, 2}
  def strike(_boss), do: nil

  @doc false
  def hurtbox(%{state: :stuck, head: {x, _y}} = boss),
    do: {x - 1.2, boss.ground - 2.8, x + 1.2, boss.ground}

  def hurtbox(%{state: state, head: {x, y}}) when state in [:erupt, :arc],
    do: {x - 1.1, y - 1.1, x + 1.1, y + 1.1}

  def hurtbox(_boss), do: nil

  @doc false
  def armoured?(_boss), do: false

  @doc false
  def weakness(_boss), do: 1

  @doc false
  def wounded(boss), do: boss

  @doc false
  def opening?(%{state: :stuck}), do: true
  def opening?(_boss), do: false

  defp clamp(v, low, high), do: v |> max(low) |> min(high)
  defp sign(d) when d < 0, do: -1
  defp sign(_d), do: 1
end
