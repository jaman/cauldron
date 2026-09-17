defmodule Linocut.Palette do
  @moduledoc """
  Colour specifications and the named colours a picture may use.

      Linocut.Palette.color("#c33")      # => {204, 51, 51, 255}
      Linocut.Palette.color(:cyan)       # => {0, 255, 255, 255}
      Linocut.Palette.color({1, 2, 3})   # => {1, 2, 3, 255}
  """

  @type spec :: String.t() | atom() | {0..255, 0..255, 0..255} | {0..255, 0..255, 0..255, 0..255}

  @names %{
    black: {0, 0, 0},
    white: {255, 255, 255},
    red: {255, 0, 0},
    green: {0, 255, 0},
    blue: {0, 0, 255},
    yellow: {255, 255, 0},
    cyan: {0, 255, 255},
    magenta: {255, 0, 255},
    orange: {255, 165, 0},
    purple: {128, 0, 128},
    pink: {255, 105, 180},
    brown: {139, 69, 19},
    gray: {128, 128, 128},
    grey: {128, 128, 128},
    silver: {192, 192, 192},
    gold: {255, 215, 0},
    navy: {0, 0, 128},
    teal: {0, 128, 128},
    olive: {128, 128, 0},
    maroon: {128, 0, 0},
    lime: {50, 205, 50},
    sky: {135, 206, 235},
    transparent: {0, 0, 0, 0}
  }

  @doc "Every named colour."
  @spec names() :: [atom()]
  def names, do: Map.keys(@names)

  @doc "The `{r, g, b, a}` a specification means. Raises `ArgumentError` for one it cannot read."
  @spec color(spec()) :: {0..255, 0..255, 0..255, 0..255}
  def color({r, g, b}), do: {r, g, b, 255}
  def color({_r, _g, _b, _a} = rgba), do: rgba

  def color(name) when is_atom(name) do
    case Map.fetch(@names, name) do
      {:ok, {r, g, b}} -> {r, g, b, 255}
      {:ok, rgba} -> rgba
      :error -> raise ArgumentError, "unknown colour name #{inspect(name)}"
    end
  end

  def color("#" <> hex) do
    case hex |> String.downcase() |> String.graphemes() do
      [r, g, b] ->
        {pair(r <> r), pair(g <> g), pair(b <> b), 255}

      [r1, r2, g1, g2, b1, b2] ->
        {pair(r1 <> r2), pair(g1 <> g2), pair(b1 <> b2), 255}

      [r1, r2, g1, g2, b1, b2, a1, a2] ->
        {pair(r1 <> r2), pair(g1 <> g2), pair(b1 <> b2), pair(a1 <> a2)}

      _ ->
        raise ArgumentError, "unreadable colour #{inspect("#" <> hex)}"
    end
  end

  def color(other), do: raise(ArgumentError, "unreadable colour #{inspect(other)}")

  defp pair(hex), do: String.to_integer(hex, 16)
end
