defmodule Greenware.Palette do
  @moduledoc "The colours of the Bake. Everything is clay, ash, bone or lamplight."

  @clay %{
    bone: {232, 220, 196, 255},
    paper: {242, 232, 210, 255},
    parchment: {218, 201, 169, 255},
    ink: {39, 27, 22, 255},
    soot: {25, 18, 16, 255},
    umber: {61, 42, 32, 255},
    leather: {92, 61, 42, 255},
    terracotta: {176, 92, 60, 255},
    ochre: {205, 148, 78, 255},
    amber: {232, 176, 92, 255},
    ember: {219, 103, 48, 255},
    moss: {91, 112, 64, 255},
    leaf: {122, 145, 80, 255},
    sage: {159, 169, 124, 255},
    teal: {58, 92, 85, 255},
    slate: {63, 73, 74, 255},
    night: {23, 30, 33, 255},
    cellar: {34, 35, 39, 255},
    plum: {74, 48, 66, 255},
    rose: {177, 104, 102, 255},
    brass: {186, 143, 72, 255},
    gold: {235, 193, 108, 255},
    white: {255, 252, 240, 255},
    clear: {0, 0, 0, 0}
  }

  @doc "A named colour."
  def c(name), do: Map.fetch!(@clay, name)

  @doc "A named colour with another alpha."
  def a(name, alpha), do: put_elem(c(name), 3, clamp(round(alpha * 255)))

  @doc "The colour `amount` (0..1) between `a` and `b`."
  def mix({ar, ag, ab, aa}, {br, bg, bb, ba}, amount) do
    t = amount |> max(0.0) |> min(1.0)

    {round(ar + (br - ar) * t), round(ag + (bg - ag) * t), round(ab + (bb - ab) * t),
     round(aa + (ba - aa) * t)}
  end

  @doc "The colour darkened or lightened by `amount` (-1..1), alpha kept."
  def shade({r, g, b, a}, amount) when amount >= 0 do
    {lerp(r, 255, amount), lerp(g, 255, amount), lerp(b, 255, amount), a}
  end

  def shade({r, g, b, a}, amount) do
    {lerp(r, 0, -amount), lerp(g, 0, -amount), lerp(b, 0, -amount), a}
  end

  defp lerp(value, target, amount), do: round(value + (target - value) * amount)

  defp clamp(value), do: value |> max(0) |> min(255)
end
