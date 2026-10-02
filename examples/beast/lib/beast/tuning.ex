defmodule Beast.Tuning do
  @moduledoc """
  Every number that decides how the run plays, as a `Cauldron2D.Tuning`.

  A tuning is carried in the game state: set it per world through `Beast.Game.init/1`'s
  `:tuning` option, and read it with `Beast.Game.tuning/2`.

  ## Settings

    * `:run` — how fast the runner moves, in tiles a second
    * `:step` — how far above his feet the ground may rise and still be walked onto, in
      tiles; anything higher has to be jumped
    * `:gravity` — the pull on a runner off the ground, in tiles a second squared
    * `:jump` — the speed a jump leaves the ground at, in tiles a second
    * `:bat_speed` — how fast a bat flies down the plain, in tiles a second
    * `:crawler_speed` — how fast a crawler walks, in tiles a second
    * `:ahead` — how far in front of the runner the plain is peopled, in tiles
    * `:gap` — how far apart creatures are hatched, in tiles
    * `:behind` — how far behind the runner a creature is left, in tiles
    * `:hurt_ticks` — how many ticks a runner is untouchable for after a knock
    * `:lives` — how many knocks a runner survives

  ## Example

      tuning = Beast.Tuning.new(run: 9.0, lives: 5)
      Cauldron2D.Tuning.get(tuning, :run)

  A setting with limits is clamped by `Cauldron2D.Tuning.put/3`; everything else is stored
  as given.
  """

  alias Cauldron2D.Tuning

  @spec_list [
    run: [default: 7.0, limits: {2.0, 16.0}, doc: "tiles a second the runner moves"],
    step: [default: 1.0, limits: {0.0, 4.0}, doc: "tiles of rise he can walk onto"],
    gravity: [default: 55.0, limits: {10.0, 120.0}, doc: "tiles a second squared"],
    jump: [default: 17.0, limits: {6.0, 32.0}, doc: "tiles a second a jump starts at"],
    bat_speed: [default: 7.0, limits: {1.0, 18.0}, doc: "tiles a second a bat flies"],
    crawler_speed: [default: 3.0, limits: {0.5, 12.0}, doc: "tiles a second a crawler walks"],
    ahead: [default: 40.0, limits: {12.0, 90.0}, doc: "tiles ahead the plain is peopled"],
    gap: [default: 22.0, limits: {6.0, 70.0}, doc: "tiles between one creature and the next"],
    behind: [default: 24.0, limits: {8.0, 70.0}, doc: "tiles behind before a creature is gone"],
    hurt_ticks: [default: 40, limits: {0, 200}, doc: "ticks untouchable after a knock"],
    lives: [default: 3, limits: {1, 9}, doc: "knocks the runner survives"]
  ]

  @doc """
  The settings, their defaults, limits and docs, as `Cauldron2D.Tuning.new/2` takes them.

  A default is whatever `config :beast, <setting>, value` says, falling back to the one
  declared here, so a deployment can move it without touching the code and a caller can
  still beat it by passing the setting to `new/1`.
  """
  @spec spec() :: Tuning.spec()
  def spec do
    Enum.map(@spec_list, fn {key, options} ->
      {key, Keyword.put(options, :default, Application.get_env(:beast, key, options[:default]))}
    end)
  end

  @doc "A tuning with `overrides` over the defaults; an override for an unknown setting raises `KeyError`."
  @spec new(keyword() | map()) :: Tuning.t()
  def new(overrides \\ []), do: Tuning.new(spec(), overrides)
end
