defmodule FoodTruck.Shop do
  @moduledoc """
  What the truck sells in the app (`CauldronNative.Purchases`), as Apple's sample sells
  it: Social Feed+, monthly or yearly, which adds highlighted posts to the social feed,
  and a year of sales history, bought once.

  The app keeps a `t:t/0` in its state, asks the stores with `ask/0` when it starts,
  passes their answers, tagged `{:shop, …}`, to `answered/3`, and the shop's events
  (`{:shop, action}` and `{:shop, action, value}`) to `event/3`.
  """

  alias CauldronNative.Purchases
  alias CauldronNative.Purchases.Product

  @plans [:social_monthly, :social_yearly]
  @history :annual_history

  defstruct products: nil,
            subscription: %{current: nil, next: nil, expires: nil},
            owned: [],
            transactions: [],
            note: nil,
            store_open?: false,
            settings_open?: false,
            pushed: [],
            refund_choice: nil,
            unlock_expanded?: true

  @type t :: %__MODULE__{
          products: %{atom() => Product.t()} | nil,
          subscription: %{current: atom() | nil, next: atom() | nil, expires: DateTime.t() | nil},
          owned: [atom()],
          transactions: [Purchases.transaction()],
          note: String.t() | nil,
          store_open?: boolean(),
          settings_open?: boolean(),
          pushed: [:support | :refunds],
          refund_choice: String.t() | nil,
          unlock_expanded?: boolean()
        }

  @doc "Nothing known from the store yet."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Ask the store for the products, what the user owns and the subscription's status, and to be told of changes."
  @spec ask() :: :ok
  def ask do
    Purchases.products({:shop, :products}, [@history | @plans])
    Purchases.owned({:shop, :owned})
    Purchases.watch({:shop, :owned})
    Purchases.subscription({:shop, :subscription}, @plans)
  end

  @doc "Whether the user subscribes to Social Feed+."
  @spec subscribed?(t()) :: boolean()
  def subscribed?(%__MODULE__{subscription: %{current: current}, owned: owned}),
    do: current != nil or Enum.any?(@plans, &(&1 in owned))

  @doc "Whether the user unlocked a year of sales history."
  @spec history_unlocked?(t()) :: boolean()
  def history_unlocked?(%__MODULE__{owned: owned}), do: @history in owned

  @doc "The year of sales history, as the store sells it, or `nil` while unknown."
  @spec history_product(t()) :: Product.t() | nil
  def history_product(%__MODULE__{products: nil}), do: nil
  def history_product(%__MODULE__{products: products}), do: products[@history]

  @doc """
  The Social Feed+ plans for the subscription store: each `%{key, name, description,
  price, savings, intro}`, `savings` the yearly plan's price a month and how much it
  saves on twelve months, `intro` whether the user may start with the plan's offer.
  """
  @spec plans(t()) :: [map()]
  def plans(%__MODULE__{products: nil}), do: []

  def plans(%__MODULE__{products: products}) do
    for key <- @plans, product <- [products[key]], product != nil do
      %{
        key: Atom.to_string(key),
        name: product.name,
        description: product.description,
        price: "#{product.price}/#{period_word(product.period)}",
        savings: savings(product, products[:social_monthly]),
        intro: product.intro_eligible
      }
    end
  end

  defp period_word(%{unit: unit}), do: Atom.to_string(unit)
  defp period_word(nil), do: ""

  defp savings(%Product{period: %{unit: :year}} = yearly, %Product{amount: monthly})
       when is_number(monthly) and monthly > 0 do
    whole = monthly * 12
    saved = whole - yearly.amount

    if saved > 0,
      do: "#{yearly.price_per_month}/month (Save #{Float.round(saved / whole * 100, 1)}%)",
      else: nil
  end

  defp savings(_product, _monthly), do: nil

  @doc "The name of the plan the user subscribes to, or \"None\"."
  @spec current_name(t()) :: String.t()
  def current_name(%__MODULE__{subscription: %{current: nil}}), do: "None"
  def current_name(shop), do: product_name(shop, shop.subscription.current)

  @doc ~S(When the subscription renews or ends: "Renews for $4.99 on Nov 24, 2026".)
  @spec renewal(t()) :: String.t()
  def renewal(%__MODULE__{subscription: subscription} = shop) do
    expires = if subscription.expires, do: day(subscription.expires), else: "None"

    case shop.products && shop.products[subscription.next] do
      nil ->
        "Expires on #{expires}"

      next when subscription.next == subscription.current ->
        "Renews for #{next.price} on #{expires}"

      next ->
        "Renews to #{next.name} for #{next.price} on #{expires}"
    end
  end

  @doc "A product's name as the store gives it, or its key while the store has not answered."
  @spec product_name(t(), atom() | String.t()) :: String.t()
  def product_name(%__MODULE__{products: products}, key) do
    case products && products[key] do
      %Product{name: name} -> name
      nil -> to_string(key)
    end
  end

  @doc ~S(A purchase in words: "Subscribed Oct 24, 2026" or "Purchased Oct 24, 2026".)
  @spec purchase_words(Purchases.transaction()) :: String.t()
  def purchase_words(%{subscription?: true, purchased_at: at}), do: "Subscribed #{day(at)}"
  def purchase_words(%{purchased_at: at}), do: "Purchased #{day(at)}"

  @months ~w(January February March April May June July August September October November December)

  defp day(%DateTime{} = at), do: "#{Enum.at(@months, at.month - 1)} #{at.day}, #{at.year}"

  @doc "`shop` after the store's `answer` to the request tagged `{:shop, tag}`."
  @spec answered(t(), term(), term()) :: t()
  def answered(shop, :products, {:ok, products}),
    do: %{shop | products: Map.new(products, &{&1.key, &1}), note: nil}

  def answered(shop, :products, {:error, _reason}),
    do: %{shop | products: %{}, note: "The store isn't available right now."}

  def answered(shop, :owned, {:ok, {:owned, keys}}) do
    Purchases.subscription({:shop, :subscription}, @plans)
    %{shop | owned: keys}
  end

  def answered(shop, :subscription, {:ok, subscription}), do: %{shop | subscription: subscription}
  def answered(shop, :transactions, {:ok, transactions}), do: %{shop | transactions: transactions}

  def answered(shop, {:buy, _key}, {:ok, :purchased}) do
    Purchases.owned({:shop, :owned})
    %{shop | store_open?: false, note: nil}
  end

  def answered(shop, {:buy, _key}, {:ok, :pending}),
    do: %{shop | note: "Your purchase is waiting for approval."}

  def answered(shop, :refund, {:ok, :requested}) do
    Purchases.owned({:shop, :owned})
    %{shop | pushed: [], refund_choice: nil}
  end

  def answered(shop, _tag, :cancelled), do: shop

  def answered(shop, _tag, {:error, :unavailable}),
    do: %{shop | note: "The store isn't available right now."}

  def answered(shop, _tag, {:error, :unsupported}),
    do: %{shop | note: "This store doesn't offer that here."}

  def answered(shop, _tag, {:error, _reason}),
    do: %{shop | note: "The purchase didn't go through."}

  def answered(shop, _tag, _answer), do: shop

  @doc "`shop` after the user's `action` on the shop's controls, given `value`."
  @spec event(t(), term(), term()) :: t()
  def event(shop, :open_store, _value), do: %{shop | store_open?: true, note: nil}
  def event(shop, :close_store, _value), do: %{shop | store_open?: false}

  def event(shop, :subscribe, key) do
    Purchases.buy({:shop, {:buy, key}}, Product.key(key))
    shop
  end

  def event(shop, :unlock_history, _value) do
    Purchases.buy({:shop, {:buy, @history}}, @history)
    %{shop | unlock_expanded?: true}
  end

  def event(shop, :collapse_unlock, _value), do: %{shop | unlock_expanded?: false}
  def event(shop, :expand_unlock, _value), do: %{shop | unlock_expanded?: true}

  def event(shop, :redeem, _value) do
    Purchases.redeem_offer({:shop, :redeem})
    shop
  end

  def event(shop, :open_settings, _value), do: %{shop | settings_open?: true, pushed: []}
  def event(shop, :close_settings, _value), do: %{shop | settings_open?: false, pushed: []}
  def event(shop, :back, keep), do: %{shop | pushed: Enum.take(shop.pushed, keep - 1)}

  def event(shop, :push, :refunds) do
    Purchases.transactions({:shop, :transactions})
    %{shop | pushed: shop.pushed ++ [:refunds], refund_choice: nil}
  end

  def event(shop, :push, screen), do: %{shop | pushed: shop.pushed ++ [screen]}

  def event(shop, :manage, _value) do
    Purchases.manage_subscriptions()
    shop
  end

  def event(shop, :restore, _value) do
    Purchases.restore({:shop, :owned})
    shop
  end

  def event(shop, :choose_refund, id), do: %{shop | refund_choice: id}

  def event(%__MODULE__{refund_choice: nil} = shop, :refund, _value), do: shop

  def event(shop, :refund, _value) do
    Purchases.refund({:shop, :refund}, shop.refund_choice)
    shop
  end
end
