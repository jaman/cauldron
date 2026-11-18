defmodule Courtyard.Scenes.Courtyard do
  @moduledoc """
  The courtyard, made in code: a checkered floor, a mirror-smooth gold sphere, a blue
  plastic one, a lamp, a sun with shadows, coloured lights and a ring of turning crates,
  as many as the view asks for. A `Courtyard.Scene`; it needs nothing downloaded.

      {:ok, placed} = Courtyard.Scenes.Courtyard.upload(target, [])
  """

  @behaviour Courtyard.Scene

  alias Cauldron3D.Scene.{Environment, Instance, Light, Material, Mesh, Quat, Texture, Transform}
  alias Cauldron3D.Scene.Target

  @first_crate 10

  @impl true
  def name, do: "courtyard"

  @impl true
  def start, do: %{position: {0.0, 0.0, 7.0}, yaw: 0.0, pitch: -0.25}

  @impl true
  def ground do
    {:ok,
     Cauldron3D.WalkGrid.build({{-20.0, -20.0}, {20.0, 20.0}}, [],
       discs: [{{-2.0, 0.0}, 0.8}, {{2.0, 0.0}, 0.8}]
     )}
  end

  @impl true
  def upload(target, _opts) do
    floor =
      Target.texture(target, Texture.checker(256, 8, {200, 200, 190, 255}, {70, 75, 80, 255}))

    crate =
      Target.texture(target, Texture.checker(64, 4, {190, 120, 60, 255}, {150, 90, 40, 255}))

    assets = %{
      plane: Target.mesh(target, Mesh.plane(40, 10)),
      cube: Target.mesh(target, Mesh.cube(1.0)),
      sphere: Target.mesh(target, Mesh.sphere(0.8, 32)),
      floor: Target.material(target, %Material{base_texture: floor, roughness: 0.3}),
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

    {:ok, %{changes: still(assets), handles: Map.values(assets) ++ [floor, crate], data: assets}}
  end

  @impl true
  def frame(%{data: assets}, view) do
    count = view.crates
    rings = div(count + 7, 8)

    for index <- 0..(count - 1)//1 do
      ring = div(index, 8)
      around = rem(index, 8) / 8 * 2 * :math.pi() + view.time * 0.4 * (1 - 2 * rem(ring, 2))
      radius = 5.0 + ring * 2.0
      height = 0.6 + ring * 1.4 / max(rings, 1) + :math.sin(view.time * 1.6 + index) * 0.4

      {:instance, @first_crate + index,
       %Instance{
         mesh: assets.cube,
         materials: [assets.crate],
         transform:
           Transform.new(
             position: {:math.cos(around) * radius, height, :math.sin(around) * radius},
             rotation: Quat.axis_angle({0.3, 1.0, 0.2}, view.time * 1.2 + index)
           )
       }}
    end
  end

  defp still(assets) do
    [
      %Environment{
        fog_density: 0.012,
        ambient_intensity: 0.25,
        exposure: 1.1,
        shadow_distance: 25.0
      },
      {:instance, 1, %Instance{mesh: assets.plane, materials: [assets.floor]}},
      {:instance, 2, at(assets.sphere, assets.gold, {-2.0, 0.8, 0.0})},
      {:instance, 3, at(assets.sphere, assets.plastic, {2.0, 0.8, 0.0})},
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

  defp at(mesh, material, position),
    do: %Instance{mesh: mesh, materials: [material], transform: Transform.new(position: position)}
end
