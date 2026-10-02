defmodule Megablast.Game do
  @moduledoc """
  The lane the ship flies up: waves of creatures entering in formation, turrets growing
  out of the rock walls, the pods they drop and the shots everyone fires.

  Held `:left` and `:right` steer and bank, `:thrust` and `:brake` move the ship up and
  down the lane; flying to the bottom holds the view back rather than running off it.
  `:fire` shoots, and every pod collected adds a drone to the ship that fires with it.
  A creature, a turret or a shot touching the ship costs a shield.
  """

  @behaviour Cauldron2D.Game

  alias Cauldron2D.Rng
  alias Megablast.{Lane, Tuning, Wave}

  @impl true
  def init(opts) do
    %{
      pilots: %{},
      foes: [],
      shots: [],
      flak: [],
      turrets: [],
      rng: Rng.new(Keyword.get(opts, :seed, 1_989_000)),
      tuning: Tuning.new(Keyword.get(opts, :tuning, [])),
      lane: Lane.new(Keyword.get(opts, :lane, [])),
      shapes: Wave.new(Keyword.get(opts, :waves, [])),
      depth: 0.0,
      waved_to: -ahead(Keyword.get(opts, :tuning, [])),
      waves: 0,
      turret_step: 0,
      events: [],
      ticks: 0
    }
  end

  @doc "The value of a tuning setting, as `Megablast.Tuning` declares them."
  @spec tuning(map(), atom()) :: term()
  def tuning(%{tuning: tuning}, key), do: Cauldron2D.Tuning.get(tuning, key)

  @impl true
  def join(state, id, _props), do: {:ok, put_in(state.pilots[id], pilot(state))}

  @impl true
  def leave(state, id), do: %{state | pilots: Map.delete(state.pilots, id)}

  @impl true
  def handle_input(state, id, %{held: held}) do
    if Map.has_key?(state.pilots, id), do: put_in(state.pilots[id].held, held), else: state
  end

  @impl true
  def step(state, dt) do
    state
    |> fly(dt)
    |> scroll(dt)
    |> shoot()
    |> muster()
    |> man_walls()
    |> fire_walls()
    |> drift(dt)
    |> strike()
    |> collide()
    |> Map.update!(:ticks, &(&1 + 1))
  end

  @impl true
  def view(state, id) do
    %{
      me: Map.get(state.pilots, id),
      depth: state.depth,
      foes: state.foes,
      shots: state.shots,
      flak: state.flak,
      turrets: state.turrets,
      addon_reach: at(state.tuning, :addon_reach),
      lane: state.lane,
      others: for({other, pilot} <- state.pilots, other != id, do: pilot)
    }
  end

  @impl true
  def drain_events(state), do: {Enum.reverse(state.events), %{state | events: []}}

  @doc "Where the ship's drones sit beside it, `reach` tiles apart, for whoever draws them."
  @spec addons(map(), number()) :: [{float(), float()}]
  def addons(%{addons: count, x: x, y: y}, reach) do
    for place <- 1..count//1, reduce: [] do
      acc -> [{x - place * reach, y}, {x + place * reach, y} | acc]
    end
  end

  defp at(tuning, key), do: Cauldron2D.Tuning.get(tuning, key)

  defp ahead(overrides), do: overrides |> Tuning.new() |> at(:wave_ahead)

  defp pilot(state) do
    %{
      x: Lane.middle(state.lane),
      y: state.depth + 6.0,
      bank: 0,
      shields: at(state.tuning, :shields),
      score: 0,
      hurt: 0,
      cooling: 0,
      addons: 0,
      braking?: false,
      held: MapSet.new()
    }
  end

  defp fly(state, dt) do
    Map.update!(state, :pilots, fn pilots ->
      Map.new(pilots, fn {id, pilot} -> {id, steer(pilot, state, dt)} end)
    end)
  end

  defp steer(pilot, state, dt) do
    tuning = state.tuning
    depth = state.depth
    across = direction(pilot.held, :right, :left)
    along = direction(pilot.held, :brake, :thrust)
    margin = at(tuning, :margin)

    y =
      clamp(
        pilot.y + along * at(tuning, :lift) * dt - at(tuning, :scroll) * dt,
        depth - at(tuning, :ceiling),
        depth + at(tuning, :floor)
      )

    {left, right} = Lane.edges(state.lane, y)

    %{
      pilot
      | x: clamp(pilot.x + across * at(tuning, :steer) * dt, left + margin, right - margin),
        y: y,
        bank: bank(pilot.bank, across),
        braking?: along > 0,
        hurt: max(0, pilot.hurt - 1),
        cooling: max(0, pilot.cooling - 1)
    }
  end

  defp direction(held, positive, negative) do
    cond do
      MapSet.member?(held, positive) -> 1
      MapSet.member?(held, negative) -> -1
      true -> 0
    end
  end

  defp bank(current, 0), do: toward(current, 0)
  defp bank(current, across), do: clamp(current + across, -2, 2)

  defp toward(value, target) when value > target, do: value - 1
  defp toward(value, target) when value < target, do: value + 1
  defp toward(value, _target), do: value

  defp scroll(%{pilots: pilots} = state, dt) when map_size(pilots) == 0 do
    %{state | depth: state.depth - at(state.tuning, :scroll) * dt}
  end

  defp scroll(state, dt) do
    lowest = state.pilots |> Map.values() |> Enum.map(& &1.y) |> Enum.max()
    forward = state.depth - at(state.tuning, :scroll) * dt

    held_back =
      min(
        state.depth + at(state.tuning, :push) * dt,
        lowest - at(state.tuning, :reach)
      )

    %{state | depth: max(forward, held_back)}
  end

  defp shoot(state) do
    {pilots, shots} =
      Enum.map_reduce(state.pilots, state.shots, fn {id, pilot}, acc ->
        if pilot.cooling == 0 and MapSet.member?(pilot.held, :fire) do
          drones = addons(pilot, at(state.tuning, :addon_reach))

          nose = [
            {pilot.x, pilot.y - 1.0} | Enum.map(drones, fn {x, y} -> {x, y - 0.8} end)
          ]

          {{id, %{pilot | cooling: at(state.tuning, :reload)}},
           Enum.map(nose, fn {x, y} -> %{x: x, y: y} end) ++ acc}
        else
          {{id, pilot}, acc}
        end
      end)

    %{state | pilots: Map.new(pilots), shots: shots}
  end

  defp muster(state) do
    if state.depth - at(state.tuning, :wave_ahead) < state.waved_to do
      {creatures, rng} =
        Wave.next(state.shapes, state.waves, state.waved_to, state.rng, state.lane)

      %{
        state
        | rng: rng,
          foes: creatures ++ state.foes,
          waves: state.waves + 1,
          waved_to: state.waved_to - at(state.tuning, :wave_gap)
      }
    else
      state
    end
  end

  defp man_walls(state) do
    wanted = Lane.turret_step(state.lane, state.depth - at(state.tuning, :wave_ahead))

    if wanted < state.turret_step do
      grown =
        for step <- wanted..(state.turret_step - 1)//1,
            turret = Lane.turret_of(state.lane, step),
            do: Map.merge(turret, %{cooling: at(state.tuning, :turret_reload), open?: false})

      %{state | turrets: grown ++ state.turrets, turret_step: wanted}
    else
      state
    end
  end

  defp fire_walls(%{pilots: pilots} = state) when map_size(pilots) == 0, do: state

  defp fire_walls(state) do
    target = state.pilots |> Map.values() |> List.first()

    {turrets, flak} =
      Enum.map_reduce(state.turrets, state.flak, fn turret, acc ->
        cond do
          turret.cooling > 0 ->
            {%{turret | cooling: turret.cooling - 1, open?: turret.cooling < 20}, acc}

          abs(turret.y - target.y) > at(state.tuning, :turret_reach) ->
            {%{turret | open?: false}, acc}

          true ->
            {%{turret | cooling: at(state.tuning, :turret_reload), open?: true},
             [bolt(turret, target) | acc]}
        end
      end)

    %{state | turrets: turrets, flak: flak}
  end

  defp bolt(turret, target) do
    {dx, dy} = {target.x - turret.x, target.y - turret.y}
    reach = max(0.001, :math.sqrt(dx * dx + dy * dy))

    %{x: turret.x / 1, y: turret.y / 1, vx: dx / reach, vy: dy / reach}
  end

  defp drift(state, dt) do
    behind = state.depth + at(state.tuning, :behind)
    ahead = state.depth - at(state.tuning, :wave_ahead) - at(state.tuning, :wave_gap)
    shot_speed = at(state.tuning, :shot_speed)
    flak_speed = at(state.tuning, :flak_speed)

    %{
      state
      | foes: state.foes |> Enum.map(&Wave.fly(&1, dt)) |> Enum.filter(&(&1.y < behind)),
        shots:
          state.shots
          |> Enum.map(&%{&1 | y: &1.y - shot_speed * dt})
          |> Enum.filter(&(&1.y > ahead)),
        flak:
          state.flak
          |> Enum.map(&sail(&1, flak_speed, dt))
          |> Enum.filter(&inside?(&1, ahead, behind, state.lane)),
        turrets: Enum.filter(state.turrets, &(&1.y < behind))
    }
  end

  defp sail(bolt, speed, dt),
    do: %{bolt | x: bolt.x + bolt.vx * speed * dt, y: bolt.y + bolt.vy * speed * dt}

  defp inside?(bolt, ahead, behind, lane),
    do: bolt.y > ahead and bolt.y < behind and Lane.open?(lane, bolt.x, bolt.y)

  defp strike(state) do
    {foes, shots, downed} = shoot_down(state.foes, state.shots)
    {turrets, shots, wrecked} = shoot_down(state.turrets, shots)
    {pods, rng} = drops(downed, state.rng)

    state
    |> Map.put(:foes, pods ++ foes)
    |> Map.put(:turrets, turrets)
    |> Map.put(:shots, shots)
    |> Map.put(:rng, rng)
    |> award(length(downed) * 25 + length(wrecked) * 60)
    |> note(length(downed) + length(wrecked))
  end

  defp shoot_down(targets, shots) do
    Enum.reduce(targets, {[], shots, []}, fn target, {kept, left, downed} ->
      case Enum.split_with(left, &near?(&1, target, 1.0)) do
        {[], _rest} -> {[target | kept], left, downed}
        {_hit, rest} -> {kept, rest, [target | downed]}
      end
    end)
  end

  defp drops(downed, rng) do
    Enum.reduce(downed, {[], rng}, fn foe, {pods, carried} ->
      {roll, carried} = Rng.roll(carried, 100)

      if roll <= 18, do: {[pod(foe) | pods], carried}, else: {pods, carried}
    end)
  end

  defp pod(foe),
    do: %{kind: :pod, x: foe.x, y: foe.y, path: :drift, lane: foe.x, phase: 0.0, age: 0.0}

  defp collide(%{pilots: pilots} = state) when map_size(pilots) == 0, do: state

  defp collide(state) do
    {taken, rest} =
      Enum.split_with(state.foes, fn foe ->
        foe.kind == :pod and Enum.any?(Map.values(state.pilots), &near?(&1, foe, 1.2))
      end)

    state
    |> Map.put(:foes, rest)
    |> Map.update!(:pilots, fn pilots ->
      Map.new(pilots, fn {id, pilot} ->
        {id, met(pilot, rest, state.flak, length(taken), state.tuning)}
      end)
    end)
  end

  defp met(%{hurt: hurt} = pilot, _foes, _flak, pods, tuning) when hurt > 0,
    do: collected(pilot, pods, tuning)

  defp met(pilot, foes, flak, pods, tuning) do
    gathered = collected(pilot, pods, tuning)

    if Enum.any?(foes, &near?(gathered, &1, 1.1)) or Enum.any?(flak, &near?(gathered, &1, 0.9)),
      do: %{
        gathered
        | shields: max(0, gathered.shields - 1),
          hurt: at(tuning, :hurt_ticks),
          addons: 0
      },
      else: gathered
  end

  defp collected(pilot, 0, _tuning), do: pilot

  defp collected(pilot, pods, tuning),
    do: %{
      pilot
      | score: pilot.score + pods * 150,
        addons: min(at(tuning, :addons), pilot.addons + pods)
    }

  defp near?(one, other, reach),
    do: abs(one.x - other.x) < reach and abs(one.y - other.y) < reach

  defp award(state, 0), do: state

  defp award(state, points) do
    Map.update!(state, :pilots, fn pilots ->
      Map.new(pilots, fn {id, pilot} -> {id, %{pilot | score: pilot.score + points}} end)
    end)
  end

  defp note(state, 0), do: state
  defp note(state, hits), do: Map.update!(state, :events, &[{:burst, hits} | &1])

  defp clamp(value, low, high), do: value |> max(low) |> min(high)
end
