defmodule Cauldron.Ease do
  @moduledoc """
  Easing curves: how a change moves from its start to its end, as a function from the
  share of time passed (`0.0..1.0`) to the share of the way gone (`0.0` at the start,
  `1.0` at the end; `:back` and `:elastic` go past it on the way).

      Cauldron.Ease.apply(:out_cubic, 0.5)
      #=> 0.875

  The curves are named as most engines name them: `:linear`, and for each of `quad`,
  `cubic`, `quart`, `sine`, `expo`, `circ`, `back`, `elastic` and `bounce`, an `:in_`
  form (slow start), an `:out_` form (slow end) and an `:in_out_` form (slow both).
  `Cauldron.Tween` runs a value along one.
  """

  @kinds [:quad, :cubic, :quart, :sine, :expo, :circ, :back, :elastic, :bounce]

  @type curve :: atom()

  @doc "Every curve's name."
  @spec curves() :: [curve()]
  def curves,
    do: [:linear | for(kind <- @kinds, form <- ["in_", "out_", "in_out_"], do: :"#{form}#{kind}")]

  @doc "How far along `curve` is with share `t` of the time passed; `t` is held to `0.0..1.0`."
  @spec apply(curve(), number()) :: float()
  def apply(curve, t) do
    t = t |> max(0.0) |> min(1.0)

    case Atom.to_string(curve) do
      "linear" -> t / 1
      "in_out_" <> kind -> in_out(kind(kind), t)
      "in_" <> kind -> ease_in(kind(kind), t)
      "out_" <> kind -> 1.0 - ease_in(kind(kind), 1.0 - t)
    end
  end

  defp kind(name) do
    kind = String.to_existing_atom(name)
    if kind in @kinds, do: kind, else: raise(ArgumentError, "no easing curve #{name}")
  end

  defp in_out(kind, t) when t < 0.5, do: ease_in(kind, t * 2) / 2
  defp in_out(kind, t), do: 1.0 - ease_in(kind, (1.0 - t) * 2) / 2

  defp ease_in(:quad, t), do: t * t
  defp ease_in(:cubic, t), do: t * t * t
  defp ease_in(:quart, t), do: t * t * t * t
  defp ease_in(:sine, t), do: 1.0 - :math.cos(t * :math.pi() / 2)
  defp ease_in(:expo, t) when t == 0, do: 0.0
  defp ease_in(:expo, t), do: :math.pow(2, 10 * t - 10)
  defp ease_in(:circ, t), do: 1.0 - :math.sqrt(1.0 - t * t)
  defp ease_in(:back, t), do: 2.70158 * t * t * t - 1.70158 * t * t
  defp ease_in(:elastic, t) when t == 0 or t == 1, do: t / 1

  defp ease_in(:elastic, t),
    do: -:math.pow(2, 10 * t - 10) * :math.sin((t * 10 - 10.75) * (2 * :math.pi() / 3))

  defp ease_in(:bounce, t), do: 1.0 - bounce_out(1.0 - t)

  defp bounce_out(t) when t < 1 / 2.75, do: 7.5625 * t * t

  defp bounce_out(t) when t < 2 / 2.75 do
    t = t - 1.5 / 2.75
    7.5625 * t * t + 0.75
  end

  defp bounce_out(t) when t < 2.5 / 2.75 do
    t = t - 2.25 / 2.75
    7.5625 * t * t + 0.9375
  end

  defp bounce_out(t) do
    t = t - 2.625 / 2.75
    7.5625 * t * t + 0.984375
  end
end
