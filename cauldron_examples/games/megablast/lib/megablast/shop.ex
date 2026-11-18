defmodule Megablast.Shop do
  @moduledoc """
  The trader between stages, and what a pilot's credits buy there.

  The wares are rows a pilot moves a cursor over (`:thrust` up, `:brake` down) and buys
  with `:fire`; the last row launches them into the next stage. A weapon's price rises
  with its level and stops at its most; a shield fills the ship's shields again, a ship
  adds a life.
  """

  alias Megablast.Weapons

  @wares [
    %{id: :main, name: "MEGA CANNON", prices: [nil, 60, 120, 200]},
    %{id: :laser, name: "LASER", prices: [80, 160, 240]},
    %{id: :homing, name: "HOMING MISSILES", prices: [90, 180]},
    %{id: :side, name: "SIDE SHOTS", prices: [50, 110]},
    %{id: :rear, name: "REAR SHOT", prices: [50, 110]},
    %{id: :drones, name: "DRONES", prices: [70, 150]},
    %{id: :engine, name: "ENGINE", prices: [40, 80, 120]},
    %{id: :bombs, name: "SMART BOMB", prices: [30, 30, 30, 30, 30]},
    %{id: :shield, name: "SHIELD REFILL", prices: :each, price: 40},
    %{id: :life, name: "EXTRA SHIP", prices: :each, price: 250},
    %{id: :launch, name: "LAUNCH", prices: :none}
  ]

  @type ware :: %{id: atom(), name: String.t()}

  @doc "The wares in the order they are shown."
  @spec wares() :: [ware()]
  def wares, do: @wares

  @doc "What ware `id` costs a pilot with `kit` next, `nil` when it cannot be bought again."
  @spec price(atom(), Weapons.kit()) :: non_neg_integer() | nil
  def price(:launch, _kit), do: 0

  def price(id, kit) do
    case Enum.find(@wares, &(&1.id == id)) do
      %{prices: :each, price: price} -> price
      %{prices: prices} -> Enum.at(prices, Map.fetch!(kit, id))
    end
  end

  @doc """
  The pilot after buying ware `id`: `{:ok, pilot}`, or `{:refused, pilot}` when it is
  sold out or too dear. A pilot is a map with `:credits`, `:kit`, `:shields` and
  `:lives`; `shields` is the most the refill gives.
  """
  @spec buy(map(), atom(), pos_integer()) :: {:ok, map()} | {:refused, map()}
  def buy(pilot, id, shields) do
    case price(id, pilot.kit) do
      nil -> {:refused, pilot}
      cost when cost > pilot.credits -> {:refused, pilot}
      cost -> {:ok, pilot |> Map.update!(:credits, &(&1 - cost)) |> bought(id, shields)}
    end
  end

  defp bought(pilot, :shield, shields), do: %{pilot | shields: shields}
  defp bought(pilot, :life, _shields), do: %{pilot | lives: pilot.lives + 1}
  defp bought(pilot, :launch, _shields), do: pilot
  defp bought(pilot, id, _shields), do: %{pilot | kit: Map.update!(pilot.kit, id, &(&1 + 1))}
end
