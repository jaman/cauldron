defmodule CauldronNative.Purchases.Product do
  @moduledoc """
  A product the store sells in the app, as the store describes it to this user: `name`,
  `description` and `price` in the store's language and currency, ready to show.

  `key` is the product's name in the app's config (`:pro` for `purchases: [pro: …]`),
  and `type` one of `:consumable`, `:non_consumable` and `:subscription`. `amount` is the
  price as a number, for sums such as a saving. A subscription has its `period`
  (`%{unit, count}`, unit one of `:day`, `:week`, `:month` and `:year`), its price a
  month in the store's currency when the period is longer (`price_per_month`), and
  whether the user may take its introductory offer (`intro_eligible`).
  """

  @enforce_keys [:key, :name, :description, :price, :type]
  defstruct @enforce_keys ++
              [amount: nil, period: nil, price_per_month: nil, intro_eligible: false]

  @type type :: :consumable | :non_consumable | :subscription
  @type t :: %__MODULE__{
          key: atom() | String.t(),
          name: String.t(),
          description: String.t(),
          price: String.t(),
          type: type(),
          amount: float() | nil,
          period: %{unit: :day | :week | :month | :year, count: pos_integer()} | nil,
          price_per_month: String.t() | nil,
          intro_eligible: boolean()
        }

  @types %{
    "consumable" => :consumable,
    "non_consumable" => :non_consumable,
    "subscription" => :subscription
  }

  @doc "The product the native side described as `json`."
  @spec from_json(map()) :: t()
  def from_json(json) do
    %__MODULE__{
      key: key(json["key"]),
      name: json["name"],
      description: json["description"],
      price: json["price"],
      type: Map.fetch!(@types, json["type"]),
      amount: json["amount"],
      period: period(json["period"]),
      price_per_month: json["price_per_month"],
      intro_eligible: json["intro_eligible"] == true
    }
  end

  @units %{"day" => :day, "week" => :week, "month" => :month, "year" => :year}

  defp period(%{"unit" => unit, "count" => count}) when is_map_key(@units, unit),
    do: %{unit: Map.fetch!(@units, unit), count: count}

  defp period(_none), do: nil

  @doc """
  The app's key for a product key the store gave: the atom of that name, which the app's
  own code holds, or the string when no such atom exists.
  """
  @spec key(String.t()) :: atom() | String.t()
  def key(name) do
    String.to_existing_atom(name)
  rescue
    ArgumentError -> name
  end
end
