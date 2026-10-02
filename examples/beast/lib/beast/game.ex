defmodule Beast.Game do
  @moduledoc """
  The world the runner crosses: one figure a player, bats that swoop in from ahead and
  crawlers that walk the ground, on terrain that goes on forever.

  Held `:left` and `:right` run, `:jump` leaves the ground. Walking off a ledge drops the
  runner; ground more than a step above his feet has to be jumped. Touching a creature
  knocks him back and costs a life; at no lives he is set down at the start again.

  Every number that decides how it plays is a `Beast.Tuning` carried in the state. Pass
  `:tuning` to `init/1` to change them, and read one with `tuning/2`.
  """

  @behaviour Cauldron2D.Game

  alias Beast.{Terrain, Tuning}
  alias Cauldron2D.Rng

  @impl true
  def init(opts) do
    %{
      runners: %{},
      bats: [],
      crawlers: [],
      rng: Rng.new(Keyword.get(opts, :seed, 20_261_002)),
      tuning: Tuning.new(Keyword.get(opts, :tuning, [])),
      filled_to: 24.0,
      events: [],
      ticks: 0
    }
  end

  @doc "The value of a tuning setting, as `Beast.Tuning` declares them."
  @spec tuning(map(), atom()) :: term()
  def tuning(%{tuning: tuning}, key), do: Cauldron2D.Tuning.get(tuning, key)

  @impl true
  def join(state, id, _props), do: {:ok, put_in(state.runners[id], runner(state.tuning))}

  @impl true
  def leave(state, id), do: %{state | runners: Map.delete(state.runners, id)}

  @impl true
  def handle_input(state, id, %{held: held}) do
    if Map.has_key?(state.runners, id),
      do: put_in(state.runners[id].held, held),
      else: state
  end

  @impl true
  def step(state, dt) do
    tuning = state.tuning

    state
    |> Map.update!(:runners, fn runners ->
      Map.new(runners, &{elem(&1, 0), move(elem(&1, 1), tuning, dt)})
    end)
    |> fill()
    |> drift(dt)
    |> touch()
    |> Map.update!(:ticks, &(&1 + 1))
  end

  @impl true
  def view(state, id) do
    %{
      me: Map.get(state.runners, id),
      bats: state.bats,
      crawlers: state.crawlers,
      others: for({other, runner} <- state.runners, other != id, do: runner)
    }
  end

  @impl true
  def drain_events(state), do: {Enum.reverse(state.events), %{state | events: []}}

  defp at(tuning, key), do: Cauldron2D.Tuning.get(tuning, key)

  defp runner(tuning) do
    %{
      x: 4.0,
      y: Terrain.floor_at(4.0) - 1.0,
      vy: 0.0,
      facing: 1,
      grounded?: true,
      running?: false,
      lives: at(tuning, :lives),
      hurt: 0,
      best: 4.0,
      stride: 0.0,
      held: MapSet.new()
    }
  end

  defp move(runner, tuning, dt) do
    direction = steer(runner.held)

    runner
    |> Map.put(:running?, direction != 0 and runner.grounded?)
    |> Map.update!(:facing, fn facing -> if direction == 0, do: facing, else: direction end)
    |> walk(direction, tuning, dt)
    |> leap(tuning, dt)
    |> land(tuning)
    |> Map.update!(:hurt, &max(0, &1 - 1))
    |> then(fn moved -> Map.update!(moved, :best, &max(&1, moved.x)) end)
  end

  defp steer(held) do
    cond do
      MapSet.member?(held, :right) -> 1
      MapSet.member?(held, :left) -> -1
      true -> 0
    end
  end

  defp walk(runner, 0, _tuning, _dt), do: runner

  defp walk(runner, direction, tuning, dt) do
    wanted = max(1.0, runner.x + direction * at(tuning, :run) * dt)

    if blocked?(runner, wanted, tuning),
      do: runner,
      else: %{runner | x: wanted, stride: runner.stride + abs(wanted - runner.x)}
  end

  defp blocked?(runner, wanted, tuning),
    do: Terrain.floor_at(wanted) - 1.0 < runner.y - at(tuning, :step)

  defp leap(%{grounded?: true} = runner, tuning, dt) do
    jump = at(tuning, :jump)

    if MapSet.member?(runner.held, :jump),
      do: %{runner | vy: -jump, grounded?: false, y: runner.y - jump * dt},
      else: runner
  end

  defp leap(runner, tuning, dt) do
    velocity = runner.vy + at(tuning, :gravity) * dt
    %{runner | vy: velocity, y: runner.y + velocity * dt}
  end

  defp land(runner, _tuning) do
    ground = Terrain.floor_at(runner.x) - 1.0

    cond do
      runner.y >= ground -> %{runner | y: ground, vy: 0.0, grounded?: true}
      runner.grounded? -> %{runner | grounded?: false, vy: 0.0}
      true -> runner
    end
  end

  defp fill(%{runners: runners} = state) when map_size(runners) == 0, do: state

  defp fill(state) do
    front = state.runners |> Map.values() |> Enum.map(& &1.x) |> Enum.max()

    if front + at(state.tuning, :ahead) > state.filled_to do
      state
      |> spawn(state.filled_to)
      |> Map.put(:filled_to, state.filled_to + at(state.tuning, :gap))
    else
      state
    end
  end

  defp spawn(state, to) do
    {roll, rng} = Rng.roll(state.rng, 100)
    {bob, rng} = Rng.between(rng, 5, 9)

    if roll <= 55 do
      %{
        state
        | rng: rng,
          bats: [%{x: to, y: Terrain.floor_at(to) - bob, phase: roll / 10} | state.bats]
      }
    else
      %{state | rng: rng, crawlers: [%{x: to, y: 0.0, phase: 0.0} | state.crawlers]}
    end
  end

  defp drift(state, dt) do
    behind = oldest(state) - at(state.tuning, :behind)
    bat_speed = at(state.tuning, :bat_speed)
    crawler_speed = at(state.tuning, :crawler_speed)

    %{
      state
      | bats: state.bats |> Enum.map(&swoop(&1, bat_speed, dt)) |> Enum.filter(&(&1.x > behind)),
        crawlers:
          state.crawlers
          |> Enum.map(&crawl(&1, crawler_speed, dt))
          |> Enum.filter(&(&1.x > behind))
    }
  end

  defp swoop(bat, speed, dt) do
    phase = bat.phase + dt * 2.2
    %{bat | x: bat.x - speed * dt, y: bat.y + :math.sin(phase) * dt * 3.0, phase: phase}
  end

  defp crawl(crawler, speed, dt), do: %{crawler | x: crawler.x - speed * dt}

  defp oldest(%{runners: runners}) when map_size(runners) == 0, do: 0.0
  defp oldest(state), do: state.runners |> Map.values() |> Enum.map(& &1.x) |> Enum.min()

  defp touch(state) do
    creatures = state.bats ++ Enum.map(state.crawlers, &%{&1 | y: Terrain.floor_at(&1.x) - 1.0})

    Map.update!(state, :runners, fn runners ->
      Map.new(runners, fn {id, runner} -> {id, bump(runner, creatures, state.tuning)} end)
    end)
  end

  defp bump(%{hurt: hurt} = runner, _creatures, _tuning) when hurt > 0, do: runner

  defp bump(runner, creatures, tuning) do
    if Enum.any?(creatures, &near?(runner, &1)),
      do: wounded(runner, tuning),
      else: runner
  end

  defp near?(runner, creature) do
    abs(runner.x - creature.x) < 0.8 and abs(runner.y - creature.y) < 1.2
  end

  defp wounded(%{lives: 1}, tuning), do: runner(tuning)

  defp wounded(runner, tuning) do
    %{
      runner
      | lives: runner.lives - 1,
        hurt: at(tuning, :hurt_ticks),
        x: max(1.0, runner.x - 1.5),
        vy: -8.0,
        grounded?: false
    }
  end
end
