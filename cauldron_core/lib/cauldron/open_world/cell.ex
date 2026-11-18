defmodule Cauldron.OpenWorld.Cell do
  @moduledoc """
  One square of a `Cauldron.OpenWorld.Map`: its ground, its water and what stands on it.

    * `address` — `{column, row}`, integers; the cell covers the map from
      `{column * size, row * size}` up to the next column and row
    * `role` — `:simulated` (movers enter it and what is in it acts) or `:shown` (drawn
      and nothing more)
    * `heights` — the ground's height at `(samples + 1)²` points, little-endian 32-bit
      floats, a row along `x` for each step along `y`, starting at the cell's low
      corner. The last row and column lie on the next cells' first
    * `kinds` — `nil`, or four bytes for each of those points: how much of each of the
      game's four kinds of ground is there, 0 to 255
    * `water` — the height of the water's surface, or `nil` where there is none
    * `things` — the `Cauldron.OpenWorld.Thing`s standing in it
    * `marks` — named points, `%{name => {x, y}}`

      cell =
        Cauldron.OpenWorld.Cell.sampled({0, 0}, 64, 64.0, fn {x, y} -> :math.sin(x / 9) + y / 20 end)
  """

  alias Cauldron.OpenWorld.Thing

  @type address :: {integer(), integer()}
  @type role :: :simulated | :shown
  @type t :: %__MODULE__{
          address: address(),
          role: role(),
          heights: binary(),
          kinds: binary() | nil,
          water: float() | nil,
          things: [Thing.t()],
          marks: %{term() => {float(), float()}}
        }

  @enforce_keys [:address, :heights]
  defstruct [:address, :heights, role: :simulated, kinds: nil, water: nil, things: [], marks: %{}]

  @doc """
  A cell at `address` of a map with `samples` steps a side and cells `size` wide, its
  heights read from `height`, a function of a map point. Options: `:role`, `:water`,
  `:things`, `:marks`, and `:kinds`, a function of a map point giving the four amounts
  `{a, b, c, d}` there.
  """
  @spec sampled(address(), pos_integer(), number(), ({float(), float()} -> number()), keyword()) ::
          t()
  def sampled({column, row} = address, samples, size, height, opts \\ []) do
    points = points(column, row, samples, size)

    %__MODULE__{
      address: address,
      role: Keyword.get(opts, :role, :simulated),
      heights: for(point <- points, into: <<>>, do: <<height.(point)::little-float-32>>),
      kinds: kinds(points, Keyword.get(opts, :kinds)),
      water: Keyword.get(opts, :water),
      things: Keyword.get(opts, :things, []),
      marks: Keyword.get(opts, :marks, %{})
    }
  end

  @doc "The height at sample `{across, along}` of a cell with `samples` steps a side."
  @spec height(t(), pos_integer(), non_neg_integer(), non_neg_integer()) :: float()
  def height(%__MODULE__{heights: heights}, samples, across, along) do
    <<height::little-float-32>> = binary_part(heights, (along * (samples + 1) + across) * 4, 4)
    height
  end

  @doc "The four ground amounts at sample `{across, along}`, or `nil` for a cell without kinds."
  @spec kind(t(), pos_integer(), non_neg_integer(), non_neg_integer()) ::
          {0..255, 0..255, 0..255, 0..255} | nil
  def kind(%__MODULE__{kinds: nil}, _samples, _across, _along), do: nil

  def kind(%__MODULE__{kinds: kinds}, samples, across, along) do
    <<first, second, third, fourth>> = binary_part(kinds, (along * (samples + 1) + across) * 4, 4)
    {first, second, third, fourth}
  end

  defp points(column, row, samples, size) do
    step = size / samples

    for along <- 0..samples, across <- 0..samples do
      {column * size + across * step, row * size + along * step}
    end
  end

  defp kinds(_points, nil), do: nil

  defp kinds(points, kind) do
    for point <- points, into: <<>> do
      {first, second, third, fourth} = kind.(point)
      <<first, second, third, fourth>>
    end
  end
end
