defmodule Beast.Tuning do
  @moduledoc """
  Every number that decides how the beast moves and fights, as a `Cauldron.Tuning`
  carried in the game state: `Beast.Game.init/1` takes `:tuning` overrides.

    * `:run` — tiles a second the beast runs
    * `:gravity` — tiles a second squared it falls
    * `:jump` — tiles a second a jump leaves the ground at; letting go early cuts it short
    * `:dodge`, `:dodge_time`, `:dodge_rest` — a roll's speed, length and the wait before another
    * `:charge` — seconds an attack is held to charge the heavy blow
    * `:health` — half-hearts the beast has
    * `:hurt_time` — seconds untouchable after a wound
    * `:knock` — tiles a second a wound throws it back
    * `:stop` — seconds the world holds still when a blow lands
  """

  alias Cauldron.Tuning

  @spec_list [
    run: [default: 7.0, limits: {2.0, 16.0}, doc: "tiles a second the beast runs"],
    gravity: [default: 75.0, limits: {10.0, 120.0}, doc: "tiles a second squared"],
    jump: [default: 26.0, limits: {6.0, 32.0}, doc: "tiles a second a jump starts at"],
    dodge: [default: 11.0, limits: {3.0, 25.0}, doc: "tiles a second a roll moves"],
    dodge_time: [default: 0.32, limits: {0.1, 1.0}, doc: "seconds a roll lasts"],
    dodge_rest: [default: 0.45, limits: {0.0, 2.0}, doc: "seconds before another roll"],
    charge: [default: 0.55, limits: {0.1, 2.0}, doc: "seconds held to charge a heavy blow"],
    health: [default: 8, limits: {1, 30}, doc: "half-hearts"],
    hurt_time: [default: 1.0, limits: {0.0, 4.0}, doc: "seconds untouchable after a wound"],
    knock: [default: 9.0, limits: {0.0, 20.0}, doc: "tiles a second a wound throws back"],
    stop: [default: 0.06, limits: {0.0, 0.3}, doc: "seconds of stillness when a blow lands"]
  ]

  @doc "A tuning with `overrides` over the defaults."
  @spec new(keyword() | map()) :: Tuning.t()
  def new(overrides \\ []), do: Tuning.new(@spec_list, overrides)
end
