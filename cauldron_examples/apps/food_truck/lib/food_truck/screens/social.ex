defmodule FoodTruck.Screens.Social do
  @moduledoc """
  The social feed: for a Social Feed+ subscriber the highlighted posts above everyone's,
  for the others the offer to subscribe, which opens the subscription store. A
  subscriber manages the subscription from the toolbar: its renewal, the feed's settings
  and help with purchases.
  """

  import CauldronNative.UI

  alias FoodTruck.{Look, Shop, Social, Store}

  @doc "The Social Feed screen for `state`."
  @spec page(map()) :: CauldronNative.UI.Node.t()
  def page(state) do
    plus? = Shop.subscribed?(state.shop)
    now = state.started_at

    screen(if(plus?, do: "Social Feed+", else: "Social Feed"), [
      list([
        if(plus?,
          do: section("Highlighted Posts", Enum.map(Social.highlighted(now), &post/1)),
          else: section(nil, [native(:plus_marketing, on_start: {:shop, :open_store})])
        ),
        section("Posts", Enum.map(Social.posts(now), &post/1))
      ]),
      if(plus?,
        do:
          toolbar([
            button("Subscription Options",
              icon: :add_circle,
              ios: "plus.bubble",
              android: "AddComment",
              style: :icon,
              on_tap: {:shop, :open_settings}
            )
          ])
      ),
      store_sheet(state.shop),
      settings_sheet(state)
    ])
  end

  defp post(post) do
    donut = Store.donut(post.favorite)

    hstack(
      [
        donut && Look.avatar(donut, 35),
        vstack(
          [
            text(post.message, modifiers: [font: :title3]),
            Look.tags(post.tags, :leading),
            text(Look.post_date(post.posted_at),
              modifiers: [font: :caption, foreground: :secondary]
            )
          ],
          alignment: :leading,
          spacing: 6
        )
      ],
      alignment: :top,
      spacing: 8,
      id: post.id,
      modifiers: [padding: [vertical: 4]]
    )
  end

  defp store_sheet(shop) do
    sheet(
      [
        native(:subscription_store,
          plans: Shop.plans(shop),
          note: shop.note,
          on_subscribe: {:shop, :subscribe},
          on_redeem: {:shop, :redeem},
          on_close: {:shop, :close_store}
        )
      ],
      shown: shop.store_open?,
      on_dismiss: {:shop, :close_store}
    )
  end

  defp settings_sheet(state) do
    shop = state.shop

    sheet(
      [
        navigation(
          [settings_screen(state) | Enum.map(shop.pushed, &pushed(&1, shop))],
          on_back: {:shop, :back}
        )
      ],
      shown: shop.settings_open?,
      on_dismiss: {:shop, :close_settings}
    )
  end

  defp settings_screen(state) do
    screen("Manage Social Feed+", [
      list([
        section("Your subscription", [
          vstack(
            [
              text(Shop.current_name(state.shop), modifiers: [font: :headline, bold: true]),
              text(Shop.renewal(state.shop),
                modifiers: [font: :subheadline, foreground: :secondary]
              )
            ],
            alignment: :leading
          ),
          button("Manage subscription", style: :plain, on_tap: {:shop, :manage})
        ]),
        section("Settings", [
          toggle("Highlight Social Feed+ posts",
            value: state.plus_settings.highlight,
            on_change: {:plus_setting, :highlight}
          ),
          toggle("Advanced engagement tools",
            value: state.plus_settings.advanced,
            on_change: {:plus_setting, :advanced}
          ),
          label("Social-media providers", icon: :share, ios: "person.2.wave.2", android: "Groups")
        ]),
        support(state.window)
      ]),
      toolbar([
        button("Dismiss",
          icon: :close,
          ios: "xmark",
          android: "Close",
          on_tap: {:shop, :close_settings}
        )
      ])
    ])
  end

  defp support(%{mac?: true}),
    do:
      section("Subscription support", [
        button("Restore missing purchases", style: :plain, on_tap: {:shop, :restore})
      ])

  defp support(_window),
    do:
      section(nil, [
        label("Subscription support",
          icon: :info,
          ios: "questionmark.circle",
          android: "HelpOutline",
          on_tap: {:shop, :push, :support}
        )
      ])

  defp pushed(:support, _shop), do: support_screen()
  defp pushed(:refunds, shop), do: refunds_screen(shop)

  @doc "Help with purchases: managing the subscription, refunds and restoring purchases."
  @spec support_screen() :: CauldronNative.UI.Node.t()
  def support_screen do
    screen("Help with purchases", [
      list([
        button("Manage subscription", style: :plain, on_tap: {:shop, :manage}),
        label("Refund purchases",
          icon: :refresh,
          ios: "arrow.uturn.backward.circle",
          android: "Undo",
          modifiers: [foreground: :accent],
          on_tap: {:shop, :push, :refunds}
        ),
        button("Restore missing purchases", style: :plain, on_tap: {:shop, :restore})
      ])
    ])
  end

  @doc """
  The user's ten most recent purchases, one chosen to ask the store for a refund of.
  """
  @spec refunds_screen(Shop.t()) :: CauldronNative.UI.Node.t()
  def refunds_screen(shop) do
    screen("Refund purchases", [
      list(
        for transaction <- shop.transactions do
          hstack(
            [
              vstack(
                [
                  text(Shop.product_name(shop, transaction.key),
                    modifiers: [font: :headline, bold: true]
                  ),
                  text(Shop.purchase_words(transaction),
                    modifiers: [font: :subheadline, foreground: :secondary]
                  )
                ],
                alignment: :leading
              ),
              spacer(),
              if(shop.refund_choice == transaction.id,
                do:
                  icon(:check,
                    ios: "checkmark",
                    android: "Check",
                    modifiers: [foreground: :accent]
                  )
              )
            ],
            id: transaction.id,
            on_tap: {:shop, :choose_refund, transaction.id}
          )
        end
      ),
      vstack(
        [
          text("Select a purchase to refund",
            modifiers: [font: :subheadline, foreground: :secondary, padding: 16]
          ),
          button("Request a refund",
            style: :prominent,
            disabled: shop.refund_choice == nil,
            on_tap: {:shop, :refund},
            modifiers: [frame: [max_width: :infinity], padding: [horizontal: 16, bottom: 16]]
          )
        ],
        spacing: 0
      )
    ])
  end
end
