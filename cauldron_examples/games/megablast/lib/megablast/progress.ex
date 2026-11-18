defmodule Megablast.Progress do
  @moduledoc """
  The world's phases and the moves between them.

    * `:flying` — up the stage, its waves coming in (`Megablast.Spawn`)
    * `:boss` — a guardian or the stage's boss is fought; beating a guardian flies on,
      beating the boss clears the stage
    * `:clear` — a few seconds to gather the credits it dropped
    * `:shop` — every pilot shops (`Megablast.Shop`) until all have launched or the time
      is up, and the next stage begins
    * `:won` — the fifth boss beaten

  Each step answers the world and its events, newest first.
  """

  alias Cauldron.Tuning
  alias Megablast.{Boss, Lane, Ship, Shop, Spawn, Stages}

  @clear_seconds 4.0

  @doc "The world after this step's moves between phases."
  @spec step({map(), [term()]}, number()) :: {map(), [term()]}
  def step({%{phase: :boss, boss: boss} = world, events}, _dt) do
    cond do
      not Boss.beaten?(boss) ->
        {world, events}

      world.final? ->
        {%{world | boss: nil, phase: :clear, timer: @clear_seconds},
         [{:clear, world.stage} | events]}

      true ->
        {%{world | boss: nil, phase: :flying}, events}
    end
  end

  def step({%{phase: :clear} = world, events}, dt) do
    left = world.timer - dt

    cond do
      left > 0 -> {%{world | timer: left}, events}
      world.stage >= Stages.count() -> {%{world | phase: :won}, [:won | events]}
      true -> {open_shop(world), [:shop | events]}
    end
  end

  def step({%{phase: :shop} = world, events}, dt) do
    {world, events} = shop(world, events)
    left = world.timer - dt
    flying = for {_id, ship} <- world.pilots, not ship.out?, do: ship

    if left <= 0 or Enum.all?(flying, & &1.ready?),
      do: next_stage({world, events}),
      else: {%{world | timer: left}, events}
  end

  def step(acc, _dt), do: acc

  defp open_shop(world) do
    pilots =
      Map.new(world.pilots, fn {id, ship} -> {id, %{ship | ready?: ship.out?, cursor: 0}} end)

    %{
      world
      | phase: :shop,
        timer: Tuning.get(world.tuning, :shop_time),
        pilots: pilots,
        bullets: [],
        foes: []
    }
  end

  defp shop(world, events) do
    count = length(Shop.wares())
    shields = Tuning.get(world.tuning, :shields)

    Enum.reduce(world.pilots, {world, events}, fn {id, ship}, {w, e} ->
      {ship, e} = shopping(ship, Ship.pressed(ship), count, shields, e)
      {%{w | pilots: Map.put(w.pilots, id, ship)}, e}
    end)
  end

  defp shopping(%{ready?: true} = ship, _pressed, _count, _shields, events), do: {ship, events}

  defp shopping(ship, pressed, count, shields, events) do
    cond do
      :thrust in pressed ->
        {%{ship | cursor: Integer.mod(ship.cursor - 1, count)}, [{:tick, ship.id} | events]}

      :brake in pressed ->
        {%{ship | cursor: Integer.mod(ship.cursor + 1, count)}, [{:tick, ship.id} | events]}

      :fire in pressed ->
        buy(ship, Enum.at(Shop.wares(), ship.cursor).id, shields, events)

      true ->
        {ship, events}
    end
  end

  defp buy(ship, :launch, _shields, events),
    do: {%{ship | ready?: true}, [{:launch, ship.id} | events]}

  defp buy(ship, id, shields, events) do
    case Shop.buy(ship, id, shields) do
      {:ok, bought} -> {bought, [{:bought, ship.id} | events]}
      {:refused, same} -> {same, [{:refused, ship.id} | events]}
    end
  end

  defp next_stage({world, events}) do
    number = world.stage + 1
    stage = Stages.stage(number)
    lane = Lane.new(stage.walls)

    world = %{
      world
      | stage: number,
        lane: lane,
        start: world.depth,
        wave: 0,
        guarded?: false,
        final?: false,
        phase: :flying,
        turret_step: Lane.turret_step(lane, world.depth - 14.0),
        pilots:
          Map.new(world.pilots, fn {id, ship} ->
            {id, %{ship | ready?: false, x: Lane.middle(lane), y: world.depth + 4.0, hurt: 2.0}}
          end)
    }

    {world, [{:stage, number} | events]}
  end

  @doc "How far through the current stage the view is, `0.0..1.0`."
  @spec through(map()) :: float()
  def through(world), do: min(1.0, Spawn.climbed(world) / Stages.stage(world.stage).length)
end
