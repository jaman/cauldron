defmodule Cauldron2D.RobotTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.{Robot, World}
  alias Cauldron2D.TestGames.Race

  defmodule Racer do
    @moduledoc false
    @behaviour Cauldron2D.Robot

    @impl true
    def init(opts), do: %{test: Keyword.fetch!(opts, :test), decided: 0}

    @impl true
    def decide(%{me: x}, memory, %{tick: tick, skill: skill}) do
      send(memory.test, {:decided, tick, skill, x})
      held = if x < 0.5, do: MapSet.new([:forward]), else: MapSet.new()
      {%{held: held, aim: nil}, %{memory | decided: memory.decided + 1}}
    end

    @impl true
    def gone?(%{others: others}), do: others >= 1
  end

  test "a robot joins as {:robot, n}, decides on its cadence, drives the world, and leaves when gone" do
    {:ok, world} = World.start_link(game: Race, hz: 100)

    {:ok, robot} =
      Robot.start_link(
        brain: Racer,
        brain_opts: [test: self()],
        world: world,
        number: 1,
        skill: 1.0,
        cadence: {2, 6}
      )

    assert World.players(world) == [{:robot, 1}]
    assert_receive {:decided, tick, 1.0, _}, 500
    assert rem(tick, 2) == 0
    Process.sleep(200)
    assert World.snapshot(world).players[{:robot, 1}].x > 0.0

    ref = Process.monitor(robot)
    :ok = Cauldron2D.Player.join(world, :human, %{})
    assert_receive {:DOWN, ^ref, :process, ^robot, :normal}, 1_000
    assert World.players(world) == [:human]
  end

  test "skill is drawn between the least and full, and cadence follows it" do
    for _ <- 1..50 do
      skill = Robot.skill()
      assert skill >= 0.3 and skill <= 1.0
    end

    assert Robot.cadence(1.0, {3, 9}) == 3
    assert Robot.cadence(0.3, {3, 9}) == 9
    assert Robot.cadence(0.65, {3, 9}) == 6
  end

  test "a refused join stops the robot with the reason" do
    {:ok, world} = World.start_link(game: Race, hz: 100)
    :ok = Cauldron2D.Player.join(world, :a, %{})
    :ok = Cauldron2D.Player.join(world, :b, %{})
    Process.flag(:trap_exit, true)

    assert {:error, :full} =
             Robot.start_link(brain: Racer, brain_opts: [test: self()], world: world, number: 1)
  end
end
