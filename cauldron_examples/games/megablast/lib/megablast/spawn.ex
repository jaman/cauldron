defmodule Megablast.Spawn do
  @moduledoc """
  What comes into the lane as the view climbs a stage: the stage's waves when the view
  reaches them, the guardian half way, the boss at the end, and the turrets that grow out
  of the rock ahead.

  Things come in `@ahead` tiles ahead of the view's middle, so they are on their way
  before the ship can see them. Each step answers the world with what came in, and its
  events.
  """

  alias Megablast.{Boss, Foe, Lane, Stages}

  @ahead 14.0

  @doc "How far up the current stage the view has climbed, in tiles."
  @spec climbed(map()) :: float()
  def climbed(world), do: world.start - world.depth

  @doc "The world with everything due this step brought in."
  @spec step({map(), [term()]}) :: {map(), [term()]}
  def step({%{phase: :flying} = world, events}) do
    {world, events}
    |> waves()
    |> guardian()
    |> boss()
    |> turrets()
  end

  def step(acc), do: acc

  defp waves({world, events}) do
    stage = Stages.stage(world.stage)
    due = Enum.drop(stage.waves, world.wave)
    climbed = climbed(world)

    case due do
      [{at, kind, formation, count, where} | _] when at <= climbed ->
        y = world.depth - @ahead
        places = Stages.places({kind, formation, count, where}, Lane.edges(world.lane, y), y)

        {foes, world} =
          Enum.map_reduce(Enum.with_index(places), world, fn {at, index}, w ->
            numbered(w, kind, at, index)
          end)

        waves({%{world | foes: foes ++ world.foes, wave: world.wave + 1}, events})

      _later ->
        {world, events}
    end
  end

  defp numbered(world, kind, at, index) do
    foe = kind |> Foe.new(at, %{phase: index * 0.7}) |> Map.put(:id, world.serial)
    {foe, %{world | serial: world.serial + 1}}
  end

  defp guardian({%{guarded?: false} = world, events}) do
    {at, design, hp} = Stages.stage(world.stage).guardian

    if climbed(world) >= at do
      boss = Boss.new(Stages.design(design, hp), {Lane.middle(world.lane), world.depth - @ahead})
      {%{world | boss: boss, guarded?: true, phase: :boss}, [{:warning, :guardian} | events]}
    else
      {world, events}
    end
  end

  defp guardian(acc), do: acc

  defp boss({%{phase: :flying} = world, events}) do
    stage = Stages.stage(world.stage)

    if climbed(world) >= stage.length do
      boss = Boss.new(Stages.design(stage.boss), {Lane.middle(world.lane), world.depth - @ahead})
      {%{world | boss: boss, phase: :boss, final?: true}, [{:warning, stage.boss} | events]}
    else
      {world, events}
    end
  end

  defp boss(acc), do: acc

  defp turrets({world, events}) do
    wanted = Lane.turret_step(world.lane, world.depth - @ahead)

    if wanted < world.turret_step do
      {grown, world} =
        wanted..(world.turret_step - 1)//1
        |> Enum.flat_map(&List.wrap(Lane.turret_of(world.lane, &1)))
        |> Enum.map_reduce(world, fn turret, w ->
          numbered(w, :turret, {turret.x, turret.y}, 0)
        end)

      {%{world | foes: grown ++ world.foes, turret_step: wanted}, events}
    else
      {world, events}
    end
  end
end
