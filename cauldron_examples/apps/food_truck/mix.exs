defmodule FoodTruck.MixProject do
  use Mix.Project

  def project do
    [
      app: :food_truck,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_options: [warnings_as_errors: true],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [food_truck: [include_erts: false, strip_beams: true]],
      cauldron_native: [
        name: "Food Truck",
        id: "io.github.jaman.foodtruck",
        orientation: :any,
        icon: "assets/icon.png",
        icon_background: "#7F85F7",
        launch: [background: "#7F85F7"],
        assets: "assets/FoodTruck.xcassets",
        window: [width: 1000, height: 650, min_width: 600, min_height: 450],
        url_schemes: ["foodtruck"],
        permissions: [notifications: "Tells you when an order's donuts are done"],
        maps: [android_key: {:env, "FOOD_TRUCK_MAPS_KEY"}],
        widgets: [
          orders: [
            name: "Orders",
            description: "Information about Food Truck's orders and daily quotas.",
            sizes: [:small, :circular, :rectangular, :inline]
          ],
          daily_donut: [
            name: "Daily Donut",
            description: "Showcasing the latest trending donuts.",
            sizes: [:small, :medium, :large, :extra_large]
          ],
          parking_spot: [
            name: "Parking Spot",
            description: "Information about your Food Truck's parking spot.",
            sizes: [:circular, :rectangular, :inline]
          ]
        ],
        live_activities: true,
        purchases: [
          annual_history: [
            type: :non_consumable,
            name: "Full year of history",
            price: "0.99",
            description: "Data and insights that cover an entire year"
          ],
          social_monthly: [
            type: :subscription,
            period: :month,
            name: "Social Feed+ Monthly Plan",
            price: "4.99",
            description: "Access advanced social-feed tools",
            intro: [price: "2.49", period: :month, periods: 3, mode: :pay_as_you_go]
          ],
          social_yearly: [
            type: :subscription,
            period: :year,
            name: "Social Feed+ Yearly Plan",
            price: "49.99",
            description: "Advanced tools at a greater value",
            intro: [price: "8.99", period: :quarter, mode: :pay_up_front]
          ]
        ],
        privacy: [tracking: false, collects: []],
        encryption: :exempt
      ]
    ]
  end

  def application, do: [extra_applications: [:logger], mod: {FoodTruck.Application, []}]

  defp deps do
    [
      {:cauldron_native, path: "../../../cauldron_native"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
