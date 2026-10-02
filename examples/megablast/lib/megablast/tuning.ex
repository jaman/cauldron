defmodule Megablast.Tuning do
  @moduledoc """
  Every number that decides how the lane plays, as a `Cauldron2D.Tuning`.

  A tuning is carried in the game state: set it per world through `Megablast.Game.init/1`'s
  `:tuning` option, and read it with `Megablast.Game.tuning/2`.

  ## Settings

    * `:scroll` — how fast the lane carries the view on, in tiles a second
    * `:steer` — how fast the ship moves across the lane, in tiles a second
    * `:lift` — how fast the ship moves up and down the lane, in tiles a second
    * `:shot_speed` — how fast the ship's shots fly, in tiles a second
    * `:flak_speed` — how fast a turret's bolt flies, in tiles a second
    * `:reload` — ticks between one of the ship's shots and the next
    * `:turret_reload` — ticks between one turret bolt and the next
    * `:turret_reach` — how near the ship must come before a turret opens, in tiles
    * `:shields` — how many hits the ship survives
    * `:hurt_ticks` — how many ticks the ship is untouchable for after a hit
    * `:addons` — how many drones the ship may carry
    * `:addon_reach` — how far beside the ship a drone sits, in tiles
    * `:wave_gap` — how far apart waves enter, in tiles
    * `:wave_ahead` — how far ahead of the view a wave enters, in tiles
    * `:behind` — how far behind the view a thing is left, in tiles
    * `:ceiling` — how far above the view's middle the ship may fly, in tiles
    * `:floor` — how far below the view's middle the ship may fly, in tiles
    * `:reach` — how far below the view the ship may get before it is held back, in tiles
    * `:push` — how fast the view is pushed back when the ship dives, in tiles a second
    * `:margin` — how near the rock the ship may fly, in tiles

  ## Example

      tuning = Megablast.Tuning.new(scroll: 8.0, shields: 5)
      Cauldron2D.Tuning.get(tuning, :scroll)
  """

  alias Cauldron2D.Tuning

  @spec_list [
    scroll: [default: 5.0, limits: {1.0, 16.0}, doc: "tiles a second the lane carries on"],
    steer: [default: 13.0, limits: {3.0, 30.0}, doc: "tiles a second across the lane"],
    lift: [default: 9.0, limits: {2.0, 24.0}, doc: "tiles a second up and down the lane"],
    shot_speed: [default: 30.0, limits: {8.0, 70.0}, doc: "tiles a second a shot flies"],
    flak_speed: [default: 10.0, limits: {2.0, 30.0}, doc: "tiles a second a bolt flies"],
    reload: [default: 8, limits: {1, 60}, doc: "ticks between the ship's shots"],
    turret_reload: [default: 90, limits: {10, 400}, doc: "ticks between turret bolts"],
    turret_reach: [default: 16.0, limits: {4.0, 40.0}, doc: "tiles before a turret opens"],
    shields: [default: 3, limits: {1, 9}, doc: "hits the ship survives"],
    hurt_ticks: [default: 50, limits: {0, 200}, doc: "ticks untouchable after a hit"],
    addons: [default: 2, limits: {0, 4}, doc: "drones the ship may carry"],
    addon_reach: [default: 1.6, limits: {0.6, 4.0}, doc: "tiles beside the ship a drone sits"],
    wave_gap: [default: 20.0, limits: {6.0, 60.0}, doc: "tiles between one wave and the next"],
    wave_ahead: [default: 24.0, limits: {8.0, 60.0}, doc: "tiles ahead a wave enters"],
    behind: [default: 12.0, limits: {4.0, 40.0}, doc: "tiles behind before a thing is gone"],
    ceiling: [default: 5.0, limits: {1.0, 14.0}, doc: "tiles above the middle the ship may fly"],
    floor: [default: 9.0, limits: {1.0, 16.0}, doc: "tiles below the middle the ship may fly"],
    reach: [default: 7.0, limits: {1.0, 14.0}, doc: "tiles below before the view is held"],
    push: [default: 3.0, limits: {0.0, 12.0}, doc: "tiles a second the view is pushed back"],
    margin: [default: 1.2, limits: {0.2, 4.0}, doc: "tiles from the rock the ship is kept"]
  ]

  @doc """
  The settings, their defaults, limits and docs, as `Cauldron2D.Tuning.new/2` takes them.

  A default is whatever `config :megablast, <setting>, value` says, falling back to the one
  declared here, so a deployment can move it without touching the code and a caller can
  still beat it by passing the setting to `new/1`.
  """
  @spec spec() :: Tuning.spec()
  def spec do
    Enum.map(@spec_list, fn {key, options} ->
      {key,
       Keyword.put(options, :default, Application.get_env(:megablast, key, options[:default]))}
    end)
  end

  @doc "A tuning with `overrides` over the defaults; an override for an unknown setting raises `KeyError`."
  @spec new(keyword() | map()) :: Tuning.t()
  def new(overrides \\ []), do: Tuning.new(spec(), overrides)
end
