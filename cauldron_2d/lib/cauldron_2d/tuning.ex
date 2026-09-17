defmodule Cauldron2D.Tuning do
  @moduledoc """
  Every number that decides how a game plays, in one value the game carries in its
  state and a settings page can show and change.

      spec = [
        ball_speed: [default: 10.0, limits: {4.0, 24.0}, doc: "tiles a second"],
        drop_chance: [default: 7],
        widths: [default: %{narrow: 2.0, wide: 5.5}]
      ]

      tuning = Cauldron2D.Tuning.new(spec, ball_speed: 14.0)
      Cauldron2D.Tuning.get(tuning, :ball_speed)
      Cauldron2D.Tuning.put(tuning, :ball_speed, 99.0)   # 24.0, the top of its range

  A setting with `:limits` is clamped by `put/3` and moved by `step/3` in twentieths of
  its range; one without takes any value. `describe/1` lists the settings in the order
  declared, for a settings page.
  """

  @type key :: atom()
  @type spec :: [{key(), keyword()}]
  @type t :: %__MODULE__{spec: spec(), values: %{key() => term()}}

  @enforce_keys [:spec, :values]
  defstruct [:spec, :values]

  @steps 20

  @doc "A tuning from `spec` with `overrides` over the defaults; an override for a key not in the spec raises `KeyError`."
  @spec new(spec(), keyword() | map()) :: t()
  def new(spec, overrides \\ []) do
    defaults = Map.new(spec, fn {key, options} -> {key, Keyword.fetch!(options, :default)} end)
    tuning = %__MODULE__{spec: spec, values: defaults}
    Enum.reduce(overrides, tuning, fn {key, value}, acc -> put(acc, key, value) end)
  end

  @doc "The value of `key`; raises `KeyError` for a key not in the spec."
  @spec get(t(), key()) :: term()
  def get(%__MODULE__{values: values}, key), do: Map.fetch!(values, key)

  @doc "The setting keys, in the order declared."
  @spec keys(t()) :: [key()]
  def keys(%__MODULE__{spec: spec}), do: Keyword.keys(spec)

  @doc "The `{low, high}` `put/3` clamps `key` to, or `nil` for a setting without limits."
  @spec limits(t(), key()) :: {number(), number()} | nil
  def limits(%__MODULE__{spec: spec}, key),
    do: spec |> Keyword.fetch!(key) |> Keyword.get(:limits)

  @doc "Change `key` to `value`, clamped into its limits when it has them; raises `KeyError` for a key not in the spec."
  @spec put(t(), key(), term()) :: t()
  def put(%__MODULE__{} = tuning, key, value) do
    clamped =
      case limits(tuning, key) do
        nil -> value
        {low, high} -> value |> max(low) |> min(high)
      end

    %{tuning | values: Map.put(tuning.values, key, clamped)}
  end

  @doc "Move `key` by `steps` twentieths of its range, or by `steps` itself when it has no limits."
  @spec step(t(), key(), integer()) :: t()
  def step(%__MODULE__{} = tuning, key, steps) do
    current = get(tuning, key)

    case limits(tuning, key) do
      nil -> put(tuning, key, current + steps)
      {low, high} -> put(tuning, key, current + steps * (high - low) / @steps)
    end
  end

  @doc "Every setting as `%{key, value, limits, doc}`, in the order declared."
  @spec describe(t()) :: [
          %{key: key(), value: term(), limits: {number(), number()} | nil, doc: String.t() | nil}
        ]
  def describe(%__MODULE__{spec: spec} = tuning) do
    for {key, options} <- spec do
      %{
        key: key,
        value: get(tuning, key),
        limits: Keyword.get(options, :limits),
        doc: Keyword.get(options, :doc)
      }
    end
  end
end
