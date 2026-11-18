defmodule FoodTruck.Look do
  @moduledoc """
  Pieces the truck's screens share: donuts drawn from their ingredients' pictures (the
  app's `donut`, `donut_stack` and `tag_flow` native views), the Truck screen's card
  headings, tags, and dates as the sample writes them.
  """

  import CauldronNative.UI

  alias FoodTruck.{City, Donut, Ingredient, Store}

  @doc "`donut`, `size` points across."
  @spec donut(Donut.t(), number(), keyword()) :: CauldronNative.UI.Node.t()
  def donut(%Donut{} = donut, size, opts \\ []) do
    native(
      :donut,
      [layers: Donut.layers(donut), modifiers: [frame: [width: size, height: size]]] ++ opts
    )
  end

  @doc "`donut` in a circle of its dough's colour, as a post's author shows."
  @spec avatar(Donut.t(), number()) :: CauldronNative.UI.Node.t()
  def avatar(%Donut{} = donut, size) do
    dough = Ingredient.fetch!(:dough, donut.dough)

    native(:donut,
      layers: Donut.layers(donut),
      background: Ingredient.background(dough),
      modifiers: [frame: [width: size, height: size]]
    )
  end

  @doc "Up to three of `donuts` stacked diagonally, `size` points across."
  @spec stack([Donut.t()], number(), keyword()) :: CauldronNative.UI.Node.t()
  def stack(donuts, size, opts \\ []) do
    native(
      :donut_stack,
      [donuts: Enum.map(donuts, &Donut.layers/1), modifiers: [frame: [width: size, height: size]]] ++
        opts
    )
  end

  @doc "Tags in rows that wrap, each a title, a donut or a city (`FoodTruck.Social.tag/0`)."
  @spec tags([FoodTruck.Social.tag()], :center | :leading) :: CauldronNative.UI.Node.t()
  def tags(tags, alignment) do
    donuts = Map.new(Store.donuts(), &{&1.id, &1})
    native(:tag_flow, tags: Enum.map(tags, &tag(&1, donuts)), alignment: alignment)
  end

  defp tag({:title, title}, _donuts), do: %{kind: "title", title: title}

  defp tag({:donut, id}, donuts),
    do: %{kind: "donut", title: donuts[id].name, layers: Donut.layers(donuts[id])}

  defp tag({:city, id}, _donuts), do: %{kind: "city", title: City.fetch!(id).name}

  @doc """
  A Truck card's heading: its icon, `title` and a chevron in the accent colour, which
  opens the card's screen (`{:card, panel}`).
  """
  @spec card_heading(String.t(), keyword(), term()) :: CauldronNative.UI.Node.t()
  def card_heading(title, icon, panel) do
    hstack(
      [
        heading_icon(icon),
        text(title, modifiers: [font: :headline, foreground: :accent]),
        icon(:forward,
          ios: "chevron.forward",
          android: "ChevronRight",
          modifiers: [font: :footnote, bold: true, foreground: :secondary, opacity: 0.6]
        ),
        spacer()
      ],
      spacing: 4,
      on_tap: {:card, panel},
      label: title,
      hint: "open #{title}"
    )
  end

  defp heading_icon({:asset, name}),
    do: image({:asset, name}, modifiers: [frame: [width: 20, height: 18], foreground: :secondary])

  defp heading_icon(names),
    do: icon(:list, names ++ [modifiers: [font: :headline, foreground: :secondary]])

  @doc "A flavour's symbol, `size` points tall."
  @spec flavor_symbol(FoodTruck.Flavor.t(), number()) :: CauldronNative.UI.Node.t()
  def flavor_symbol(flavor, size) do
    case FoodTruck.Flavor.symbol(flavor) do
      {:asset, name} -> image({:asset, name}, modifiers: [frame: [width: size, height: size]])
      {:icon, names} -> icon(:face, names ++ [modifiers: [frame: [width: size, height: size]]])
    end
  end

  @doc ~S(A moment as the orders show it: "Today, 9:41 AM", "Yesterday, 9:41 AM" or "10/24/2026, 9:41 AM".)
  @spec order_date(NaiveDateTime.t()) :: String.t()
  def order_date(%NaiveDateTime{} = at), do: "#{day(at, :numeric)}, #{time(at)}"

  @doc ~S(A moment as the posts show it: "Today, 9:41 AM" or "Oct 22, 2026, 9:41 AM".)
  @spec post_date(NaiveDateTime.t()) :: String.t()
  def post_date(%NaiveDateTime{} = at), do: "#{day(at, :abbreviated)}, #{time(at)}"

  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

  @doc ~S(A day as "Oct 24".)
  @spec short_day(Date.t()) :: String.t()
  def short_day(%Date{month: month, day: day}), do: "#{Enum.at(@months, month - 1)} #{day}"

  @doc ~S(The time of `at` as "9:41 AM".)
  @spec time(NaiveDateTime.t()) :: String.t()
  def time(%NaiveDateTime{} = at) do
    hour = rem(at.hour + 11, 12) + 1
    half = if at.hour < 12, do: "AM", else: "PM"
    "#{hour}:#{at.minute |> Integer.to_string() |> String.pad_leading(2, "0")} #{half}"
  end

  defp day(at, style) do
    date = NaiveDateTime.to_date(at)
    today = NaiveDateTime.to_date(NaiveDateTime.local_now())

    cond do
      date == today -> "Today"
      date == Date.add(today, -1) -> "Yesterday"
      style == :numeric -> "#{date.month}/#{date.day}/#{date.year}"
      true -> "#{short_day(date)}, #{date.year}"
    end
  end

  @doc ~S(A whole number with thousands separated: "1,234".)
  @spec number(integer()) :: String.t()
  def number(value) when value < 0, do: "-" <> number(-value)

  def number(value) do
    value
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  @doc "Degrees Celsius in Fahrenheit, as the sample shows its temperatures."
  @spec fahrenheit(number()) :: float()
  def fahrenheit(celsius), do: celsius * 9 / 5 + 32
end
