defmodule BrowserShowcase do
  @moduledoc """
  The cauldron_gpu showcase courtyard in a browser: a scene served at
  http://localhost:4400/ with turning cubes, metal and plastic spheres, a sun with
  shadows and coloured lamps. Arrow keys or W A S D in the browser move the camera.

      mix run examples/showcase.exs [seconds]

  Runs until stopped, or for `seconds` when given.
  """

  alias Cauldron3D.Net.Scene
  alias CauldronGPU.{Camera, Environment, Instance, Light, Material, Mesh, Quat, Texture, Transform}

  defmodule Socket do
    @moduledoc false
    use Cauldron3D.Net.Socket, channel: BrowserShowcase.Channel
  end

  defmodule Channel do
    @moduledoc false
    use Cauldron3D.Net.Channel
  end

  defmodule Endpoint do
    @moduledoc false
    use Phoenix.Endpoint, otp_app: :cauldron_3d_net

    socket("/socket", BrowserShowcase.Socket, websocket: true, longpoll: false)
    plug(Cauldron3D.Net.Page, scene: "courtyard", title: "cauldron showcase")
  end

  @tick_ms 50

  def run(args) do
    Application.put_env(:cauldron_3d_net, Endpoint,
      adapter: Bandit.PhoenixAdapter,
      http: [port: 4400],
      server: true,
      secret_key_base: String.duplicate("cauldron", 8),
      pubsub_server: Cauldron3D.Net.PubSub
    )

    {:ok, _} = Endpoint.start_link()
    {:ok, scene} = Scene.open(id: "courtyard", events: self())
    assets = assets(scene)
    Scene.submit(scene, static_scene(assets))
    IO.puts("watch at http://localhost:4400/")
    deadline = with [seconds] <- args, do: System.monotonic_time(:millisecond) + String.to_integer(seconds) * 1000
    loop(%{scene: scene, assets: assets, tick: 0, position: {0.0, 2.2, 9.0}, yaw: 0.0, keys: MapSet.new()}, deadline)
  end

  defp assets(scene) do
    checker = Scene.texture(scene, Texture.checker(256, 8, {200, 200, 190, 255}, {70, 75, 80, 255}))
    crate = Scene.texture(scene, Texture.checker(64, 4, {190, 120, 60, 255}, {150, 90, 40, 255}))

    %{
      plane: Scene.mesh(scene, Mesh.plane(40, 10)),
      cube: Scene.mesh(scene, Mesh.cube(1.0)),
      sphere: Scene.mesh(scene, Mesh.sphere(0.8, 24)),
      floor: Scene.material(scene, %Material{base_texture: checker, roughness: 0.3}),
      crate: Scene.material(scene, %Material{base_texture: crate, roughness: 0.6}),
      gold: Scene.material(scene, %Material{base_color: {1.0, 0.78, 0.34, 1.0}, metallic: 1.0, roughness: 0.25}),
      plastic: Scene.material(scene, %Material{base_color: {0.1, 0.35, 0.9, 1.0}, roughness: 0.35}),
      lamp: Scene.material(scene, %Material{base_color: {1.0, 0.6, 0.2, 1.0}, unlit: true})
    }
  end

  defp static_scene(assets) do
    [
      %Environment{fog_density: 0.012, ambient_intensity: 0.25, exposure: 1.1, shadow_distance: 25.0},
      {:instance, 1, %Instance{mesh: assets.plane, materials: [assets.floor]}},
      {:instance, 2, %Instance{mesh: assets.sphere, materials: [assets.gold], transform: Transform.new(position: {-2.0, 0.8, 0.0})}},
      {:instance, 3, %Instance{mesh: assets.sphere, materials: [assets.plastic], transform: Transform.new(position: {2.0, 0.8, 0.0})}},
      {:instance, 4,
       %Instance{mesh: assets.sphere, materials: [assets.lamp], shadows: false, transform: Transform.new(position: {0.0, 3.0, -3.0}, scale: 0.15)}},
      {:light, 1, %Light{kind: :directional, direction: {-0.5, -1.0, -0.35}, color: {1.0, 0.95, 0.85}, intensity: 3.0, shadows: true}},
      {:light, 2, %Light{kind: :point, position: {0.0, 3.0, -3.0}, color: {1.0, 0.6, 0.2}, intensity: 30.0, range: 12.0}},
      {:light, 3,
       %Light{kind: :spot, position: {5.0, 4.0, 4.0}, direction: {-0.6, -1.0, -0.6}, color: {0.3, 0.6, 1.0}, intensity: 60.0, range: 15.0}}
    ]
  end

  defp loop(state, deadline) do
    if deadline && System.monotonic_time(:millisecond) >= deadline do
      :done
    else
      state = state |> drain() |> walk()
      Scene.submit(state.scene, ring(state) ++ [%Camera{position: state.position, rotation: Quat.yaw_pitch(state.yaw, -0.15), fov_y: 1.1}])
      Process.sleep(@tick_ms)
      loop(%{state | tick: state.tick + 1}, deadline)
    end
  end

  defp ring(%{assets: assets, tick: tick}) do
    for index <- 0..7 do
      angle = index / 8 * 2 * :math.pi() + tick * 0.02
      position = {:math.cos(angle) * 5.0, 0.6 + :math.sin(tick * 0.08 + index) * 0.4, :math.sin(angle) * 5.0}
      rotation = Quat.axis_angle({0.3, 1.0, 0.2}, tick * 0.06 + index)
      {:instance, 10 + index, %Instance{mesh: assets.cube, materials: [assets.crate], transform: Transform.new(position: position, rotation: rotation)}}
    end
  end

  defp drain(state) do
    receive do
      {:cauldron_3d_net, "courtyard", _session, {:key, :down, key, _}} -> drain(%{state | keys: MapSet.put(state.keys, key)})
      {:cauldron_3d_net, "courtyard", _session, {:key, :up, key, _}} -> drain(%{state | keys: MapSet.delete(state.keys, key)})
      {:cauldron_3d_net, "courtyard", _session, _event} -> drain(state)
    after
      0 -> state
    end
  end

  defp walk(state) do
    held = &MapSet.member?(state.keys, &1)
    turn = if(held.(:left) or held.(:a), do: 0.05, else: 0.0) - if(held.(:right) or held.(:d), do: 0.05, else: 0.0)
    step = if(held.(:up) or held.(:w), do: 0.25, else: 0.0) - if(held.(:down) or held.(:s), do: 0.25, else: 0.0)
    yaw = state.yaw + turn
    {x, y, z} = state.position
    %{state | yaw: yaw, position: {x - :math.sin(yaw) * step, y, z - :math.cos(yaw) * step}}
  end
end

BrowserShowcase.run(System.argv())
