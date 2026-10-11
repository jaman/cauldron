defmodule Cauldron2D.GameMaker.Colour do
  @moduledoc """
  GameMaker's colour functions, as `{r, g, b}`.

      Colour.hsv(25, 220, 200)
      Colour.merge({255, 0, 0}, {0, 0, 255}, 0.5)

  `hsv/3` is `make_color_hsv`: hue, saturation and value each `0..255`, the hue wrapping
  around the colour wheel. `merge/3` is `merge_color`: `amount` `0.0` gives the first
  colour, `1.0` the second.
  """

  @type t :: {byte(), byte(), byte()}

  @doc "The colour of hue `hue`, saturation `saturation` and value `value`, each `0..255`."
  @spec hsv(number(), number(), number()) :: t()
  def hsv(hue, saturation, value) do
    h = :math.fmod(:math.fmod(hue, 255.0) + 255.0, 255.0) / 255.0 * 6.0
    s = clamp(saturation / 255.0)
    v = clamp(value / 255.0)
    sector = trunc(h) |> rem(6)
    f = h - trunc(h)
    p = v * (1.0 - s)
    q = v * (1.0 - s * f)
    t = v * (1.0 - s * (1.0 - f))

    {r, g, b} =
      case sector do
        0 -> {v, t, p}
        1 -> {q, v, p}
        2 -> {p, v, t}
        3 -> {p, q, v}
        4 -> {t, p, v}
        _ -> {v, p, q}
      end

    {byte(r), byte(g), byte(b)}
  end

  @doc "The colour `amount` of the way from `from` to `to`."
  @spec merge(t(), t(), number()) :: t()
  def merge({r1, g1, b1}, {r2, g2, b2}, amount),
    do: {mix(r1, r2, amount), mix(g1, g2, amount), mix(b1, b2, amount)}

  defp mix(a, b, amount), do: round(a + (b - a) * amount) |> max(0) |> min(255)
  defp clamp(x), do: x |> max(0.0) |> min(1.0)
  defp byte(x), do: round(x * 255)
end
