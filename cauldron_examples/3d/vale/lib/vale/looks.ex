defmodule Vale.Looks do
  @moduledoc """
  What the vale is drawn with: the ground's four layers, the lake, the trees, bushes,
  boulders, grass and flowers, the painted range for the backdrop panels, and the light
  of each hour.

      looks = Vale.Looks.upload(target)
      Cauldron3D.Scene.OpenWorld.Shown.new(Vale.Looks.shown(looks))

  `upload/1` makes every mesh, texture and material in code and uploads them, answering
  their handles. `shown/1` gives the options that draw the land with them. `sky/1` gives
  the environment and the sun for an hour of the day (0 to 24).
  """

  alias Cauldron.Noise
  alias Cauldron3D.Scene.{Environment, Light, Liquid, Material, Mesh, Target, Texture, Transform}

  @type t :: %{
          ground: Cauldron3D.Scene.Handle.t(),
          water: Cauldron3D.Scene.Handle.t(),
          range: Cauldron3D.Scene.Handle.t(),
          kinds: map(),
          cover: [map()]
        }

  @doc "Uploads everything the vale is drawn with to `target`."
  @spec upload(Target.t()) :: t()
  def upload(target) do
    paint = fn colour -> Target.material(target, %Material{base_color: colour, roughness: 0.95}) end
    bark = paint.({0.36, 0.25, 0.16, 1.0})
    needles = paint.({0.13, 0.36, 0.24, 1.0})
    crown = paint.({0.27, 0.55, 0.2, 1.0})
    shrub = paint.({0.2, 0.47, 0.22, 1.0})
    stone = paint.({0.55, 0.54, 0.52, 1.0})
    soft = fn colour -> Target.material(target, %Material{base_color: colour, double_sided: true, outline: false}) end

    %{
      ground: ground(target),
      water: Target.material(target, %Material{liquid: %Liquid{clarity: 3.0, wave_size: 7.0, foam_width: 0.3}, double_sided: true}),
      range: range(target),
      kinds: %{
        pine: %{mesh: Target.mesh(target, pine()), materials: [bark, needles], sway: {0.25, 0.03, 7.0, 0.0}},
        oak: %{mesh: Target.mesh(target, oak()), materials: [bark, crown], sway: {0.2, 0.05, 5.5, 0.0}},
        bush: %{mesh: Target.mesh(target, bush()), materials: [shrub], sway: {0.06, 0.03, 1.0, 0.15}},
        boulder: %{mesh: Target.mesh(target, boulder()), materials: [stone]}
      },
      cover: [
        %{
          kind: 0,
          per: 9.0,
          size: {0.6, 1.3},
          mesh: Target.mesh(target, tuft()),
          materials: [soft.({0.4, 0.7, 0.28, 1.0})],
          sway: {0.09, 0.012, 0.24, 0.2},
          fade: {30.0, 48.0},
          shadows: false
        },
        %{
          kind: 3,
          per: 1.6,
          size: {0.8, 1.3},
          mesh: Target.mesh(target, flower()),
          materials: [soft.({0.3, 0.6, 0.25, 1.0}), soft.({0.98, 0.86, 0.3, 1.0})],
          sway: {0.1, 0.02, 0.35, 0.3},
          fade: {32.0, 52.0},
          shadows: false
        }
      ]
    }
  end

  @doc "The options that draw the land with `looks` (`Cauldron3D.Scene.OpenWorld.Shown.new/1`)."
  @spec shown(t()) :: keyword()
  def shown(looks) do
    [
      ground: looks.ground,
      water: looks.water,
      kinds: looks.kinds,
      cover: looks.cover,
      load: 420.0,
      keep: 470.0,
      steps: [1, 2, 4],
      distances: [100.0, 210.0],
      skirt: 5.0,
      things_within: 2,
      cover_within: 0
    ]
  end

  @doc "The environment and the sun at `hour`."
  @spec sky(number()) :: {Environment.t(), Light.t()}
  def sky(hour) do
    turn = (hour - 12.0) / 12.0 * :math.pi()
    high = max(:math.cos(turn), 0.08)
    low = 1.0 - high
    warm = {1.0, 0.97 - low * 0.35, 0.9 - low * 0.6}

    environment = %Environment{
      shading: :toon,
      toon_bands: 2,
      toon_softness: 0.07,
      shade_color: {0.5, 0.55, 0.74},
      rim: 0.22,
      outline_color: {0.14, 0.11, 0.16},
      outline_width: 1.4,
      outline_reach: 85.0,
      wind: {1.0, 0.35, 1.0, 1.3},
      sky_top: {0.2 + low * 0.15, 0.45 - low * 0.15, 0.86 - low * 0.3},
      sky_horizon: {0.76 + low * 0.2, 0.86 - low * 0.2, 0.96 - low * 0.45},
      sky_ground: {0.4, 0.46, 0.4},
      ambient: {0.56, 0.63, 0.78},
      ambient_intensity: 0.3 + high * 0.3,
      fog_color: {0.74 + low * 0.18, 0.83 - low * 0.15, 0.95 - low * 0.35},
      fog_density: 0.0016,
      shadow_distance: 95.0,
      bloom_strength: 0.03,
      exposure: 1.0,
      tone_map: :neutral
    }

    sun = %Light{
      kind: :directional,
      direction: {-:math.sin(turn) * 0.85, -high, -0.35},
      color: warm,
      intensity: 1.2 + high * 2.4,
      shadows: true
    }

    {environment, sun}
  end

  defp ground(target) do
    layers =
      for {light, dark, grain} <- [
            {{98, 170, 72}, {78, 148, 60}, 9.0},
            {{140, 136, 130}, {104, 100, 98}, 5.0},
            {{222, 204, 158}, {204, 186, 142}, 12.0},
            {{118, 176, 78}, {92, 158, 70}, 7.0}
          ] do
        Target.texture(target, patch(light, dark, grain))
      end

    Target.material(target, %Material{layers: layers, layer_scale: 0.2, roughness: 0.95})
  end

  defp patch({r1, g1, b1}, {r2, g2, b2}, grain) do
    side = 128

    pixels =
      for row <- 0..(side - 1), column <- 0..(side - 1), into: <<>> do
        mix = seamless(column / side, row / side, grain) * 0.5 + 0.5
        <<blend(r2, r1, mix), blend(g2, g1, mix), blend(b2, b1, mix), 255>>
      end

    %Texture{width: side, height: side, pixels: pixels, filter: :linear, mipmaps: true}
  end

  defp seamless(across, down, grain) do
    at = fn x, y -> Noise.fractal(77, x * grain, y * grain, octaves: 3) end
    near = at.(across, down) * (1 - across) + at.(across - 1, down) * across
    far = at.(across, down - 1) * (1 - across) + at.(across - 1, down - 1) * across
    near * (1 - down) + far * down
  end

  defp range(target) do
    {width, height} = {1024, 256}

    ridges =
      for column <- 0..(width - 1) do
        around = column / width * 2.0 * :math.pi()
        {x, y} = {:math.cos(around) * 3.0, :math.sin(around) * 3.0}

        {0.36 + Noise.fractal(5, x, y, octaves: 4) * 0.2, 0.56 + Noise.fractal(6, x * 1.7, y * 1.7, octaves: 4) * 0.13,
         0.76 + Noise.fractal(7, x * 2.6, y * 2.6, octaves: 3) * 0.08}
      end

    pixels =
      for row <- 0..(height - 1), {far, mid, near} <- ridges, into: <<>> do
        down = row / height

        cond do
          down > near -> <<96, 134, 108, 255>>
          down > mid -> <<128, 158, 168, 255>>
          down > far -> <<168, 188, 214, 255>>
          true -> <<0, 0, 0, 0>>
        end
      end

    texture = %Texture{width: width, height: height, pixels: pixels, filter: :linear, wrap: :repeat}

    Target.material(target, %Material{
      base_texture: Target.texture(target, texture),
      unlit: true,
      alpha_cutoff: 0.5,
      double_sided: true,
      outline: false
    })
  end

  defp pine do
    Mesh.joined([
      Mesh.joined([column(0.16, 0.1, 2.2, 6)]),
      Mesh.joined([
        lifted(cone(1.5, 2.4, 7), 1.4),
        lifted(cone(1.15, 2.1, 7), 2.9),
        lifted(cone(0.75, 1.8, 7), 4.3)
      ])
    ])
  end

  defp oak do
    Mesh.joined([
      Mesh.joined([column(0.26, 0.17, 2.6, 6)]),
      Mesh.joined([
        blob({0.0, 3.6, 0.0}, {1.9, 1.4, 1.9}),
        blob({1.1, 3.0, 0.3}, {1.2, 0.95, 1.2}),
        blob({-0.9, 3.1, -0.5}, {1.3, 1.0, 1.3}),
        blob({0.1, 4.5, -0.2}, {1.1, 0.9, 1.1})
      ])
    ])
  end

  defp bush do
    Mesh.joined([
      Mesh.joined([blob({0.0, 0.45, 0.0}, {0.8, 0.6, 0.8}), blob({0.5, 0.35, 0.2}, {0.55, 0.42, 0.55}), blob({-0.4, 0.3, -0.3}, {0.5, 0.4, 0.5})])
    ])
  end

  defp boulder do
    Mesh.joined([
      Mesh.joined([blob({0.0, 0.35, 0.0}, {1.0, 0.7, 0.85}, 5), blob({0.6, 0.2, 0.3}, {0.55, 0.42, 0.5}, 5)])
    ])
  end

  defp tuft do
    blades =
      for {turn, lean, height} <- [{0.0, 0.05, 0.24}, {1.1, -0.04, 0.19}, {2.2, 0.06, 0.27}, {3.6, -0.05, 0.21}, {5.0, 0.03, 0.17}] do
        {sin, cos} = {:math.sin(turn), :math.cos(turn)}
        blade({sin * 0.04, cos * 0.04}, {cos * 0.016, -sin * 0.016}, {sin * lean, cos * lean}, height)
      end

    Mesh.joined([Mesh.joined(blades)])
  end

  defp flower do
    stem = blade({0.0, 0.0}, {0.008, 0.0}, {0.015, 0.0}, 0.26)

    head =
      Mesh.placed(Mesh.sphere(1.0, 4), %Transform{position: {0.015, 0.27, 0.0}, scale: {0.04, 0.022, 0.04}})

    Mesh.joined([stem, head])
  end

  defp blade({x, z}, {half_x, half_z}, {lean_x, lean_z}, height) do
    up = {0.0, 1.0, 0.0}

    Mesh.new(
      [
        %{position: {x - half_x, 0.0, z - half_z}, normal: up, uv: {0.0, 1.0}},
        %{position: {x + half_x, 0.0, z + half_z}, normal: up, uv: {1.0, 1.0}},
        %{position: {x + lean_x, height, z + lean_z}, normal: up, uv: {0.5, 0.0}}
      ],
      [0, 1, 2]
    )
  end

  defp blob(position, scale, rings \\ 7),
    do: Mesh.placed(Mesh.sphere(1.0, rings), %Transform{position: position, scale: scale})

  defp lifted(mesh, height), do: Mesh.placed(mesh, %Transform{position: {0.0, height, 0.0}})

  defp cone(radius, height, sides) do
    slope = radius / height

    rim =
      for side <- 0..sides do
        turn = side / sides * 2.0 * :math.pi()
        {x, z} = {:math.cos(turn), :math.sin(turn)}
        %{position: {x * radius, 0.0, z * radius}, normal: unit({x, slope, z}), uv: {side / sides, 1.0}}
      end

    tips =
      for side <- 0..(sides - 1) do
        turn = (side + 0.5) / sides * 2.0 * :math.pi()
        %{position: {0.0, height, 0.0}, normal: unit({:math.cos(turn), slope, :math.sin(turn)}), uv: {(side + 0.5) / sides, 0.0}}
      end

    under =
      for side <- 0..sides do
        turn = side / sides * 2.0 * :math.pi()
        {x, z} = {:math.cos(turn), :math.sin(turn)}
        %{position: {x * radius, 0.0, z * radius}, normal: {0.0, -1.0, 0.0}, uv: {x * 0.5 + 0.5, z * 0.5 + 0.5}}
      end

    middle = %{position: {0.0, 0.0, 0.0}, normal: {0.0, -1.0, 0.0}, uv: {0.5, 0.5}}
    first_under = 2 * sides + 1
    faces = for side <- 0..(sides - 1), do: [side + 1, side, sides + 1 + side]
    floor = for side <- 0..(sides - 1), do: [first_under + side, first_under + side + 1, first_under + sides + 1]
    Mesh.new(rim ++ tips ++ under ++ [middle], List.flatten(faces ++ floor))
  end

  defp column(base, top, height, sides) do
    ring = fn radius, y, v ->
      for side <- 0..sides do
        turn = side / sides * 2.0 * :math.pi()
        {x, z} = {:math.cos(turn), :math.sin(turn)}
        %{position: {x * radius, y, z * radius}, normal: {x, 0.0, z}, uv: {side / sides, v}}
      end
    end

    faces =
      for side <- 0..(sides - 1) do
        upper = sides + 1 + side
        [side + 1, side, upper, side + 1, upper, upper + 1]
      end

    Mesh.new(ring.(base, 0.0, 1.0) ++ ring.(top, height, 0.0), List.flatten(faces))
  end

  defp unit({x, y, z}) do
    length = :math.sqrt(x * x + y * y + z * z)
    {x / length, y / length, z / length}
  end

  defp blend(from, to, mix), do: from |> Kernel.+((to - from) * mix) |> round() |> max(0) |> min(255)
end
