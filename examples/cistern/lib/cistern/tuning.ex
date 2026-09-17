defmodule Cistern.Tuning do
  @moduledoc """
  The numbers the game plays by, as a `Cauldron2D.Tuning`.

    * `:fall` — tiles a second a drop falls
    * `:spawn_every` — seconds between drops
  """

  alias Cauldron2D.Tuning

  @spec_list [
    fall: [default: 3.0, limits: {1.0, 12.0}, doc: "tiles a second a drop falls"],
    spawn_every: [default: 1.2, limits: {0.3, 4.0}, doc: "seconds between drops"]
  ]

  @doc "A tuning with `overrides` over the defaults."
  @spec new(keyword() | map()) :: Tuning.t()
  def new(overrides \\ []), do: Tuning.new(@spec_list, overrides)
end
