defmodule CisternComplete.Tuning do
  @moduledoc """
  The numbers the game plays by, as a `Cauldron.Tuning`. A pace setting has a
  first-storm value and a step added for every storm after it.

    * `:squall_speed`, `:squall_speed_step` — tiles a second the Squall drifts
    * `:drop_every`, `:drop_every_step` — seconds between drops (the step is taken off)
    * `:fall`, `:fall_step` — tiles a second rain falls
    * `:storm_drops`, `:storm_drops_step` — drops in a storm
    * `:swerve` — chances a second, per storm, that the Squall turns early
    * `:mood_every` — seconds between the Squall's changes of mood
    * `:hail_from`, `:hail_chance` — the first storm with hail, and the share of drops that are hail
    * `:lightning_from`, `:lightning_every` — the first storm with lightning, and seconds between strikes
    * `:flicker` — seconds a strike's column flickers before it strikes
    * `:lull` — seconds of quiet before a storm and after a miss
    * `:capacity` — drops a jar holds
    * `:pour_seconds` — how long a pour takes
    * `:streak` — catches in a row that mend a jar
    * `:keeper_speed` — tiles a second the keeper walks
    * `:gust_seconds` — how long a gust lasts, the Squall's own or one a rival sent
  """

  alias Cauldron.Tuning

  @spec_list [
    squall_speed: [default: 3.0, limits: {0.5, 20.0}, doc: "tiles a second the Squall drifts"],
    squall_speed_step: [default: 1.0, limits: {0.0, 5.0}, doc: "more each storm"],
    drop_every: [default: 1.05, limits: {0.15, 4.0}, doc: "seconds between drops"],
    drop_every_step: [default: 0.1, limits: {0.0, 1.0}, doc: "less each storm"],
    fall: [default: 4.0, limits: {1.0, 30.0}, doc: "tiles a second rain falls"],
    fall_step: [default: 0.7, limits: {0.0, 5.0}, doc: "more each storm"],
    storm_drops: [default: 14, limits: {1, 200}, doc: "drops in the first storm"],
    storm_drops_step: [default: 6, limits: {0, 50}, doc: "more each storm"],
    swerve: [default: 0.12, limits: {0.0, 2.0}, doc: "turns a second, per storm"],
    mood_every: [default: 5.0, limits: {1.0, 30.0}, doc: "seconds between moods"],
    hail_from: [default: 3, limits: {1, 50}, doc: "the first storm with hail"],
    hail_chance: [default: 0.18, limits: {0.0, 1.0}, doc: "share of drops that are hail"],
    lightning_from: [default: 4, limits: {1, 50}, doc: "the first storm with lightning"],
    lightning_every: [default: 7.0, limits: {1.0, 60.0}, doc: "seconds between strikes"],
    flicker: [default: 1.1, limits: {0.2, 5.0}, doc: "seconds a strike flickers first"],
    lull: [default: 2.2, limits: {0.0, 10.0}, doc: "seconds of quiet between storms"],
    capacity: [default: 5, limits: {1, 20}, doc: "drops a jar holds"],
    pour_seconds: [default: 0.6, limits: {0.1, 3.0}, doc: "seconds a pour takes"],
    streak: [default: 15, limits: {1, 100}, doc: "catches in a row that mend a jar"],
    keeper_speed: [default: 9.0, limits: {1.0, 30.0}, doc: "tiles a second the keeper walks"],
    gust_seconds: [default: 2.5, limits: {0.5, 10.0}, doc: "seconds a gust lasts"]
  ]

  @doc "A tuning with `overrides` over the defaults."
  @spec new(keyword() | map()) :: Tuning.t()
  def new(overrides \\ []), do: Tuning.new(@spec_list, overrides)
end
