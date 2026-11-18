defmodule FoodTruck.Screens.Orders do
  @moduledoc """
  Today's orders, searched by number or donut: on a phone a list in sections by status,
  each order's donuts stacked beside its number and its count of donuts; with more room a
  table of every order with its donuts, status and date, the selected order's details
  and completion in the toolbar. An order's own screen shows its status and donuts and
  takes it a step on; a completed order shows its box closing (`completed/1`).
  """

  import CauldronNative.UI

  alias FoodTruck.{Donut, Look, Order, Store}

  @sections [placed: "New", preparing: "Preparing", ready: "Ready", completed: "Completed"]

  @doc "The Orders screen for `state`'s window, search and selected order."
  @spec page(map()) :: CauldronNative.UI.Node.t()
  def page(state) do
    orders =
      Store.orders()
      |> Enum.filter(&matches?(&1, state.search))
      |> Enum.sort_by(
        &{-Enum.find_index(Order.statuses(), fn status -> status == &1.status end), &1.number}
      )

    screen(
      "Orders",
      [content(orders, state)],
      search: state.search,
      on_search: :search,
      search_prompt: "Search"
    )
  end

  defp content(orders, %{window: %{compact: true}}) do
    list(
      for {status, title} <- @sections,
          of_status = Enum.filter(orders, &(&1.status == status)),
          of_status != [] do
        section(title, Enum.map(of_status, &row/1))
      end
    )
  end

  defp content(orders, state) do
    [
      table(
        [
          {:order, "Order"},
          {:donuts, "Donuts"},
          {:status, "Status"},
          {:date, "Date"},
          {:details, "Details", 60}
        ],
        Enum.map(orders, &table_row(&1, state.window)),
        on_select: :select_order
      ),
      toolbar([
        button("View Details",
          icon: :list,
          ios: "list.bullet.below.rectangle",
          android: "ListAlt",
          style: :icon,
          disabled: state.selected == nil,
          on_tap: {:open_order, state.selected}
        ),
        button("Complete Order",
          icon: :check_circle,
          ios: "checkmark.circle",
          android: "CheckCircle",
          style: :icon,
          disabled: state.selected == nil,
          on_tap: {:complete_order, state.selected}
        )
      ])
    ]
  end

  defp row(order) do
    hstack(
      [
        Look.stack(donuts(order), 40, modifiers: [frame: [width: 40, height: 40], padding: 2]),
        text(Order.title(order)),
        spacer(),
        text(Look.number(Order.total(order)), modifiers: [foreground: :secondary])
      ],
      spacing: 10,
      id: order.number,
      on_tap: {:open_order, order.number},
      label: Order.title(order)
    )
  end

  defp table_row(order, window) do
    side = if window.mac?, do: 20, else: 40

    %{
      id: order.number,
      order:
        hstack(
          [
            Look.stack(donuts(order), side, modifiers: [frame: [width: side, height: side]]),
            text(Order.title(order))
          ],
          spacing: 8
        ),
      donuts: Look.number(Order.total(order)),
      status:
        label(Order.status_title(order.status), [icon: :info] ++ Order.status_icon(order.status)),
      date: Look.order_date(order.created_at),
      details:
        menu(
          "Details",
          [
            button("View Details",
              icon: :list,
              ios: "list.bullet.below.rectangle",
              android: "ListAlt",
              on_tap: {:open_order, order.number}
            ),
            !Order.complete?(order) &&
              button("Complete Order",
                icon: :check,
                ios: "checkmark",
                android: "Check",
                on_tap: {:complete_order, order.number}
              )
          ]
          |> Enum.filter(& &1),
          icon: :more,
          ios: "ellipsis.circle",
          android: "MoreHoriz"
        )
    }
  end

  @doc "The screen of the order numbered `number`."
  @spec order(pos_integer()) :: CauldronNative.UI.Node.t()
  def order(number) do
    order = Store.order(number)

    screen(Order.title(order), [
      list([
        section("Status", [
          hstack([
            text(Order.status_title(order.status)),
            spacer(),
            icon(:info, Order.status_icon(order.status) ++ [modifiers: [foreground: :secondary]])
          ]),
          hstack([
            text("Order Started"),
            spacer(),
            text(Look.order_date(order.created_at), modifiers: [foreground: :secondary])
          ])
        ]),
        section(
          "Donuts",
          for {id, count} <- order.sales, donut <- [Store.donut(id)], donut != nil do
            hstack(
              [
                Look.donut(donut, 28),
                text(donut.name),
                spacer(),
                text(Look.number(count), modifiers: [foreground: :secondary])
              ],
              spacing: 12,
              id: id
            )
          end
        ),
        section(nil, [
          hstack([
            text("Total Donuts"),
            spacer(),
            text(Look.number(Order.total(order)), modifiers: [foreground: :secondary])
          ])
        ])
      ]),
      toolbar([
        button(
          Order.button_title(order.status),
          [icon: :check_circle] ++
            next_icon(order) ++
            [style: :icon, disabled: Order.complete?(order), on_tap: {:next_step, number}]
        )
      ])
    ])
  end

  defp next_icon(%Order{status: :completed}), do: [ios: "shippingbox.fill", android: "Inventory2"]
  defp next_icon(%Order{status: status}), do: Order.status_icon(status)

  @doc """
  The sheet that shows the order numbered `number` completed: its first donut going into
  its box, which closes, and the order's donuts and time.
  """
  @spec completed(pos_integer() | nil) :: CauldronNative.UI.Node.t()
  def completed(number) do
    order = number && Store.order(number)

    sheet(
      order &&
        [
          navigation([
            screen(Order.title(order), [
              vstack(
                [
                  native(:donut_box,
                    layers: order |> Order.donut_ids() |> hd() |> Store.donut() |> Donut.layers(),
                    modifiers: [frame: [max_width: 300, max_height: 300]]
                  ),
                  text("#{Order.title(order)} completed!", modifiers: [font: :headline]),
                  hstack(
                    [
                      text("#{Look.number(Order.total(order))} donuts"),
                      text("•"),
                      text(Look.time(order.completed_at || NaiveDateTime.local_now()))
                    ],
                    spacing: 4,
                    modifiers: [foreground: :secondary]
                  )
                ],
                modifiers: [padding: 16]
              ),
              toolbar([button("Done", style: :prominent, on_tap: :close_completed)])
            ])
          ])
        ],
      shown: order != nil,
      on_dismiss: :close_completed
    )
  end

  defp donuts(order),
    do: order |> Order.donut_ids() |> Enum.map(&Store.donut/1) |> Enum.reject(&is_nil/1)

  defp matches?(_order, ""), do: true

  defp matches?(order, search) do
    Order.matches?(order, search) or
      order |> Order.donut_ids() |> Enum.any?(&(Store.donut(&1) |> Donut.matches?(search)))
  end
end
