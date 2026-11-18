defmodule FoodTruck.City do
  @moduledoc """
  A city the truck parks in, with its parking spots: each a name, a place, and how far
  away the map's camera looks at it from, in metres.
  """

  @enforce_keys [:id, :name, :spots]
  defstruct @enforce_keys

  @type spot :: %{name: String.t(), at: {float(), float()}, camera: number()}
  @type t :: %__MODULE__{id: atom(), name: String.t(), spots: [spot()]}

  @cities [
    cupertino:
      {"Cupertino",
       [
         {"Apple Park", {37.3348, -122.0090}, 1100},
         {"Infinite Loop", {37.3317, -122.0302}, 1000}
       ]},
    san_francisco:
      {"San Francisco",
       [
         {"Coit Tower", {37.8024, -122.4058}, 300},
         {"Fisherman's Wharf", {37.8099, -122.4103}, 700},
         {"Ferry Building", {37.7956, -122.3935}, 450},
         {"Golden Gate Bridge", {37.8199, -122.4783}, 2000},
         {"Oracle Park", {37.7786, -122.3893}, 650},
         {"The Castro Theatre", {37.7609, -122.4350}, 400},
         {"Sutro Tower", {37.7552, -122.4528}, 1000},
         {"Bay Bridge", {37.7983, -122.3778}, 1000}
       ]},
    london:
      {"London",
       [
         {"Big Ben", {51.4994, -0.1245}, 850},
         {"Buckingham Palace", {51.5014, -0.1419}, 750},
         {"Marble Arch", {51.5131, -0.1589}, 1000},
         {"Piccadilly Circus", {51.510067, -0.133869}, 1000},
         {"Shakespeare's Globe", {51.5081, -0.0972}, 1000},
         {"Tower Bridge", {51.5055, -0.0754}, 1000}
       ]}
  ]

  @doc "The cities, Cupertino first."
  @spec all() :: [t()]
  def all do
    for {id, {name, spots}} <- @cities do
      %__MODULE__{
        id: id,
        name: name,
        spots: for({spot, at, camera} <- spots, do: %{name: spot, at: at, camera: camera})
      }
    end
  end

  @doc "The city with `id`."
  @spec fetch!(atom()) :: t()
  def fetch!(id), do: Enum.find(all(), &(&1.id == id)) || raise(ArgumentError, "no city #{id}")
end
