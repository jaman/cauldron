defmodule FoodTruck.Flavor do
  @moduledoc """
  The six flavours a donut's ingredients add up to, and a flavour profile: how much of
  each, as a map of flavour to strength (`profile/1`, `add/2`, `most_potent/1`).
  """

  @type t :: :salty | :sweet | :bitter | :sour | :savory | :spicy
  @type profile :: %{t() => integer()}

  @all [:salty, :sweet, :bitter, :sour, :savory, :spicy]

  @doc "The flavours, in the order the editor lists them."
  @spec all() :: [t()]
  def all, do: @all

  @doc "A profile from the strengths given, the others 0."
  @spec profile(keyword(integer())) :: profile()
  def profile(strengths), do: Map.merge(Map.new(@all, &{&1, 0}), Map.new(strengths))

  @doc "Two profiles together."
  @spec add(profile(), profile()) :: profile()
  def add(one, other), do: Map.merge(one, other, fn _flavor, a, b -> a + b end)

  @doc "The strongest flavour of `profile` and its strength; sweet when none is above 0."
  @spec most_potent(profile()) :: {t(), integer()}
  def most_potent(profile) do
    Enum.reduce(@all, {:sweet, 0}, fn flavor, {_best, strength} = best ->
      if profile[flavor] > strength, do: {flavor, profile[flavor]}, else: best
    end)
  end

  @doc "The flavour's name."
  @spec name(t()) :: String.t()
  def name(:salty), do: "Salty"
  def name(:sweet), do: "Sweet"
  def name(:bitter), do: "Bitter"
  def name(:sour), do: "Sour"
  def name(:savory), do: "Savory"
  def name(:spicy), do: "Spicy"

  @doc """
  The flavour's symbol, as `CauldronNative.UI.image/2` or `icon/2` options take it: an
  asset of the app's catalog, or for savory the platforms' smiling face.
  """
  @spec symbol(t()) :: {:asset, String.t()} | {:icon, keyword()}
  def symbol(:savory), do: {:icon, ios: "face.smiling", android: "SentimentSatisfied"}
  def symbol(flavor), do: {:asset, Atom.to_string(flavor)}
end
