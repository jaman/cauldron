defmodule FoodTruck.Donut do
  @moduledoc """
  A donut on the truck's menu: a dough, and maybe a glaze and a topping, each one of the
  truck's ingredients (`FoodTruck.Ingredient`) by key. Its flavour profile is its
  ingredients' together (`flavors/1`), and its picture their pictures one over the other
  (`layers/2`). The menu starts as `all/0`.
  """

  alias FoodTruck.{Flavor, Ingredient}

  @enforce_keys [:id, :name, :dough]
  defstruct [:id, :name, :dough, glaze: nil, topping: nil]

  @type id :: non_neg_integer()
  @type t :: %__MODULE__{
          id: id() | nil,
          name: String.t(),
          dough: atom(),
          glaze: atom() | nil,
          topping: atom() | nil
        }

  @all [
    {"The Classic", :plain, :chocolate, :sprinkles},
    {"Blueberry Frosted", :blueberry, :blueberry, :sugar_lattice},
    {"Strawberry Drizzle", :strawberry, :strawberry, :sugar_drizzle},
    {"Cosmos", :chocolate, :chocolate, :star_sprinkles},
    {"Strawberry Sprinkles", :plain, :strawberry, :star_sprinkles},
    {"Lemon Chocolate", :plain, :chocolate, :lemon_lines},
    {"Rainbow", :plain, :rainbow, nil},
    {"Picnic Basket", :chocolate, :strawberry, :blueberry_lattice},
    {"Figure Skater", :plain, :blueberry, :sugar_drizzle},
    {"Powdered Chocolate", :chocolate, nil, :powdered_sugar},
    {"Powdered Strawberry", :strawberry, nil, :powdered_sugar},
    {"Custard", :lemonade, :spicy, :lemon_lines},
    {"Super Lemon", :lemonade, :lemon, :sprinkles},
    {"Fire Zest", :lemonade, :spicy, :spicy_sauce_drizzle},
    {"Black Raspberry", :plain, :chocolate, :blueberry_drizzle},
    {"Daytime", :lemonade, :rainbow, nil},
    {"Nighttime", :chocolate, :chocolate, :chocolate_drizzle}
  ]

  @doc "The menu the truck starts with, ids from 0."
  @spec all() :: [t()]
  def all do
    for {{name, dough, glaze, topping}, id} <- Enum.with_index(@all),
        do: %__MODULE__{id: id, name: name, dough: dough, glaze: glaze, topping: topping}
  end

  @doc "A new donut for the editor, with the id it will get on the menu."
  @spec new(id()) :: t()
  def new(id),
    do: %__MODULE__{
      id: id,
      name: "New Donut",
      dough: :plain,
      glaze: :chocolate,
      topping: :sprinkles
    }

  @doc "The donut's ingredients, dough first."
  @spec ingredients(t()) :: [Ingredient.t()]
  def ingredients(%__MODULE__{} = donut) do
    [
      Ingredient.fetch!(:dough, donut.dough),
      donut.glaze && Ingredient.fetch!(:glaze, donut.glaze),
      donut.topping && Ingredient.fetch!(:topping, donut.topping)
    ]
    |> Enum.reject(&is_nil/1)
  end

  @doc "The donut's flavour profile, its ingredients' together."
  @spec flavors(t()) :: Flavor.profile()
  def flavors(%__MODULE__{} = donut),
    do:
      donut
      |> ingredients()
      |> Enum.map(& &1.flavors)
      |> Enum.reduce(Flavor.profile([]), &Flavor.add/2)

  @doc """
  The donut's pictures, dough first, drawn one over the other: each a catalog name
  without its `-full` or `-thumb`, which the donut view adds, the thumbnail for a picture
  128 points across or smaller.
  """
  @spec layers(t()) :: [String.t()]
  def layers(%__MODULE__{} = donut), do: donut |> ingredients() |> Enum.map(&Ingredient.picture/1)

  @doc "Whether the donut's name or one of its ingredients' names holds `search`."
  @spec matches?(t(), String.t()) :: boolean()
  def matches?(_donut, ""), do: true

  def matches?(%__MODULE__{} = donut, search) do
    wanted = String.downcase(search)
    names = [donut.name | Enum.map(ingredients(donut), & &1.name)]
    Enum.any?(names, &String.contains?(String.downcase(&1), wanted))
  end
end
