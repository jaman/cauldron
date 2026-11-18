defmodule Cistern.Tuning do
  @moduledoc """
  The numbers the game plays by, as a `Cauldron.Tuning`. Each pace setting has a
  first-storm value and a step added for every storm after it.

    * `:squall_speed`, `:squall_speed_step` — tiles a second the Squall drifts
    * `:drop_every`, `:drop_every_step` — seconds between drops (the step is taken off)
    * `:fall`, `:fall_step` — tiles a second a drop falls
    * `:storm_drops`, `:storm_drops_step` — drops in a storm
    * `:swerve` — the chance a second, per storm, that the Squall turns before it
      reaches where it was going
    * `:lull` — seconds of quiet before a storm and after a miss
    * `:streak` — catches in a row that win a broken jar back
    * `:keeper_speed` — tiles a second the keeper walks
  """

  alias Cauldron.Tuning

  @spec_list [
    squall_speed: [default: 3.0, limits: {0.5, 20.0}, doc: "tiles a second the Squall drifts"],
    squall_speed_step: [default: 1.1, limits: {0.0, 5.0}, doc: "more each storm"],
    drop_every: [default: 1.1, limits: {0.15, 4.0}, doc: "seconds between drops"],
    drop_every_step: [default: 0.11, limits: {0.0, 1.0}, doc: "less each storm"],
    fall: [default: 4.0, limits: {1.0, 30.0}, doc: "tiles a second a drop falls"],
    fall_step: [default: 0.8, limits: {0.0, 5.0}, doc: "more each storm"],
    storm_drops: [default: 10, limits: {1, 200}, doc: "drops in the first storm"],
    storm_drops_step: [default: 5, limits: {0, 50}, doc: "more each storm"],
    swerve: [default: 0.12, limits: {0.0, 2.0}, doc: "turns a second, per storm"],
    lull: [default: 2.0, limits: {0.0, 10.0}, doc: "seconds of quiet between storms"],
    streak: [default: 15, limits: {1, 100}, doc: "catches in a row that mend a jar"],
    keeper_speed: [default: 9.0, limits: {1.0, 30.0}, doc: "tiles a second the keeper walks"]
  ]

  @doc "A tuning with `overrides` over the defaults."
  @spec new(keyword() | map()) :: Tuning.t()
  def new(overrides \\ []), do: Tuning.new(@spec_list, overrides)
end
