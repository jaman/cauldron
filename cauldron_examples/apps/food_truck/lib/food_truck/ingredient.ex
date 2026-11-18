defmodule FoodTruck.Ingredient do
  @moduledoc """
  A donut's dough, glaze or topping: its name, the flavours it adds, and the picture of
  it in the app's catalog, a full size one and a thumbnail (`picture/1`). The truck's
  ingredients are `doughs/0`, `glazes/0` and `toppings/0`, toppings also grouped as the
  editor lists them (`topping_groups/0`).
  """

  alias FoodTruck.Flavor

  @enforce_keys [:key, :kind, :name, :picture, :flavors]
  defstruct @enforce_keys

  @type kind :: :dough | :glaze | :topping
  @type t :: %__MODULE__{
          key: atom(),
          kind: kind(),
          name: String.t(),
          picture: String.t(),
          flavors: Flavor.profile()
        }

  @doughs [
    blueberry: {"Blueberry Dough", "blue", salty: 1, sweet: 2, savory: 2},
    chocolate: {"Chocolate Dough", "brown", salty: 1, sweet: 3, bitter: 1, sour: -1, savory: 1},
    sour_candy: {"Sour Candy", "green", salty: 1, sweet: 2, sour: 3, savory: -1},
    strawberry: {"Strawberry Dough", "pink", sweet: 3, savory: 2},
    plain: {"Plain", "plain", salty: 1, sweet: 1, bitter: 1, savory: 2},
    powdered: {"Powdered Dough", "white", salty: -1, sweet: 4, savory: 1},
    lemonade: {"Lemonade", "yellow", salty: 1, sweet: 1, sour: 3}
  ]

  @glazes [
    blueberry: {"Blueberry Spread", "blue", salty: 1, sweet: 3, sour: -1, savory: 2},
    chocolate: {"Chocolate Glaze", "brown", salty: 1, sweet: 1, bitter: 1, savory: 2},
    sour_candy: {"Sour Candy Glaze", "green", bitter: 1, sour: 3, savory: -1, spicy: 2},
    spicy: {"Spicy Spread", "orange", salty: 1, sour: 1, spicy: 3},
    strawberry: {"Strawberry Glaze", "pink", salty: 1, sweet: 2, savory: 2},
    lemon: {"Lemon Spread", "yellow", sweet: 1, sour: 3, spicy: 1},
    rainbow: {"Rainbow Glaze", "rainbow", salty: 2, sweet: 2, spicy: 1}
  ]

  @other [
    powdered_sugar: {"Powdered Sugar", "powdersugar", salty: 1, sweet: 4},
    sprinkles: {"Sprinkles", "sprinkles", sweet: 3, savory: 2},
    star_sprinkles: {"Star Sprinkles", "sprinkles-stars", sweet: 3, savory: 2}
  ]

  @lattices [
    blueberry_lattice:
      {"Blueberry Lattice", "crisscross-blue", salty: 1, sweet: 2, bitter: 1, sour: -1, savory: 2},
    chocolate_lattice: {"Chocolate Lattice", "crisscross-brown", salty: 2, sweet: 1, bitter: 2},
    sour_apple_lattice:
      {"Sour Apple Lattice", "crisscross-green", sweet: 1, sour: 3, savory: -1, spicy: 2},
    spicy_sauce_lattice:
      {"Spicy Sauce Lattice", "crisscross-orange", salty: 1, savory: 1, spicy: 3},
    strawberry_lattice: {"Strawberry Lattice", "crisscross-pink", salty: 1, sweet: 2, savory: 2},
    sugar_lattice: {"Sugar Lattice", "crisscross-white", salty: 2, sweet: 3},
    lemon_lattice: {"Lemon Lattice", "crisscross-yellow", bitter: 2, sour: 2, spicy: 1}
  ]

  @lines [
    blueberry_lines:
      {"Blueberry Lines", "crisscross-blue", salty: 1, sweet: 2, bitter: 1, sour: -1, savory: 2},
    chocolate_lines: {"Chocolate Lines", "straight-brown", salty: 2, sweet: 1, bitter: 2},
    sour_apple_lines:
      {"Sour Apple Lines", "straight-green", sweet: 1, sour: 3, savory: -1, spicy: 2},
    spicy_sauce_lines: {"Spicy Sauce Lines", "straight-orange", salty: 1, savory: 1, spicy: 3},
    strawberry_lines: {"Strawberry Lines", "straight-pink", salty: 1, sweet: 2, savory: 2},
    sugar_lines: {"Sugar Lines", "straight-white", salty: 2, sweet: 3},
    lemon_lines: {"Lemon Lines", "straight-yellow", bitter: 2, sour: 2, spicy: 1}
  ]

  @drizzles [
    blueberry_drizzle:
      {"Blueberry Drizzle", "zigzag-blue", salty: 1, sweet: 2, bitter: 1, sour: -1, savory: 2},
    chocolate_drizzle: {"Chocolate Drizzle", "zigzag-brown", salty: 2, sweet: 1, bitter: 2},
    sour_apple_drizzle:
      {"Sour Apple Drizzle", "zigzag-green", sweet: 1, sour: 3, savory: -1, spicy: 2},
    spicy_sauce_drizzle: {"Spicy Sauce Drizzle", "zigzag-orange", salty: 1, savory: 1, spicy: 3},
    strawberry_drizzle: {"Strawberry Drizzle", "zigzag-pink", salty: 1, sweet: 2, savory: 2},
    sugar_drizzle: {"Sugar Drizzle", "zigzag-white", salty: 2, sweet: 3},
    lemon_drizzle: {"Lemon Drizzle", "zigzag-yellow", bitter: 2, sour: 2, spicy: 1}
  ]

  @doc "The doughs."
  @spec doughs() :: [t()]
  def doughs, do: built(:dough, @doughs)

  @doc "The glazes."
  @spec glazes() :: [t()]
  def glazes, do: built(:glaze, @glazes)

  @doc "The toppings."
  @spec toppings() :: [t()]
  def toppings, do: Enum.flat_map(topping_groups(), &elem(&1, 1))

  @doc "The toppings in the editor's groups: others, lattices, lines and drizzles."
  @spec topping_groups() :: [{atom(), [t()]}]
  def topping_groups,
    do: [
      other: built(:topping, @other),
      lattices: built(:topping, @lattices),
      lines: built(:topping, @lines),
      drizzles: built(:topping, @drizzles)
    ]

  @doc "The dough, glaze or topping (`kind`) called `key`."
  @spec fetch!(kind(), atom()) :: t()
  def fetch!(:dough, key), do: Enum.find(doughs(), &(&1.key == key)) || missing!(:dough, key)
  def fetch!(:glaze, key), do: Enum.find(glazes(), &(&1.key == key)) || missing!(:glaze, key)

  def fetch!(:topping, key),
    do: Enum.find(toppings(), &(&1.key == key)) || missing!(:topping, key)

  @doc "The catalog name of the ingredient's picture, without its `-full` or `-thumb`."
  @spec picture(t()) :: String.t()
  def picture(%__MODULE__{kind: kind, picture: picture}), do: "#{kind}/#{picture}"

  @doc "The catalog name of a dough's background colour."
  @spec background(t()) :: String.t()
  def background(%__MODULE__{kind: :dough, picture: picture}), do: "dough/#{picture}-bg"

  defp built(kind, table) do
    for {key, {name, picture, flavors}} <- table do
      %__MODULE__{
        key: key,
        kind: kind,
        name: name,
        picture: picture,
        flavors: Flavor.profile(flavors)
      }
    end
  end

  defp missing!(kind, key), do: raise(ArgumentError, "no #{kind} called #{inspect(key)}")
end
