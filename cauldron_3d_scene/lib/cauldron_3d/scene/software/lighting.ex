if Code.ensure_loaded?(Cauldron3D.Render) do
  defmodule Cauldron3D.Scene.Software.Lighting do
    @moduledoc """
    The light on a vertex and the colour it is tinted with in `Cauldron3D.Scene.Software`.

    `light/4` is the linear light reaching a vertex: the environment's ambient light and
    each light the scene holds. A light adds `colour * intensity * max(normal · to_light,
    0)`, times `max(1 - distance² / range², 0)` for point and spot lights, and for spot
    lights the share of the way from the outer cone to the inner. Shadows, reflections and
    baked light are not drawn.

    `tint/4` is a material lit by that light, plus its emissive light, turned into screen
    colour as `Cauldron3D.Scene.Software.Display` turns it and multiplied by the vertex
    colour: `{r, g, b, a}`, each 0 to 1. An `unlit` material shows its base colour.

        light = Lighting.light(position, normal, lights, environment)
        Lighting.tint(material, light, nil, environment)
    """

    alias Cauldron3D.Scene.{Environment, Light, Material}
    alias Cauldron3D.Scene.Software.Display

    @type rgb :: {float(), float(), float()}
    @type rgba :: {float(), float(), float(), float()}

    @doc "The linear light reaching a vertex at `position` with `normal`."
    @spec light(rgb(), rgb(), [Light.t()], Environment.t()) :: rgb()
    def light(position, normal, lights, %Environment{} = environment) do
      {ar, ag, ab} = environment.ambient
      intensity = environment.ambient_intensity

      Enum.reduce(
        lights,
        {ar * intensity, ag * intensity, ab * intensity},
        &add(&2, received(&1, position, normal))
      )
    end

    @doc "The tint of a vertex of `material` under `light`, with vertex colour `color` (or `nil`)."
    @spec tint(Material.t(), rgb(), rgba() | nil, Environment.t()) :: rgba()
    def tint(%Material{unlit: true} = material, _light, color, environment),
      do:
        display(material.base_color, {1.0, 1.0, 1.0}, color, %{
          environment
          | exposure: 1.0,
            tone_map: :clamp
        })

    def tint(%Material{} = material, light, color, environment),
      do: display(material.base_color, add(light, emitted(material)), color, environment)

    defp received(%Light{kind: :directional} = light, _position, normal) do
      {dx, dy, dz} = light.direction
      scaled(light, max(dot(normal, {-dx, -dy, -dz}), 0.0))
    end

    defp received(%Light{} = light, position, normal) do
      to_light = minus(light.position, position)
      distance_squared = dot(to_light, to_light)
      direction = unit(to_light, distance_squared)
      falloff = max(1.0 - distance_squared / (light.range * light.range), 0.0)
      scaled(light, max(dot(normal, direction), 0.0) * falloff * cone(light, direction))
    end

    defp cone(%Light{kind: :spot} = light, direction) do
      {dx, dy, dz} = light.direction
      angle = :math.acos(max(min(dot({-dx, -dy, -dz}, direction), 1.0), -1.0))
      span = max(light.outer_cone - light.inner_cone, 1.0e-6)
      max(min((light.outer_cone - angle) / span, 1.0), 0.0)
    end

    defp cone(_light, _direction), do: 1.0

    defp emitted(%Material{emissive: {r, g, b}, emissive_strength: strength}),
      do: {r * strength, g * strength, b * strength}

    defp scaled(%Light{color: {r, g, b}, intensity: intensity}, amount),
      do: {r * intensity * amount, g * intensity * amount, b * intensity * amount}

    defp display({br, bg, bb, ba}, {lr, lg, lb}, color, environment) do
      {cr, cg, cb, ca} = color || {1.0, 1.0, 1.0, 1.0}
      {r, g, b} = Display.shown({br * lr, bg * lg, bb * lb}, environment)
      {r * cr, g * cg, b * cb, ba * ca}
    end

    defp add({ar, ag, ab}, {br, bg, bb}), do: {ar + br, ag + bg, ab + bb}
    defp minus({ax, ay, az}, {bx, by, bz}), do: {ax - bx, ay - by, az - bz}
    defp dot({ax, ay, az}, {bx, by, bz}), do: ax * bx + ay * by + az * bz

    defp unit(_vector, squared) when squared <= 0.0, do: {0.0, 1.0, 0.0}

    defp unit({x, y, z}, squared) do
      length = :math.sqrt(squared)
      {x / length, y / length, z / length}
    end
  end
end
