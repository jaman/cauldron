if Code.ensure_loaded?(Cauldron3D.Render) do
  defmodule Cauldron3D.Scene.Software.Display do
    @moduledoc """
    Light turned into screen colour as `cauldron_gpu` turns it, for
    `Cauldron3D.Scene.Software`: scaled by the environment's `exposure`, put through its
    `tone_map` (`:aces`, `:neutral` or `:clamp`), encoded as sRGB, then
    `clamp(v ** gamma * contrast + brightness, 0, 1)`.
    """

    alias Cauldron3D.Scene.Environment

    @doc "The screen colour, each channel 0 to 1, of linear light `{r, g, b}` in `environment`."
    @spec shown({number(), number(), number()}, Environment.t()) :: {float(), float(), float()}
    def shown({r, g, b}, %Environment{} = environment) do
      exposed = {r * environment.exposure, g * environment.exposure, b * environment.exposure}
      {mr, mg, mb} = mapped(exposed, environment.tone_map)
      {curve(mr, environment), curve(mg, environment), curve(mb, environment)}
    end

    defp mapped({r, g, b}, :neutral) do
      scale = 1.5 / (1 + max(r, max(g, b)))
      {r * scale, g * scale, b * scale}
    end

    defp mapped({r, g, b}, :clamp), do: {r, g, b}
    defp mapped({r, g, b}, _aces), do: {aces(r), aces(g), aces(b)}

    defp aces(x), do: x * (2.51 * x + 0.03) / (x * (2.43 * x + 0.59) + 0.14)

    defp curve(linear, environment) do
      encoded = encode(min(max(linear, 0.0), 1.0))

      min(
        max(
          :math.pow(encoded, environment.gamma) * environment.contrast + environment.brightness,
          0.0
        ),
        1.0
      )
    end

    defp encode(c) when c <= 0.0031308, do: c * 12.92
    defp encode(c), do: 1.055 * :math.pow(c, 1 / 2.4) - 0.055
  end
end
