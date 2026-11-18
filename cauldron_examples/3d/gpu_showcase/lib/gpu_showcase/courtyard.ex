defmodule GpuShowcase.Courtyard do
  @moduledoc """
  A lit courtyard built entirely in code: a checkered floor, a ring of turning crates,
  metal and plastic spheres, a sun with shadows and coloured lamps. Uploads go through
  `Cauldron3D.Scene.Target`, so any renderer takes it.

      assets = GpuShowcase.Courtyard.upload(target)
      Cauldron3D.Scene.Target.submit(target, GpuShowcase.Courtyard.scene(assets))
      Cauldron3D.Scene.Target.submit(target, GpuShowcase.Courtyard.ring(assets, tick) ++ [camera])

  `ring/3` places `count` crates (default 8) with ids from 10. `orbit/2` is a camera
  looking at the middle from `angle` radians around it, `distance` away (default 9).
  """

  alias Cauldron3D.Scene.{Camera, Environment, Instance, Light, Material, Mesh, Quat, Texture, Transform}
  alias Cauldron3D.Scene.Target

  def upload(target) do
    checker =
      Target.texture(target, Texture.checker(256, 8, {200, 200, 190, 255}, {70, 75, 80, 255}))

    crate =
      Target.texture(target, Texture.checker(64, 4, {190, 120, 60, 255}, {150, 90, 40, 255}))

    %{
      plane: Target.mesh(target, Mesh.plane(40, 10)),
      cube: Target.mesh(target, Mesh.cube(1.0)),
      sphere: Target.mesh(target, Mesh.sphere(0.8, 24)),
      floor: Target.material(target, %Material{base_texture: checker, roughness: 0.3}),
      crate: Target.material(target, %Material{base_texture: crate, roughness: 0.6}),
      gold:
        Target.material(target, %Material{
          base_color: {1.0, 0.78, 0.34, 1.0},
          metallic: 1.0,
          roughness: 0.05
        }),
      plastic:
        Target.material(target, %Material{base_color: {0.1, 0.35, 0.9, 1.0}, roughness: 0.35}),
      lamp: Target.material(target, %Material{base_color: {1.0, 0.6, 0.2, 1.0}, unlit: true})
    }
  end

  def scene(assets) do
    [
      %Environment{
        fog_density: 0.012,
        ambient_intensity: 0.25,
        exposure: 1.1,
        shadow_distance: 25.0
      },
      {:instance, 1, %Instance{mesh: assets.plane, materials: [assets.floor]}},
      {:instance, 2,
       %Instance{
         mesh: assets.sphere,
         materials: [assets.gold],
         transform: Transform.new(position: {-2.0, 0.8, 0.0})
       }},
      {:instance, 3,
       %Instance{
         mesh: assets.sphere,
         materials: [assets.plastic],
         transform: Transform.new(position: {2.0, 0.8, 0.0})
       }},
      {:instance, 4,
       %Instance{
         mesh: assets.sphere,
         materials: [assets.lamp],
         shadows: false,
         transform: Transform.new(position: {0.0, 3.0, -3.0}, scale: 0.15)
       }},
      {:light, 1,
       %Light{
         kind: :directional,
         direction: {-0.5, -1.0, -0.35},
         color: {1.0, 0.95, 0.85},
         intensity: 3.0,
         shadows: true
       }},
      {:light, 2,
       %Light{
         kind: :point,
         position: {0.0, 3.0, -3.0},
         color: {1.0, 0.6, 0.2},
         intensity: 30.0,
         range: 12.0
       }},
      {:light, 3,
       %Light{
         kind: :spot,
         position: {5.0, 4.0, 4.0},
         direction: {-0.6, -1.0, -0.6},
         color: {0.3, 0.6, 1.0},
         intensity: 60.0,
         range: 15.0
       }}
    ]
  end

  def ring(assets, tick, count \\ 8) do
    for index <- 0..(count - 1) do
      angle = index / count * 2 * :math.pi() + tick * 0.02

      position =
        {:math.cos(angle) * 5.0, 0.6 + :math.sin(tick * 0.08 + index) * 0.4,
         :math.sin(angle) * 5.0}

      rotation = Quat.axis_angle({0.3, 1.0, 0.2}, tick * 0.06 + index)

      {:instance, 10 + index,
       %Instance{
         mesh: assets.cube,
         materials: [assets.crate],
         transform: Transform.new(position: position, rotation: rotation)
       }}
    end
  end

  def orbit(angle, distance \\ 9.0) do
    rotation = Quat.yaw_pitch(angle, -0.3)
    {x, y, z} = Quat.rotate(rotation, {0.0, 0.0, distance})
    %Camera{position: {x, y + 0.8, z}, rotation: rotation, fov_y: 1.1}
  end
end
