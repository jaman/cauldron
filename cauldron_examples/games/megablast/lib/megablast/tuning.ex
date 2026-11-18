defmodule Megablast.Tuning do
  @moduledoc """
  Every number that decides how the lane plays, as a `Cauldron.Tuning`, carried in the
  game state: `Megablast.Game.init/1` takes `:tuning` overrides.

    * `:scroll` — tiles a second the lane carries the view on
    * `:boss_scroll` — tiles a second it creeps while a boss is fought
    * `:steer`, `:lift` — tiles a second the ship moves across and along the lane, before
      its engines are bought up
    * `:engine_step` — how much faster each engine bought makes the ship
    * `:reload` — seconds between the main gun's shots
    * `:shot_speed`, `:bullet_speed` — tiles a second the ship's shots and enemy bullets fly
    * `:shields`, `:lives` — hits a ship takes before it is lost, and ships a pilot has
    * `:hurt` — seconds a ship is untouchable after a hit or a new life
    * `:chain_time` — seconds a kill keeps the chain alive
    * `:chain_most` — the largest a chain's multiplier grows
    * `:ceiling`, `:floor` — tiles above and below the view's middle the ship may fly
    * `:margin` — tiles from the rock the ship is kept
    * `:hitbox` — the radius of the ship that a bullet must touch, in tiles
    * `:shop_time` — seconds the shop stays open before the lane goes on
  """

  alias Cauldron.Tuning

  @spec_list [
    scroll: [default: 4.0, limits: {1.0, 16.0}, doc: "tiles a second the lane carries on"],
    boss_scroll: [default: 0.0, limits: {0.0, 8.0}, doc: "tiles a second during a boss"],
    steer: [default: 11.0, limits: {3.0, 30.0}, doc: "tiles a second across"],
    lift: [default: 8.0, limits: {2.0, 24.0}, doc: "tiles a second up and down"],
    engine_step: [default: 0.18, limits: {0.0, 1.0}, doc: "faster with each engine"],
    reload: [default: 0.13, limits: {0.03, 1.0}, doc: "seconds between main shots"],
    shot_speed: [default: 30.0, limits: {8.0, 70.0}, doc: "tiles a second a shot flies"],
    bullet_speed: [default: 9.0, limits: {2.0, 30.0}, doc: "tiles a second a bullet flies"],
    shields: [default: 3, limits: {1, 9}, doc: "hits a ship takes"],
    lives: [default: 3, limits: {1, 9}, doc: "ships a pilot has"],
    hurt: [default: 1.6, limits: {0.0, 6.0}, doc: "seconds untouchable after a hit"],
    chain_time: [default: 1.6, limits: {0.2, 6.0}, doc: "seconds a kill keeps the chain"],
    chain_most: [default: 8, limits: {1, 32}, doc: "the largest multiplier"],
    ceiling: [default: 6.0, limits: {1.0, 14.0}, doc: "tiles above the middle"],
    floor: [default: 8.0, limits: {1.0, 16.0}, doc: "tiles below the middle"],
    margin: [default: 1.0, limits: {0.2, 4.0}, doc: "tiles from the rock"],
    hitbox: [default: 0.35, limits: {0.1, 1.5}, doc: "the ship's radius for bullets"],
    shop_time: [default: 45.0, limits: {5.0, 300.0}, doc: "seconds the shop stays open"]
  ]

  @doc "A tuning with `overrides` over the defaults."
  @spec new(keyword() | map()) :: Tuning.t()
  def new(overrides \\ []), do: Tuning.new(@spec_list, overrides)
end
