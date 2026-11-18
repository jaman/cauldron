defmodule CauldronNative.Purchases do
  @moduledoc """
  In-app purchases: StoreKit on iOS, tvOS and macOS, Google Play Billing on Android.

  The app's config names its products (`purchases:`, `CauldronNative.Build.App`), each
  by a key and its type:

      purchases: [pro: [type: :non_consumable, name: "Food Truck Pro", price: "4.99"]]

  A product's id in App Store Connect and the Play Console is the app's id, a dot and
  the key: `io.github.jaman.foodtruck.pro`. The name and price in the config are for
  local testing (the StoreKit configuration the Xcode project carries); the stores'
  own are the ones shown to users, through `products/2`.

  Answers arrive as `CauldronNative.Device`'s do, `{:device, tag, answer}`:

    * `products/2` — `{:ok, [CauldronNative.Purchases.Product.t()]}`, the products the
      store has, so missing ones are left out
    * `buy/2` — `{:ok, :purchased}`, `{:ok, :pending}` (waiting on a parent's approval
      or a payment), or `:cancelled`
    * `owned/1` and `restore/1` — `{:ok, {:owned, keys}}`, the non-consumables and
      subscriptions the user has now
    * `watch/1` — `{:ok, {:owned, keys}}` again each time that changes outside a
      `buy/2`: a pending purchase approved, a refund, a purchase on another device
    * `subscription/2` — `{:ok, %{current: key, next: key, expires: expires}}`: the
      subscription among `keys` the user has now, the one it renews to, and when the
      current period ends (a `DateTime`); `nil` for each the store does not know
      (Google Play gives no end date)
    * `transactions/1` — `{:ok, [transaction()]}`, the user's ten most recent purchases
      that were not refunded, newest first
    * `refund/2` — `{:ok, :requested}` once the user sent the request, or `:cancelled`
    * `redeem_offer/1` — `{:ok, :finished}` when the sheet closes (on Android, once
      Google Play's redeem page opens); a redeemed code reaches `watch/1` as what the
      user owns

  The errors are `:unavailable` (no store: a simulator without a StoreKit
  configuration, an emulator without Google Play, no network), `:not_found` (the store
  has no such product), `:unsupported` (a refund on Android or Apple TV, whose users ask
  for one in the store) and `:failed`.

  A consumable is the app's to keep count of: `{:ok, :purchased}` is the moment to add
  it. The others are the store's to remember: ask `owned/1` when the app starts.

      def mount(_params) do
        CauldronNative.Purchases.owned(:owned)
        CauldronNative.Purchases.watch(:owned)
        %{pro?: false}
      end

      def handle_info({:device, :owned, {:ok, {:owned, keys}}}, state),
        do: %{state | pro?: :pro in keys}
  """

  alias CauldronNative.Device.Request

  @typedoc "A purchase: the store's `id` for it, the product's `key`, when it was bought, and whether it is a subscription."
  @type transaction :: %{
          id: String.t(),
          key: atom() | String.t(),
          purchased_at: DateTime.t(),
          subscription?: boolean()
        }

  @doc "Ask the store for the products of `keys`."
  @spec products(term(), [atom()]) :: :ok
  def products(tag, keys), do: Request.send(tag, "purchase_products", %{keys: keys})

  @doc "Buy the product `key`; the store shows its own confirmation."
  @spec buy(term(), atom()) :: :ok
  def buy(tag, key), do: Request.send(tag, "purchase_buy", %{key: key})

  @doc "Ask which products the user owns."
  @spec owned(term()) :: :ok
  def owned(tag), do: Request.send(tag, "purchase_owned", %{})

  @doc "Ask the store to bring back purchases made with the user's account, then which they own."
  @spec restore(term()) :: :ok
  def restore(tag), do: Request.send(tag, "purchase_restore", %{})

  @doc "Be told what the user owns each time it changes."
  @spec watch(term()) :: :ok
  def watch(tag), do: Request.send(tag, "purchase_watch", %{})

  @doc "Ask which of the subscriptions `keys` the user has, what it renews to, and when."
  @spec subscription(term(), [atom()]) :: :ok
  def subscription(tag, keys), do: Request.send(tag, "purchase_subscription", %{keys: keys})

  @doc "Ask for the user's recent purchases."
  @spec transactions(term()) :: :ok
  def transactions(tag), do: Request.send(tag, "purchase_transactions", %{})

  @doc "Show the store's sheet that asks for a refund of the purchase `id` (`t:transaction/0`)."
  @spec refund(term(), String.t()) :: :ok
  def refund(tag, id), do: Request.send(tag, "purchase_refund", %{transaction: id})

  @doc """
  Show the store's own page of the user's subscriptions: the App Store's sheet on iOS,
  its page on the Mac, Google Play's on Android.
  """
  @spec manage_subscriptions() :: :ok
  def manage_subscriptions, do: Request.send(nil, "purchase_manage", %{})

  @doc "Show the store's sheet for redeeming an offer code."
  @spec redeem_offer(term()) :: :ok
  def redeem_offer(tag), do: Request.send(tag, "purchase_redeem", %{})
end
