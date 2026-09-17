defmodule Cauldron2D.TuningTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Tuning

  @spec_list [
    ball_speed: [default: 10.0, limits: {4.0, 24.0}, doc: "tiles a second"],
    drop_chance: [default: 7],
    widths: [default: %{narrow: 2.0, wide: 5.5}]
  ]

  test "a tuning starts from its defaults with overrides applied" do
    tuning = Tuning.new(@spec_list, ball_speed: 14.0)
    assert Tuning.get(tuning, :ball_speed) == 14.0
    assert Tuning.get(tuning, :drop_chance) == 7
    assert Tuning.get(tuning, :widths).wide == 5.5
    assert Tuning.keys(tuning) == [:ball_speed, :drop_chance, :widths]
  end

  test "put clamps a setting with limits, takes any other as given, and refuses an unknown one" do
    tuning = Tuning.new(@spec_list)
    assert Tuning.get(Tuning.put(tuning, :ball_speed, 99.0), :ball_speed) == 24.0
    assert Tuning.get(Tuning.put(tuning, :ball_speed, 1.0), :ball_speed) == 4.0
    assert Tuning.get(Tuning.put(tuning, :drop_chance, 100), :drop_chance) == 100
    assert_raise KeyError, fn -> Tuning.put(tuning, :nope, 1) end
    assert Tuning.limits(tuning, :ball_speed) == {4.0, 24.0}
    assert Tuning.limits(tuning, :drop_chance) == nil
  end

  test "describe lists every setting for a settings page, and step moves a bounded one by a share of its range" do
    tuning = Tuning.new(@spec_list)

    assert [
             %{key: :ball_speed, value: 10.0, limits: {4.0, 24.0}, doc: "tiles a second"},
             %{key: :drop_chance, doc: nil} | _
           ] = Tuning.describe(tuning)

    assert Tuning.get(Tuning.step(tuning, :ball_speed, 1), :ball_speed) == 11.0
    assert Tuning.get(Tuning.step(tuning, :ball_speed, -10), :ball_speed) == 4.0
    assert Tuning.get(Tuning.step(tuning, :drop_chance, 1), :drop_chance) == 8
  end
end
