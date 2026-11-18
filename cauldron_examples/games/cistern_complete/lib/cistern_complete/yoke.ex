defmodule CisternComplete.Yoke do
  @moduledoc """
  What the keeper carries: a jar balanced on the head and one hanging from each end of a
  yoke, each holding up to the tuning's `:capacity` drops, and where the keeper stands.

  A jar's mouth catches a drop over it while the drop is at the mouth's height — the head
  jar higher than the side jars. A side jar breaks before the head jar does; with the
  head jar broken the keeper is out.
  """

  @width 16
  @mouths %{head: {7.63, 8.4}, side: {9.3, 9.95}}
  @grate {7.0, 9.0}

  @type slot :: :left | :head | :right
  @type jar :: %{slot: slot(), x: float(), from: float(), until: float(), fill: non_neg_integer()}
  @type t :: %__MODULE__{centre: float(), jars: %{slot() => non_neg_integer()}}

  defstruct centre: @width / 2, jars: %{left: 0, head: 0, right: 0}

  @doc "The span of the keeper's position, in tiles, over which the keeper can pour into the cistern."
  @spec grate() :: {float(), float()}
  def grate, do: @grate

  @doc "Whether the keeper stands over the grate."
  @spec over_grate?(t()) :: boolean()
  def over_grate?(%__MODULE__{centre: centre}) do
    {low, high} = @grate
    centre >= low and centre <= high
  end

  @doc "How many jars are left."
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{jars: jars}), do: map_size(jars)

  @doc "The drops in all the jars."
  @spec water(t()) :: non_neg_integer()
  def water(%__MODULE__{jars: jars}), do: jars |> Map.values() |> Enum.sum()

  @doc "Whether every jar left is full."
  @spec all_full?(t(), pos_integer()) :: boolean()
  def all_full?(%__MODULE__{jars: jars}, capacity),
    do: map_size(jars) > 0 and Enum.all?(jars, fn {_slot, fill} -> fill >= capacity end)

  @doc "The jars left, left to right, each with its tile's left edge, the drop heights its mouth catches between, and its fill."
  @spec jars(t()) :: [jar()]
  def jars(%__MODULE__{centre: centre, jars: jars}) do
    for {slot, offset, mouth} <- [
          {:left, -1.5, :side},
          {:head, -0.5, :head},
          {:right, 0.5, :side}
        ],
        Map.has_key?(jars, slot) do
      {from, until} = Map.fetch!(@mouths, mouth)
      %{slot: slot, x: centre + offset, from: from, until: until, fill: Map.fetch!(jars, slot)}
    end
  end

  @doc "The jar whose mouth `drop` is in, or `nil`."
  @spec catching(t(), %{x: number(), y: number()}) :: jar() | nil
  def catching(%__MODULE__{} = yoke, drop) do
    Enum.find(jars(yoke), fn jar ->
      drop.x >= jar.x and drop.x < jar.x + 1 and drop.y >= jar.from and drop.y < jar.until
    end)
  end

  @doc "The yoke with one more drop in jar `slot`."
  @spec fill(t(), slot()) :: t()
  def fill(%__MODULE__{jars: jars} = yoke, slot),
    do: %{yoke | jars: Map.update!(jars, slot, &(&1 + 1))}

  @doc "The yoke with every jar emptied, and the drops that came out."
  @spec pour(t()) :: {t(), non_neg_integer()}
  def pour(%__MODULE__{jars: jars} = yoke),
    do: {%{yoke | jars: Map.new(jars, fn {slot, _fill} -> {slot, 0} end)}, water(yoke)}

  @doc """
  The yoke with a jar broken by something that came down on side `toward`: that side's
  jar, else the other side's, else the head jar.
  """
  @spec break(t(), :left | :right) :: t()
  def break(%__MODULE__{jars: jars} = yoke, toward) do
    other = if toward == :left, do: :right, else: :left
    slot = Enum.find([toward, other, :head], &Map.has_key?(jars, &1))
    %{yoke | jars: Map.delete(jars, slot)}
  end

  @doc "The yoke with jar `slot` broken."
  @spec break_jar(t(), slot()) :: t()
  def break_jar(%__MODULE__{jars: jars} = yoke, slot), do: %{yoke | jars: Map.delete(jars, slot)}

  @doc "The yoke with a broken side jar mended, empty; `nil` when there is none to mend."
  @spec mend(t()) :: t() | nil
  def mend(%__MODULE__{jars: jars} = yoke) do
    case Enum.find([:left, :right], &(not Map.has_key?(jars, &1))) do
      nil -> nil
      side -> %{yoke | jars: Map.put(jars, side, 0)}
    end
  end

  @doc "The yoke walked towards `x` by at most `step` tiles, its jars kept inside the square."
  @spec walk(t(), number(), number()) :: t()
  def walk(%__MODULE__{} = yoke, x, step) do
    wanted = clamp(yoke, x)
    gap = wanted - yoke.centre
    %{yoke | centre: yoke.centre + min(abs(gap), step) * if(gap < 0, do: -1, else: 1)}
  end

  defp clamp(yoke, x) do
    low = if Map.has_key?(yoke.jars, :left), do: 1.5, else: 0.5
    high = if Map.has_key?(yoke.jars, :right), do: @width - 1.5, else: @width - 0.5
    x |> max(low) |> min(high)
  end
end
