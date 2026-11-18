defmodule Megablast.Combat do
  @moduledoc """
  Every strike in the lane and what it costs: the ships' shots against foes and boss
  pieces, enemy bullets and foes' bodies against ships, credit bubbles gathered, and the
  bombs. Each answers the world and its events, newest first.

  A kill scores its foe's points times the killer's chain multiplier, and drops a credit
  bubble for every credit the foe is worth; any ship may gather them. A boss part broken
  or a boss beaten stops the world a moment and shakes the view (`Cauldron.Impact`).
  """

  alias Cauldron.{Impact, Tuning}
  alias Cauldron2D.{Box, Projectiles}
  alias Megablast.{Boss, Foe, Ship}

  @shot_reach 0.35
  @gather 1.1
  @bomb_damage 6

  @doc "The world after the ships' shots strike."
  @spec shots({map(), [term()]}) :: {map(), [term()]}
  def shots({world, events}) do
    {{world, events}, shots} =
      Projectiles.resolve(world.shots, {world, events}, &struck/2, &hit/3)

    {%{world | shots: shots}, events}
  end

  defp hit(acc, shot, {:foe, foe}), do: foe_struck(acc, shot, foe)
  defp hit(acc, shot, {:piece, piece}), do: piece_struck(acc, shot, piece)

  defp struck({world, _events}, shot) do
    foe =
      Enum.find(world.foes, fn foe ->
        not Projectiles.struck?(shot, foe.id) and near?(foe, shot, Foe.radius(foe) + @shot_reach)
      end)

    cond do
      foe -> {foe.id, {:foe, foe}}
      world.boss && not Projectiles.struck?(shot, :boss) -> piece(world.boss, shot)
      true -> nil
    end
  end

  defp piece(boss, shot) do
    case Enum.find(Boss.pieces(boss), &near?(&1, shot, &1.radius + @shot_reach)) do
      nil -> nil
      piece -> {:boss, {:piece, piece}}
    end
  end

  defp foe_struck({world, events}, shot, foe) do
    hp = foe.hp - shot.damage

    if hp > 0 do
      {%{world | foes: replace(world.foes, %{foe | hp: hp, hit: 0.1})}, events}
    else
      killed({world, events}, foe, shot.by)
    end
  end

  @doc "The world after foe `foe` is killed by pilot `by` (or `nil`, a bomb with no owner)."
  @spec killed({map(), [term()]}, map(), term()) :: {map(), [term()]}
  def killed({world, events}, foe, by) do
    %{points: points, credits: credits} = Foe.worth(foe.kind)
    bubbles = for index <- 1..credits//1, do: %{x: foe.x + (index - 1) * 0.5, y: foe.y, age: 0.0}
    remains = foe |> Foe.remains() |> Enum.map(&Map.put(&1, :id, {foe.id, &1.x}))

    world = %{
      world
      | foes: remains ++ Enum.reject(world.foes, &(&1.id == foe.id)),
        pickups: bubbles ++ world.pickups,
        blasts: [%{x: foe.x, y: foe.y, age: 0.0, size: blast_size(foe.kind)} | world.blasts],
        pilots: credit(world.pilots, by, points, world.tuning)
    }

    {world, [{:boom, {foe.x, foe.y}} | events]}
  end

  defp blast_size(kind) when kind in [:shell, :orb], do: :big
  defp blast_size(_kind), do: :small

  defp credit(pilots, nil, _points, _tuning), do: pilots

  defp credit(pilots, by, points, tuning) do
    case Map.fetch(pilots, by) do
      {:ok, ship} -> Map.put(pilots, by, Ship.credit(ship, points, 0, tuning))
      :error -> pilots
    end
  end

  defp piece_struck({world, events}, shot, piece) do
    {boss, result} = Boss.strike(world.boss, piece.name, shot.damage)
    world = %{world | boss: boss}

    case result do
      :rang -> {world, [{:clang, {piece.x, piece.y}} | events]}
      :struck -> {world, events}
      :broken -> broken({world, events}, piece, shot.by)
      :beaten -> beaten({world, events}, piece, shot.by)
    end
  end

  defp broken({world, events}, piece, by) do
    world = %{
      world
      | impact: world.impact |> Impact.freeze(0.1) |> Impact.shake(0.45),
        blasts: [%{x: piece.x, y: piece.y, age: 0.0, size: :big} | world.blasts],
        pickups:
          for(i <- 1..4, do: %{x: piece.x + i - 2.5, y: piece.y, age: 0.0}) ++ world.pickups,
        pilots: credit(world.pilots, by, 1500, world.tuning)
    }

    {world, [{:blast, {piece.x, piece.y}} | events]}
  end

  defp beaten({world, events}, piece, by) do
    blasts =
      for dx <- [-2, 0, 2],
          dy <- [-1, 1],
          do: %{x: piece.x + dx, y: piece.y + dy, age: -abs(dx) * 0.08, size: :big}

    world = %{
      world
      | impact: world.impact |> Impact.freeze(0.28) |> Impact.shake(0.9),
        blasts: blasts ++ world.blasts,
        bullets: [],
        pickups:
          for(i <- 1..10, do: %{x: piece.x + i / 2 - 2.75, y: piece.y, age: 0.0}) ++ world.pickups,
        pilots: credit(world.pilots, by, 10_000, world.tuning)
    }

    {world, [{:beaten, {piece.x, piece.y}} | events]}
  end

  @doc "The world after enemy bullets and foes' bodies strike the ships."
  @spec ships({map(), [term()]}) :: {map(), [term()]}
  def ships({world, events}) do
    hitbox = Tuning.get(world.tuning, :hitbox)

    Enum.reduce(world.pilots, {world, events}, fn {id, ship}, acc ->
      if Ship.open?(ship), do: ship_struck(acc, id, ship, hitbox), else: acc
    end)
  end

  defp ship_struck({world, events}, id, ship, hitbox) do
    bullet = Enum.find(world.bullets, &near?(&1, ship, hitbox + 0.15))
    body = Enum.find(world.foes, &near?(&1, ship, Foe.radius(&1) + hitbox))

    cond do
      bullet -> hurt({%{world | bullets: List.delete(world.bullets, bullet)}, events}, id, ship)
      body -> {world, events} |> hurt(id, ship) |> foe_struck(%{damage: 3, by: id}, body)
      true -> {world, events}
    end
  end

  defp hurt({world, events}, id, ship) do
    {ship, result} = Ship.hit(ship, world.tuning)

    world = %{
      world
      | pilots: Map.put(world.pilots, id, ship),
        impact: Impact.shake(world.impact, 0.3)
    }

    case result do
      :hurt ->
        {world, [{:hurt, {ship.x, ship.y}} | events]}

      :lost ->
        {%{
           world
           | impact: Impact.freeze(world.impact, 0.16),
             blasts: [%{x: ship.x, y: ship.y, age: 0.0, size: :big} | world.blasts]
         }, [{:lost, {ship.x, ship.y}} | events]}

      :out ->
        {world, [{:out, id} | events]}
    end
  end

  @doc "The world after the ships gather the credit bubbles they touch."
  @spec gather({map(), [term()]}) :: {map(), [term()]}
  def gather({world, events}) do
    Enum.reduce(world.pickups, {%{world | pickups: []}, events}, &gather_bubble/2)
  end

  @doc "The world after pilot `by`'s bomb: every bullet gone, every foe in view struck, the boss struck."
  @spec bomb({map(), [term()]}, term(), {number(), number()}) :: {map(), [term()]}
  def bomb({world, events}, by, {top, bottom}) do
    in_view = Enum.filter(world.foes, &(&1.y >= top and &1.y <= bottom))

    acc =
      {%{world | bullets: [], impact: Impact.shake(world.impact, 0.7)}, [{:bomb, by} | events]}

    acc =
      Enum.reduce(in_view, acc, fn foe, {w, e} ->
        case Enum.find(w.foes, &(&1.id == foe.id)) do
          nil -> {w, e}
          current -> foe_struck({w, e}, %{damage: @bomb_damage, by: by}, current)
        end
      end)

    bomb_boss(acc, by)
  end

  defp bomb_boss({%{boss: nil} = world, events}, _by), do: {world, events}

  defp bomb_boss({world, events}, by) do
    Enum.reduce(Boss.pieces(world.boss), {world, events}, fn piece, acc ->
      if piece.armoured?, do: acc, else: piece_struck(acc, %{damage: 4, by: by}, piece)
    end)
  end

  defp gather_bubble(bubble, {world, events}) do
    case Enum.find(world.pilots, &gathers?(&1, bubble)) do
      nil ->
        {%{world | pickups: [bubble | world.pickups]}, events}

      {id, ship} ->
        {%{world | pilots: Map.put(world.pilots, id, %{ship | credits: ship.credits + 1})},
         [{:pickup, {bubble.x, bubble.y}} | events]}
    end
  end

  defp gathers?({_id, ship}, bubble), do: not ship.out? and near?(bubble, ship, @gather)

  defp near?(a, b, reach), do: Box.contains?(Box.around({b.x, b.y}, reach), {a.x, a.y})

  defp replace(foes, foe), do: Enum.map(foes, &if(&1.id == foe.id, do: foe, else: &1))
end
