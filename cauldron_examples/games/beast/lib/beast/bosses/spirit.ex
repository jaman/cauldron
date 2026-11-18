defmodule Beast.Bosses.Spirit do
  @moduledoc """
  The spirit of the great tree, a face in the bark. It cannot move, so it reaches: the
  ground glows where the beast stands (`:roots_windup`) and roots burst up there
  (`:roots`) — twice, three times raging; then it spits three seeds that arc over
  (`:seeds`), and its face is open (`:open`) a while after. Only then do blows hurt it.
  """

  @doc false
  def init(_at), do: %{hp: 44, max: 44, state: :rest, rooted: 0, spot: nil}

  @doc false
  def think(%{state: :rest, t: t} = boss, _dt, {tx, _ty}) when t >= 0.8,
    do: %{boss | state: :roots_windup, t: 0.0, spot: tx}

  def think(%{state: :roots_windup, t: t} = boss, _dt, _target) when t >= 0.9,
    do: %{boss | state: :roots, t: 0.0}

  def think(%{state: :roots, t: t} = boss, _dt, {tx, _ty}) when t >= 0.35 do
    rooted = boss.rooted + 1
    volleys = if Beast.Boss.raging?(boss), do: 3, else: 2

    if rooted >= volleys,
      do: %{boss | state: :seeds, t: 0.0, rooted: 0, shots: seeds(boss, tx)},
      else: %{boss | state: :roots_windup, t: 0.0, rooted: rooted, spot: tx}
  end

  def think(%{state: :seeds, t: t} = boss, _dt, _target) when t >= 0.5,
    do: %{boss | state: :open, t: 0.0}

  def think(%{state: :open, t: t} = boss, _dt, _target) when t >= 2.2,
    do: %{boss | state: :rest, t: 0.0}

  def think(boss, _dt, _target), do: boss

  defp seeds(boss, tx) do
    for spread <- [-0.35, 0.0, 0.35] do
      reach = (tx - boss.x) / 1.1

      %{
        x: boss.x,
        y: boss.ground - 3.0,
        vx: reach * (1.0 + spread),
        vy: -9.0,
        kind: :seed,
        damage: 1
      }
    end
  end

  @doc false
  def strike(%{state: :roots, spot: x}), do: {{x - 0.8, -1.0e6, x + 0.8, 1.0e6}, 2}
  def strike(_boss), do: nil

  @doc false
  def hurtbox(boss), do: {boss.x - 1.6, boss.ground - 5.0, boss.x + 1.6, boss.ground - 1.0}

  @doc false
  def armoured?(%{state: :open}), do: false
  def armoured?(_boss), do: true

  @doc false
  def weakness(_boss), do: 1

  @doc false
  def wounded(boss), do: boss

  @doc false
  def opening?(%{state: :open}), do: true
  def opening?(_boss), do: false
end
