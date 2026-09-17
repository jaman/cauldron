defmodule Cauldron2D.Collision.Buckets do
  @moduledoc """
  Bodies sorted into square buckets, so that only neighbours are compared.

      buckets =
        Cauldron2D.Collision.Buckets.new(4)
        |> Cauldron2D.Collision.Buckets.insert(:ball, {10.5, 3.2}, 0.5)
        |> Cauldron2D.Collision.Buckets.insert(:coin_9, {10.9, 3.0}, 0.1)

      Cauldron2D.Collision.Buckets.pairs(buckets)       # => [{:ball, :coin_9}]
      Cauldron2D.Collision.Buckets.near(buckets, {10.0, 3.0}, 1.0)

  The bucket size is in tiles and should be at least the largest radius plus the largest
  reach queried, so that a body is never further than one bucket from anything it can touch.
  Build a fresh set each tick; there is no removal.
  """

  alias Cauldron2D.Collision

  @type id :: term()
  @type t :: %__MODULE__{size: pos_integer(), cells: %{{integer(), integer()} => [entry()]}}
  @typep entry :: {id(), Collision.point(), float()}

  defstruct [:size, cells: %{}]

  @doc "An empty set with buckets `size` tiles across."
  @spec new(pos_integer()) :: t()
  def new(size) when is_integer(size) and size > 0, do: %__MODULE__{size: size}

  @doc "Add a body under `id`."
  @spec insert(t(), id(), Collision.point(), number()) :: t()
  def insert(%__MODULE__{} = buckets, id, pos, radius) do
    key = key_of(buckets, pos)

    %{
      buckets
      | cells:
          Map.update(buckets.cells, key, [{id, pos, radius / 1}], &[{id, pos, radius / 1} | &1])
    }
  end

  @doc "Ids of every body within `reach` of `pos`, measured surface to point."
  @spec near(t(), Collision.point(), number()) :: [id()]
  def near(%__MODULE__{} = buckets, pos, reach) do
    buckets
    |> around(pos)
    |> Enum.filter(fn {_id, other, radius} ->
      Collision.circles_overlap?(pos, reach, other, radius)
    end)
    |> Enum.map(&elem(&1, 0))
  end

  @doc "Every pair of overlapping bodies, each once, as `{id, id}` with the smaller id first."
  @spec pairs(t()) :: [{id(), id()}]
  def pairs(%__MODULE__{} = buckets) do
    for {key, entries} <- buckets.cells,
        {id, pos, radius} <- entries,
        {other_id, other_pos, other_radius} <- neighbours(buckets, key),
        id < other_id,
        Collision.circles_overlap?(pos, radius, other_pos, other_radius),
        uniq: true,
        do: {id, other_id}
  end

  defp around(buckets, pos), do: neighbours(buckets, key_of(buckets, pos))

  defp neighbours(buckets, {kx, ky}) do
    for dx <- -1..1,
        dy <- -1..1,
        entry <- Map.get(buckets.cells, {kx + dx, ky + dy}, []),
        do: entry
  end

  defp key_of(%__MODULE__{size: size}, {x, y}), do: {floor(x / size), floor(y / size)}
end
