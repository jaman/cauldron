defmodule Courtyard.Scenes.Alley do
  @moduledoc """
  A night-time alley between an apartment block and a factory, built from Poly Haven's
  CC0 "Hidden Alley" models on a cobblestone floor. The building fronts and the end walls
  are assembled from the modular facade kits (`Courtyard.Scenes.Alley.Buildings`); a fire
  escape, street lamps, security lights, a covered car, a burning barrel stove and the
  rest stand in front of them. Three warm street lamps, two cold security lights, the
  stove's flickering fire and a dim moon light it. A `Courtyard.Scene`;
  `mix courtyard.fetch alley` downloads it.

      {:ok, placed} = Courtyard.Scenes.Alley.upload(target, [])
  """

  @behaviour Courtyard.Scene

  alias Cauldron3D.Scene.{
    Environment,
    Gltf,
    Instance,
    Light,
    Material,
    Mesh,
    Quat,
    Texture,
    Transform
  }

  alias Cauldron3D.Scene.Target

  alias Cauldron3D.WalkGrid
  alias Courtyard.{Assets, Grounds, Kit}
  alias Courtyard.Scenes.Alley.Buildings

  @first_id 1000
  @half_turn :math.pi()
  @quarter_turn :math.pi() / 2
  @fire {-7.5, 0.95, -2.4}
  @fire_escape_floor 2.87

  @impl true
  def name, do: "alley"

  @impl true
  def start, do: %{position: {-21.0, 0.0, 0.0}, yaw: -@quarter_turn, pitch: -0.15}

  @impl true
  def ground do
    with true <- Assets.ready?(:alley) || {:error, {:missing, Assets.fetch_command(:alley)}},
         do: Grounds.cached(:alley, &walk_grid/0)
  end

  defp walk_grid do
    with {:ok, documents} <- documents() do
      sources =
        Enum.flat_map(documents, fn {_id, document, places} ->
          Grounds.sources(document, Enum.map(places, &transform/1))
        end)

      {:ok, WalkGrid.build({{-27.0, -4.5}, {27.0, 4.5}}, sources)}
    end
  end

  @impl true
  def upload(target, _opts) do
    if Assets.ready?(:alley) do
      placed(target)
    else
      {:error, {:missing, Assets.fetch_command(:alley)}}
    end
  end

  @impl true
  def frame(_placed, view) do
    flicker = 0.8 + 0.12 * :math.sin(view.time * 13.0) + 0.08 * :math.sin(view.time * 31.0 + 1.3)
    [{:light, 4, fire_light(flicker)}]
  end

  defp placed(target) do
    with {:ok, models} <- models(target),
         {:ok, ground} <- cobbles(target) do
      changes =
        [environment(), ground.instance | lights()] ++ Enum.flat_map(models, & &1.instances)

      {:ok,
       %{
         changes: changes,
         handles: ground.handles ++ Enum.flat_map(models, & &1.handles),
         data: nil
       }}
    end
  end

  defp placements do
    [
      {"modular_urban_apartments_facade", {:parts, Buildings.apartments()}},
      {"modular_factory_facade", {:parts, Buildings.factory()}},
      {"modular_fire_escape",
       {:places, [{{-12.0, Buildings.apartment_floor(1) + @fire_escape_floor, -3.2}, 0.0}]}},
      {"street_lamp_01",
       {:places,
        [{{-10.0, 0.0, 3.0}, @half_turn}, {{6.0, 0.0, -3.0}, 0.0}, {{17.0, 0.0, 3.0}, @half_turn}]}},
      {"security_light",
       {:places, [{{-2.0, 4.2, 4.0}, @half_turn}, {{12.0, 4.2, 4.0}, @half_turn}]}},
      {"barrel_stove", {:places, [{put_elem(@fire, 1, 0.0), 0.3}]}},
      {"metal_trash_can",
       {:pick,
        [
          "metal_trash_can_rust",
          "metal_trash_can_rust_handle_left",
          "metal_trash_can_rust_handle_right",
          "metal_trash_can_rust_lid"
        ], [{{-1.0, 0.0, -3.4}, 0.0}]}},
      {"covered_car", {:places, [{{8.0, 0.0, 2.0}, @quarter_turn}]}},
      {"fire_hydrant",
       {:pick,
        [
          "fire_hydrant_aged",
          "fire_hydrant_cap_01_aged",
          "fire_hydrant_cap_02_aged",
          "fire_hydrant_cap_03_aged",
          "fire_hydrant_chain_aged"
        ], [{{2.3, 0.0, 3.4}, @half_turn}]}},
      {"water_manhole_cover", {:places, [{{0.5, 0.0, 0.3}, 0.0}]}},
      {"rollershutter_door",
       {:parts, [{"rollershutter_door_graffiti", {7.5, 0.0, 4.0}, @half_turn}]}},
      {"exterior_aircon_unit",
       {:parts, [{"exterior_aircon_unit_rusted", {-1.5, 2.4, -3.78}, 0.0}]}},
      {"old_tyre", {:places, [{{-8.8, 0.3, -3.3}, 0.0}]}},
      {"utility_box_01", {:places, [{{4.5, 0.0, -3.7}, 0.0}]}},
      {"concrete_road_barrier",
       {:places, [{{22.0, 0.0, -1.2}, @quarter_turn}, {{22.0, 0.0, 1.0}, @quarter_turn}]}},
      {"boombox", {:places, [{{-6.6, 0.0, -3.0}, 0.4}]}},
      {"street_rat", {:places, [{{-1.2, 0.0, -2.6}, 1.2}]}}
    ]
  end

  defp documents do
    placements()
    |> Enum.reduce_while({:ok, []}, fn {id, shape}, {:ok, read} ->
      with {:ok, kit} <- Cauldron3D.Formats.Gltf.read(Assets.model(id)),
           {:ok, document, places} <- shaped(kit, shape) do
        {:cont, {:ok, [{id, document, places} | read]}}
      else
        {:error, reason} -> {:halt, {:error, {id, reason}}}
      end
    end)
    |> then(fn
      {:ok, read} -> {:ok, Enum.reverse(read)}
      error -> error
    end)
  end

  defp models(target) do
    with {:ok, documents} <- documents() do
      documents
      |> Enum.reduce_while({:ok, [], @first_id}, &upload_document(target, &1, &2))
      |> then(fn
        {:ok, uploaded, _next_id} -> {:ok, uploaded}
        error -> error
      end)
    end
  end

  defp upload_document(target, {id, document, places}, {:ok, uploaded, next_id}) do
    case Gltf.upload(target, document,
           places: Enum.map(places, &transform/1),
           first_id: next_id
         ) do
      {:ok, result} -> {:cont, {:ok, [result | uploaded], result.next_id}}
      {:error, reason} -> {:halt, {:error, {id, reason}}}
    end
  end

  defp shaped(kit, {:places, places}), do: {:ok, kit, places}
  defp shaped(kit, {:pick, names, places}), do: {:ok, Kit.pick(kit, names), places}

  defp shaped(kit, {:parts, parts}),
    do:
      with(
        {:ok, document} <- Kit.assemble(kit, parts),
        do: {:ok, document, [{{0.0, 0.0, 0.0}, 0.0}]}
      )

  defp transform({position, yaw}),
    do: Transform.new(position: position, rotation: Quat.axis_angle({0.0, 1.0, 0.0}, yaw))

  defp cobbles(target) do
    {diffuse, normal, arm} = Assets.ground()

    with {:ok, base} <- Texture.encoded(File.read!(diffuse), format: :srgb),
         {:ok, bumps} <- Texture.encoded(File.read!(normal), format: :linear),
         {:ok, surface} <- Texture.encoded(File.read!(arm), format: :linear) do
      textures = [
        Target.texture(target, base),
        Target.texture(target, bumps),
        Target.texture(target, surface)
      ]

      [base, bumps, surface] = textures

      material =
        Target.material(target, %Material{
          base_texture: base,
          normal_texture: bumps,
          metallic: 0.0,
          metallic_roughness_texture: surface,
          occlusion_texture: surface
        })

      mesh = Target.mesh(target, Mesh.plane(60, 30))

      {:ok,
       %{
         instance: {:instance, @first_id - 1, %Instance{mesh: mesh, materials: [material]}},
         handles: [mesh, material | textures]
       }}
    end
  end

  defp environment do
    %Environment{
      sky_top: {0.01, 0.015, 0.04},
      sky_horizon: {0.05, 0.06, 0.1},
      sky_ground: {0.02, 0.02, 0.025},
      ambient: {0.25, 0.3, 0.45},
      ambient_intensity: 0.06,
      fog_color: {0.04, 0.05, 0.08},
      fog_density: 0.02,
      exposure: 1.4,
      shadow_distance: 40.0,
      bloom_strength: 0.08
    }
  end

  defp lights do
    lamps =
      for {{x, _y, z}, index} <-
            Enum.with_index([{-10.0, 0.0, 3.0}, {6.0, 0.0, -3.0}, {17.0, 0.0, 3.0}], 1) do
        {:light, index,
         %Light{
           kind: :point,
           position: {x, 3.7, z - 0.4 * sign(z)},
           color: {1.0, 0.75, 0.45},
           intensity: 45.0,
           range: 14.0
         }}
      end

    security =
      for {x, index} <- Enum.with_index([-2.0, 12.0], 5) do
        {:light, index,
         %Light{
           kind: :spot,
           position: {x, 4.0, 3.6},
           direction: {0.0, -1.0, -0.45},
           color: {0.8, 0.9, 1.0},
           intensity: 90.0,
           range: 14.0
         }}
      end

    moon =
      {:light, 7,
       %Light{
         kind: :directional,
         direction: {0.3, -1.0, 0.45},
         color: {0.55, 0.65, 0.95},
         intensity: 0.25,
         shadows: true
       }}

    [moon, {:light, 4, fire_light(1.0)} | lamps ++ security]
  end

  defp fire_light(strength),
    do: %Light{
      kind: :point,
      position: @fire,
      color: {1.0, 0.45, 0.15},
      intensity: 22.0 * strength,
      range: 7.0
    }

  defp sign(value) when value < 0, do: -1.0
  defp sign(_value), do: 1.0
end
