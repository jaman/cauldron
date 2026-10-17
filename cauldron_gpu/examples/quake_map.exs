defmodule QuakeMap.Things do
  @moduledoc """
  A Quake map's monsters, pickups and flames, drawn as alias models (`progs/*.mdl`) or
  pickup brush models (`maps/b_*.bsp`), each lit by the world's light where it stands.
  Monsters loop an idle or walk animation, flames burn, pickups spin.
  """

  import Bitwise, only: [band: 2]

  alias Cauldron3D.Formats.{Bsp, Entities, Files, Mdl}
  alias CauldronGPU.{AliasModel, Instance, Placement, Texture}

  @scale 1 / 32
  @not_on_normal_skill 512

  @models %{
    "monster_army" => {"progs/soldier.mdl", ["stand", "prowl_"]},
    "monster_dog" => {"progs/dog.mdl", ["stand", "walk"]},
    "monster_ogre" => {"progs/ogre.mdl", ["stand", "walk"]},
    "monster_knight" => {"progs/knight.mdl", ["stand", "walk"]},
    "monster_zombie" => {"progs/zombie.mdl", ["stand", "walk"]},
    "monster_demon1" => {"progs/demon.mdl", ["stand", "walk"]},
    "monster_shambler" => {"progs/shambler.mdl", ["stand", "walk"]},
    "monster_wizard" => {"progs/wizard.mdl", ["hover", "fly"]},
    "weapon_supershotgun" => {"progs/g_shot.mdl", ["shot"]},
    "weapon_nailgun" => {"progs/g_nail.mdl", ["shot"]},
    "weapon_supernailgun" => {"progs/g_nail2.mdl", ["shot"]},
    "weapon_grenadelauncher" => {"progs/g_rock.mdl", ["shot"]},
    "weapon_rocketlauncher" => {"progs/g_rock2.mdl", ["shot"]},
    "weapon_lightning" => {"progs/g_light.mdl", ["shot"]},
    "item_armor1" => {"progs/armor.mdl", ["armor"]},
    "item_armor2" => {"progs/armor.mdl", ["armor"]},
    "item_artifact_super_damage" => {"progs/quaddama.mdl", ["frame"]},
    "item_artifact_invulnerability" => {"progs/invulner.mdl", ["frame"]},
    "item_artifact_envirosuit" => {"progs/suit.mdl", ["frame"]},
    "item_artifact_invisibility" => {"progs/invisibl.mdl", ["frame"]},
    "light_torch_small_walltorch" => {"progs/flame.mdl", ["flame"]},
    "light_flame_large_yellow" => {"progs/flame2.mdl", ["flameb"]},
    "light_flame_small_yellow" => {"progs/flame2.mdl", ["flame"]},
    "light_flame_small_white" => {"progs/flame2.mdl", ["flame"]}
  }

  @skins %{"item_armor2" => 1}

  @boxes %{
    {"item_health", 0} => "maps/b_bh25.bsp",
    {"item_health", 1} => "maps/b_bh10.bsp",
    {"item_health", 2} => "maps/b_bh100.bsp",
    {"item_shells", 0} => "maps/b_shell0.bsp",
    {"item_shells", 1} => "maps/b_shell1.bsp",
    {"item_spikes", 0} => "maps/b_nail0.bsp",
    {"item_spikes", 1} => "maps/b_nail1.bsp",
    {"item_rockets", 0} => "maps/b_rock0.bsp",
    {"item_rockets", 1} => "maps/b_rock1.bsp",
    {"item_cells", 0} => "maps/b_batt0.bsp",
    {"item_cells", 1} => "maps/b_batt1.bsp",
    {"misc_explobox", 0} => "maps/b_explob.bsp"
  }

  @doc "Uploads and places every thing in `entities` the tables know, ids from `first_id`; returns the things and the spawning changes."
  def spawn(gpu, files, bsp, entities, palette, first_id) do
    loaded = %{}

    {things, _loaded, _id} =
      entities
      |> Enum.filter(&(band(flags(&1), @not_on_normal_skill) == 0))
      |> Enum.reduce({[], loaded, first_id}, fn entity, {things, loaded, id} ->
        case thing(gpu, files, bsp, entity, palette, loaded, id) do
          {nil, loaded} -> {things, loaded, id}
          {thing, loaded} -> {[thing | things], loaded, id + 1}
        end
      end)

    things = Enum.reverse(things)
    {things, Enum.flat_map(things, &placing/1)}
  end

  @doc "The changes posing every thing at `time` seconds."
  def tick(things, time), do: Enum.flat_map(things, &changes(&1, time))

  defp placing(%{kind: :brush, id: id, instance: instance}), do: [{:instance, id, instance}]
  defp placing(thing), do: changes(thing, 0.0)

  defp changes(%{kind: :brush}, _time), do: []

  defp changes(%{kind: :alias} = thing, time) do
    instance =
      if AliasModel.rotates?(thing.model),
        do: %{thing.instance | transform: Placement.transform(@scale, thing.origin, thing.angle + 100 * time)},
        else: thing.instance

    AliasModel.animate(thing.model, thing.id, instance, thing.animation, time + thing.offset)
  end

  defp thing(gpu, files, bsp, entity, palette, loaded, id) do
    classname = entity["classname"]

    cond do
      Map.has_key?(@models, classname) -> alias_thing(gpu, files, bsp, entity, palette, loaded, id)
      Map.has_key?(@boxes, {classname, band(flags(entity), 3)}) -> brush_thing(gpu, files, entity, palette, loaded, id)
      true -> {nil, loaded}
    end
  end

  defp alias_thing(gpu, files, bsp, entity, palette, loaded, id) do
    {path, animations} = Map.fetch!(@models, entity["classname"])

    case load(loaded, path, fn -> alias_model(gpu, files, path, palette) end) do
      {nil, loaded} ->
        {nil, loaded}

      {model, loaded} ->
        origin = Entities.vector(entity["origin"]) || {0.0, 0.0, 0.0}
        angle = Entities.number(entity["angle"]) || 0.0
        light = light_texture(gpu, bsp, origin)
        material = AliasModel.material(gpu, model, skin: Map.get(@skins, entity["classname"], 0), lightmap: light)

        thing = %{
          kind: :alias,
          id: id,
          model: model,
          origin: origin,
          angle: angle,
          animation: Enum.at(animations, rem(id, length(animations))),
          offset: :erlang.phash2(id, 1000) / 1000,
          instance: AliasModel.instance(model, [material], Placement.transform(@scale, origin, angle)),
          keeps: [material, light]
        }

        {thing, loaded}
    end
  end

  defp brush_thing(gpu, files, entity, palette, loaded, id) do
    path = Map.fetch!(@boxes, {entity["classname"], band(flags(entity), 3)})

    case load(loaded, path, fn -> brush_model(gpu, files, path, palette) end) do
      {nil, loaded} ->
        {nil, loaded}

      {world, loaded} ->
        [{mesh, materials} | _] = world.models
        origin = Entities.vector(entity["origin"]) || {0.0, 0.0, 0.0}
        transform = Placement.transform(@scale, origin, 0)
        {%{kind: :brush, id: id, instance: %Instance{mesh: mesh, materials: materials, transform: transform}, keeps: [world]}, loaded}
    end
  end

  defp load(loaded, path, build) do
    case loaded do
      %{^path => value} -> {value, loaded}
      _ -> then(build.(), &{&1, Map.put(loaded, path, &1)})
    end
  end

  defp alias_model(gpu, files, path, palette) do
    with bytes when is_binary(bytes) <- Files.read(files, path),
         {:ok, mdl} <- Mdl.parse(bytes) do
      AliasModel.upload(gpu, mdl, palette, names: AliasModel.frame_names(bytes))
    else
      _ -> nil
    end
  end

  defp brush_model(gpu, files, path, palette) do
    with bytes when is_binary(bytes) <- Files.read(files, path),
         {:ok, %{bsp: bsp}} <- Bsp.parse(bytes) do
      CauldronGPU.Bsp.upload(gpu, bsp, palette, scale: @scale)
    else
      _ -> nil
    end
  end

  defp light_texture(gpu, bsp, {x, y, z}) do
    {{r, g, b}, _direction} = Cauldron3D.Bsp.Light.point(bsp, {x, y, z}, %{})
    pixel = for value <- [r, g, b], into: <<>>, do: <<min(round(value), 255)>>
    CauldronGPU.texture(gpu, %Texture{width: 1, height: 1, pixels: pixel <> <<255>>, format: :linear, wrap: :clamp, mipmaps: false})
  end

  defp flags(entity), do: trunc(Entities.number(entity["spawnflags"]) || 0)
