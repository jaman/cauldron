defmodule Cauldron3D.Formats.Entities do
  @moduledoc """
  A map's entity text read into a list of string maps, one per `{ … }` block, in order.

      Cauldron3D.Formats.Entities.parse(~s|{ "classname" "worldspawn" }|)
      #=> [%{"classname" => "worldspawn"}]
  """

  @doc "The entities of `text`."
  @spec parse(String.t()) :: [%{String.t() => String.t()}]
  def parse(text), do: text |> blocks() |> Enum.map(&elem(&1, 1))

  @doc "The entities of `text` with the text of each block, braces included: `[{block, keys}]`."
  @spec blocks(String.t()) :: [{String.t(), %{String.t() => String.t()}}]
  def blocks(text) do
    ~r/\{([^}]*)\}/
    |> Regex.scan(text)
    |> Enum.map(fn [block, body] ->
      keys =
        ~r/"([^"]*)"\s*"([^"]*)"/
        |> Regex.scan(body, capture: :all_but_first)
        |> Map.new(fn [key, value] -> {key, value} end)

      {block, keys}
    end)
  end

  @doc "A vector value such as `\"64 -32 24\"` as `{x, y, z}` floats, or `nil`."
  @spec vector(String.t() | nil) :: {float(), float(), float()} | nil
  def vector(nil), do: nil

  def vector(text) do
    case text |> String.split() |> Enum.map(&number/1) do
      [x, y, z] -> {x, y, z}
      _ -> nil
    end
  end

  @doc "A number value as a float, or `nil`."
  @spec number(String.t() | nil) :: float() | nil
  def number(nil), do: nil

  def number(text) do
    case Float.parse(text) do
      {value, _} -> value
      :error -> nil
    end
  end
end
