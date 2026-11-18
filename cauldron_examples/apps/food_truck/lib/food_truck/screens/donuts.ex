defmodule FoodTruck.Screens.Donuts do
  @moduledoc """
  The menu's donuts: a gallery of icons or a list, searched by name or ingredient and
  sorted by name, popularity over a timeframe or a flavour, from which a donut opens in
  the editor; and the editor, where a donut's name and ingredients change and its
  flavour profile follows.

  Sizes follow the platform, as Apple's sample does: smaller thumbnails on the Mac,
  where the pointer is precise, and on a phone's narrow window.
  """

  import CauldronNative.UI

  alias FoodTruck.{Donut, Flavor, Ingredient, Look, Store}

  @timeframes [today: "Today", week: "Week", month: "Month", year: "Year"]

  @doc "The gallery for `state.gallery`, `state.donut_search` and `state.window`."
  @spec gallery(map()) :: CauldronNative.UI.Node.t()
  def gallery(state) do
    options = state.gallery

    donuts =
      options
      |> sort()
      |> Store.donuts()
      |> Enum.filter(&Donut.matches?(&1, state.donut_search))

    screen(
      "Donuts",
      [
        content(options.layout, donuts, state.window),
        toolbar([
          button("Create Donut",
            icon: :add,
            ios: "plus",
            android: "Add",
            style: :icon,
            on_tap: :new_donut
          ),
          menu(
            "Layout Options",
            layout_menu(options),
            [icon: :menu] ++ layout_icon(options.layout)
          )
        ])
      ],
      search: state.donut_search,
      on_search: :donut_search,
      search_prompt: "Search"
    )
  end

  defp sort(%{sort: :popularity, timeframe: timeframe}), do: {:popularity, timeframe}
  defp sort(%{sort: :flavor, flavor: flavor}), do: {:flavor, flavor}
  defp sort(%{sort: :name}), do: :name

  defp content(:grid, donuts, window) do
    {cell, thumbnail} = sizes(window)

    scroll([
      grid(Enum.map(donuts, &cell(&1, thumbnail)),
        min_width: cell,
        spacing: 20,
        modifiers: [padding: 16]
      )
    ])
  end

  defp content(:list, donuts, window) do
    side = if window.mac?, do: 30, else: 60

    list(
      for donut <- donuts do
        hstack([Look.donut(donut, side), text(donut.name)],
          spacing: 12,
          id: donut.id,
          on_tap: {:edit_donut, donut.id},
          label: donut.name
        )
      end
    )
  end

  defp sizes(%{mac?: true, width: width}) when width <= 520, do: {100, 40}
  defp sizes(%{mac?: true}), do: {150, 80}
  defp sizes(%{compact: true}), do: {100, 60}
  defp sizes(%{width: width}) when width <= 390, do: {100, 60}
  defp sizes(_window), do: {150, 100}

  defp cell(donut, thumbnail) do
    {flavor, _strength} = donut |> Donut.flavors() |> Flavor.most_potent()

    vstack(
      [
        Look.donut(donut, thumbnail),
        text(donut.name),
        hstack([Look.flavor_symbol(flavor, 14), text(Flavor.name(flavor))],
          spacing: 4,
          modifiers: [font: :subheadline, foreground: :secondary]
        )
      ],
      alignment: :center,
      id: donut.id,
      on_tap: {:edit_donut, donut.id},
      label: donut.name,
      hint: "edit this donut"
    )
  end

  defp layout_icon(:grid), do: [ios: "square.grid.2x2", android: "GridView"]
  defp layout_icon(:list), do: [ios: "list.bullet", android: "ViewList"]

  defp layout_menu(options) do
    [
      choice("Icons", options.layout == :grid, {:gallery, :layout, :grid},
        ios: "square.grid.2x2",
        android: "GridView"
      ),
      choice("List", options.layout == :list, {:gallery, :layout, :list},
        ios: "list.bullet",
        android: "ViewList"
      ),
      divider(),
      choice("Name", options.sort == :name, {:gallery, :sort, :name},
        ios: "textformat",
        android: "SortByAlpha"
      ),
      choice("Popularity", options.sort == :popularity, {:gallery, :sort, :popularity},
        ios: "trophy",
        android: "EmojiEvents"
      ),
      choice("Flavor", options.sort == :flavor, {:gallery, :sort, :flavor},
        ios: "fork.knife",
        android: "Restaurant"
      ),
      divider()
    ] ++ refinements(options)
  end

  defp refinements(%{sort: :popularity} = options) do
    for {timeframe, title} <- @timeframes,
        do: choice(title, options.timeframe == timeframe, {:gallery, :timeframe, timeframe}, [])
  end

  defp refinements(%{sort: :flavor} = options) do
    for flavor <- Flavor.all(),
        do: choice(Flavor.name(flavor), options.flavor == flavor, {:gallery, :flavor, flavor}, [])
  end

  defp refinements(_options), do: []

  defp choice(title, chosen?, event, icons) do
    icons = if chosen?, do: [ios: "checkmark", android: "Check"], else: icons
    button(title, [icon: :check] ++ icons ++ [on_tap: event])
  end

  @doc "The editor for `donut`, laid out for `window`."
  @spec editor(Donut.t(), map()) :: CauldronNative.UI.Node.t()
  def editor(%Donut{} = donut, window) do
    screen(donut.name, [editor_layout(donut, window)], large_title: false)
  end

  defp editor_layout(donut, %{compact: true}),
    do: form([section(nil, [viewer(donut)]) | fields(donut)])

  defp editor_layout(donut, _window) do
    hstack(
      [
        vstack([viewer(donut)],
          modifiers: [frame: [max_width: :infinity, max_height: :infinity]]
        ),
        divider(),
        form(fields(donut), modifiers: [frame: [width: 350]])
      ],
      spacing: 0
    )
  end

  defp viewer(donut) do
    native(:donut,
      layers: Donut.layers(donut),
      modifiers: [
        frame: [min_width: 100, max_width: :infinity, min_height: 100, max_height: :infinity],
        padding: [horizontal: 40, vertical: 16]
      ]
    )
  end

  defp fields(donut) do
    profile = Donut.flavors(donut)
    {strongest, strength} = Flavor.most_potent(profile)

    [
      section("Donut", [
        text_field("Donut Name", value: donut.name, on_change: {:donut_field, :name})
      ]),
      section("Flavor Profile", [
        native(:flavor_profile,
          top: strength,
          flavors:
            for flavor <- Flavor.all() do
              symbol =
                case Flavor.symbol(flavor) do
                  {:asset, name} -> %{asset: name}
                  {:icon, names} -> %{ios: names[:ios], android: names[:android]}
                end

              Map.merge(symbol, %{
                title: Flavor.name(flavor),
                value: max(profile[flavor], 0),
                strongest: flavor == strongest
              })
            end
        )
      ]),
      section("Ingredients", [
        picker("Dough", for(dough <- Ingredient.doughs(), do: {dough.key, dough.name}),
          value: donut.dough,
          on_change: {:donut_field, :dough}
        ),
        picker(
          "Glaze",
          [{nil, "None"} | for(glaze <- Ingredient.glazes(), do: {glaze.key, glaze.name})],
          value: donut.glaze,
          on_change: {:donut_field, :glaze}
        ),
        picker(
          "Topping",
          [
            {nil, "None"} | for(topping <- Ingredient.toppings(), do: {topping.key, topping.name})
          ],
          value: donut.topping,
          on_change: {:donut_field, :topping}
        )
      ])
    ]
  end
end