end

defmodule QuakeMap do
  @moduledoc """
  Walks a Quake map drawn on the graphics card: its textures, lightmaps and brush
  models, from the player start. Fly with W A S D, Space and Left Shift, look with the
  mouse, Escape quits.

      mix run examples/quake_map.exs ~/quake e1m1 [seconds] [backend]

  The first argument is the game directory (holding `id1`). With `seconds` the walk
  stops by itself; with `CAPTURE=path.png` set it saves the last frame before closing,
  and `CAPTURE_AT=seconds` saves one that many seconds in as `path` with `-early` before
  its extension. `EFFECTS=rt` adds ray-traced ambient occlusion over the lightmaps.
  `VIEW="x y z yaw"` starts at that map point instead of the player start.
  `MONSTERS=1` adds the map's monsters, pickups and flames (`QuakeMap.Things`).
  Light styles 0 to 11 flicker and pulse by the patterns in `@light_styles`.
  """

  alias Cauldron3D.Formats.{Bsp, Entities, Files}
  alias CauldronGPU.{Camera, Environment, Quat}

  @tick_ms 33

  @light_styles [
    "m",
    "mmlmnmmkmmnolmmmjmnm",
    "dfhjlnprtvxzxvtrpnljhf",
    "mmmlmmnmmmmlkmmnmmmlmmonmmm",
    "mmmaaammmaaa",
    "jklmnopqrqponmlk",
    "nmlnkmnonmlmmnjmn",
    "mmnmmmlmmmnommmlmmn",
    "lmmmnmmmmlmmkmmmnmm",
    "aaaaaaazzzzzzz",
    "mmmmmmammmmmmmmmamammmmm",
    "acegikmkigec"
  ]

  def run([directory, map | rest]) do
    {seconds, backend} = parse(rest)
    {:ok, files} = Files.open(Path.expand(directory), within: "id1")
    palette = binary_part(Files.read(files, "gfx/palette.lmp"), 0, 768)
    {:ok, %{bsp: bsp, entities: text}} = Bsp.parse(Files.read(files, "maps/#{map}.bsp"), texture: &texture/2)
    {:ok, gpu} = CauldronGPU.open(title: "#{map} — cauldron_gpu", width: 1280, height: 720, backend: backend)
    IO.inspect(gpu.info, label: "device")
    {micros, world} = :timer.tc(fn -> CauldronGPU.Bsp.upload(gpu, bsp, palette) end)
    IO.puts("uploaded #{tuple_size(bsp.faces)} faces in #{div(micros, 1000)} ms")
    entities = Entities.parse(text)
    {origin, angle} = view(System.get_env("VIEW")) || spawn_point(entities)
    {things, spawned} = things(System.get_env("MONSTERS"), gpu, files, bsp, entities, palette, length(world.models) + 1)
    environment = %Environment{ambient_intensity: 0.0, fog_density: 0.0, reflections: 0.0, ao_radius: 1.2, sky_picture: CauldronGPU.Bsp.sky_layers(gpu, bsp, palette)}
    CauldronGPU.submit(gpu, [environment, effects(System.get_env("EFFECTS")), light_styles(0.0) | CauldronGPU.Bsp.instances(world)] ++ spawned)
    if seconds == nil, do: CauldronGPU.relative_mouse(gpu, true)
    started = System.monotonic_time(:millisecond)
    early = early_capture(System.get_env("CAPTURE"), System.get_env("CAPTURE_AT"))
    state = %{gpu: gpu, world: world, things: things, started: started, early: early, position: CauldronGPU.Bsp.point(world, add(origin, {0, 0, 22})), yaw: angle, pitch: 0.0, keys: MapSet.new()}
    loop(state, seconds && started + seconds * 1000)
    IO.puts("frames drawn: #{CauldronGPU.frames(gpu)}")
    save_capture(gpu, System.get_env("CAPTURE"))
    CauldronGPU.close(gpu)
  end

  defp things(monsters, _gpu, _files, _bsp, _entities, _palette, _first_id) when monsters in [nil, "", "0"], do: {[], []}

  defp things(_monsters, gpu, files, bsp, entities, palette, first_id) do
    {micros, {things, changes}} = :timer.tc(fn -> QuakeMap.Things.spawn(gpu, files, bsp, entities, palette, first_id) end)
    IO.puts("placed #{length(things)} things in #{div(micros, 1000)} ms")
    {things, changes}
  end

  defp light_styles(time), do: {:light_styles, Enum.map(@light_styles, &CauldronGPU.Bsp.light_style(&1, time))}

  defp early_capture(nil, _at), do: nil
  defp early_capture(_path, nil), do: nil

  defp early_capture(path, at) do
    {seconds, _} = Float.parse(at)
    {Path.rootname(path) <> "-early" <> Path.extname(path), round(seconds * 1000)}
  end

  defp texture(name, mips) do
    kind =
      cond do
        String.starts_with?(name, "sky") -> :sky
        String.starts_with?(name, "*") -> :liquid
        name in ["trigger", "clip", "hint", "skip"] -> :hidden
        String.starts_with?(name, "{") -> :masked
        true -> :solid
      end

    %{Bsp.solid(name, mips) | kind: kind}
  end

  defp view(nil), do: nil

  defp view(text) do
    [x, y, z, yaw] = text |> String.split() |> Enum.map(&parse_number/1)
    {{x, y, z}, yaw}
  end

  defp spawn_point(entities) do
    start = Enum.find(entities, &(&1["classname"] == "info_player_start")) || %{}
    [x, y, z] = (start["origin"] || "0 0 0") |> String.split() |> Enum.map(&parse_number/1)
    {{x, y, z}, parse_number(start["angle"] || "0")}
  end

  defp parse_number(text) do
    case Float.parse(text) do
      {value, _} -> value
      :error -> 0.0
    end
  end

  defp effects(nil), do: {:effects, []}

  defp effects(names) do
    {:effects, names |> String.split(",") |> Enum.flat_map(&effect(&1, [:ray_traced_ambient_occlusion]))}
  end

  defp effect("rt", traced), do: traced
  defp effect("upscale", _traced), do: [:upscaling]
  defp effect(_, _traced), do: []

  defp parse([]), do: {nil, nil}
  defp parse([seconds]), do: {String.to_integer(seconds), nil}
  defp parse([seconds, "metal"]), do: {String.to_integer(seconds), :metal}
  defp parse([seconds, "vulkan"]), do: {String.to_integer(seconds), :vulkan}

  defp save_capture(_gpu, nil), do: :ok

  defp save_capture(gpu, path) do
    {:ok, frame} = CauldronGPU.capture(gpu)
    File.write!(path, CauldronGPU.PNG.encode(frame))
    IO.puts("saved #{frame.width}x#{frame.height} to #{path}")
  end

  defp loop(state, deadline) do
    now = System.monotonic_time(:millisecond)

    if deadline && now >= deadline do
      :done
    else
      time = (now - state.started) / 1000
      state = state |> drain_events() |> fly()
      camera = %Camera{position: state.position, rotation: rotation(state), fov_y: 1.3, near: 0.05, far: 400.0}
      CauldronGPU.submit(state.gpu, [camera, light_styles(time) | QuakeMap.Things.tick(state.things, time)])
      state = maybe_capture_early(state, now - state.started)
      if state[:quit], do: :done, else: (Process.sleep(@tick_ms); loop(state, deadline))
    end
  end

  defp maybe_capture_early(%{early: {path, at}} = state, elapsed) when elapsed >= at do
    save_capture(state.gpu, path)
    %{state | early: nil}
  end

  defp maybe_capture_early(state, _elapsed), do: state

  defp rotation(state), do: CauldronGPU.Bsp.facing(state.yaw, state.pitch)

  defp drain_events(state) do
    id = state.gpu.id

    receive do
      {:cauldron_gpu, ^id, {:key, :down, :escape, _}} -> Map.put(state, :quit, true)
      {:cauldron_gpu, ^id, :close_requested} -> Map.put(state, :quit, true)
      {:cauldron_gpu, ^id, {:key, :down, key, _}} -> drain_events(%{state | keys: MapSet.put(state.keys, key)})
      {:cauldron_gpu, ^id, {:key, :up, key, _}} -> drain_events(%{state | keys: MapSet.delete(state.keys, key)})
      {:cauldron_gpu, ^id, {:mouse_motion, _, _, dx, dy}} ->
        drain_events(%{state | yaw: state.yaw - dx * 0.15, pitch: max(min(state.pitch - dy * 0.003, 1.5), -1.5)})

      {:cauldron_gpu, ^id, {:error, message}} -> IO.puts("renderer: #{message}") && drain_events(state)
      {:cauldron_gpu, ^id, _} -> drain_events(state)
    after
      0 -> state
    end
  end

  defp fly(state) do
    turn = rotation(state)

    step =
      Enum.reduce([w: {0, 0, -1}, s: {0, 0, 1}, a: {-1, 0, 0}, d: {1, 0, 0}], {0.0, 0.0, 0.0}, fn {key, direction}, total ->
        if MapSet.member?(state.keys, key), do: add(total, Quat.rotate(turn, direction)), else: total
      end)

    rise = if(MapSet.member?(state.keys, :space), do: 1.0, else: 0.0) - if(MapSet.member?(state.keys, :left_shift), do: 1.0, else: 0.0)
    %{state | position: add(state.position, scale(add(step, {0.0, rise, 0.0}), 0.3))}
  end

  defp add({ax, ay, az}, {bx, by, bz}), do: {ax + bx, ay + by, az + bz}
  defp scale({x, y, z}, factor), do: {x * factor, y * factor, z * factor}
end

QuakeMap.run(System.argv())
