defmodule Courtyard.Game do
  @moduledoc """
  The courtyard's world: the scene shown (`Courtyard.Scenes`), each viewer's character
  and camera in each scene, the hour of the atrium's sun, how many crates circle the
  courtyard, how wide the picture is drawn and which effects are on. This is a
  `Cauldron.Game`; nothing here reads a clock, a file or draws.

  Each viewer walks a character (`Courtyard.Character`) seen from behind. Each tick:

    * `:turn_left`, `:turn_right`, `:look_up`, `:look_down` swing the camera round the
      character at the keys' rate, and `:pointer_left`, `:pointer_right`, `:pointer_up`,
      `:pointer_down` at the pointer's, scaled by the input's `:strength`; `:closer` and
      `:farther` move it in and out
    * `:forward`, `:back`, `:strafe_left`, `:strafe_right` walk the character relative to
      the camera, faster the harder they are held, up to a run; the character turns to
      face the way it walks and slides along what blocks it (the scene's walk grid,
      `Courtyard.Grounds`)
    * the character is posed (`Courtyard.Gait`), its hair and clothes swing
      (`Cauldron3D.SpringBones`) and its skins' bone matrices are made for the view
    * the camera stays on the near side of anything between it and the character

  A press of `:next_scene`, `:scene_1`, `:scene_2` or `:scene_3` shows another scene,
  where the character is back where it last stood in it (first at its `start/0`); of
  `:more_crates` or `:fewer_crates` changes the crates by a step; of `:finer` or
  `:coarser` the picture width through its widths; of `:ray_tracing`,
  `:global_illumination` or `:upscaling` switches that effect. `:earlier` and `:later`
  move the hour.

  ## Options

    * `:character` — a loaded `Courtyard.Character`; without it the camera circles an
      unseen walker
    * `:grounds` — walk grids by scene; a scene without one has no walls
    * `:tuning` — overrides on `tuning/0`
  """

  @behaviour Cauldron.Game

  alias Cauldron3D.Formats.Gltf.Rig
  alias Cauldron3D.Formats.Vrm
  alias Cauldron3D.{Skeleton, SpringBones, WalkGrid}
  alias Courtyard.{Character, Gait, Scenes}

  @up {0.0, 1.0, 0.0}

  @type place :: %{
          position: {float(), float(), float()},
          facing: float(),
          speed: float(),
          phase: float(),
          camera: %{yaw: float(), pitch: float(), distance: float()}
        }
  @type viewer :: %{
          places: %{Scenes.scene() => place()},
          held: MapSet.t(atom()),
          presses: Cauldron.Presses.t(),
          strength: %{atom() => float()},
          springs: SpringBones.t() | nil,
          posed: map() | nil,
          camera: map() | nil
        }
  @type t :: %__MODULE__{
          viewers: %{term() => viewer()},
          scene: Scenes.scene(),
          hour: float(),
          crates: pos_integer(),
          width: pos_integer(),
          effects: %{ray_tracing: boolean(), global_illumination: boolean(), upscaling: boolean()},
          time: float(),
          character: Character.t() | nil,
          grounds: %{Scenes.scene() => WalkGrid.t()},
          tuning: map()
        }

  defstruct viewers: %{},
            scene: :courtyard,
            hour: 13.0,
            crates: 8,
            width: 640,
            effects: %{ray_tracing: false, global_illumination: false, upscaling: false},
            time: 0.0,
            character: nil,
            grounds: %{},
            tuning: %{}

  @numbered [scene_1: 0, scene_2: 1, scene_3: 2]

  @doc """
  The tuning a world starts with: `:run` (metres a second at full input), `:accelerate`
  (metres a second each second), `:turn` (radians a second the character turns to face
  its way), `:radius` (the character's, against walls), `:key_turn` and `:pointer_turn`
  (radians a second the camera swings), `:zoom` (metres a second), `:distance`,
  `:nearest`, `:farthest` (the camera's distance), `:shoulder` (the height it looks at),
  `:crate_step`, `:fewest_crates`, `:most_crates`, the picture `:widths` and the
  `:width` it starts at, the `:hour` the sun starts at, how many hours a second
  `:earlier` and `:later` move it (`:hour_rate`) and the hours it stays between (`:dawn`,
  `:dusk`).
  """
  @spec tuning() :: map()
  def tuning do
    %{
      run: 3.4,
      accelerate: 9.0,
      turn: 9.0,
      radius: 0.28,
      key_turn: 1.8,
      pointer_turn: 3.0,
      zoom: 3.0,
      distance: 3.0,
      nearest: 1.2,
      farthest: 7.0,
      shoulder: 1.35,
      crate_step: 8,
      fewest_crates: 8,
      most_crates: 96,
      widths: [320, 480, 640, 960, 1280],
      width: 640,
      hour: 13.0,
      hour_rate: 2.0,
      dawn: 6.0,
      dusk: 18.0
    }
  end

  @doc """
  The world options a client gives when it starts the world itself: the character, read
  from its download (`nil` without one), and every downloaded scene's walk grid.
  """
  @spec prepared() :: keyword()
  def prepared do
    character =
      case Courtyard.Character.load() do
        {:ok, character} -> character
        {:error, _reason} -> nil
      end

    [character: character, grounds: Courtyard.Grounds.all()]
  end

  @impl true
  def init(opts) do
    tuning = Map.merge(tuning(), Map.new(Keyword.get(opts, :tuning, [])))

    %__MODULE__{
      tuning: tuning,
      crates: tuning.fewest_crates,
      width: tuning.width,
      hour: tuning.hour,
      character: Keyword.get(opts, :character),
      grounds: Keyword.get(opts, :grounds, %{})
    }
  end

  @impl true
  def join(%__MODULE__{} = game, id, _props) do
    places = Map.new(Scenes.all(), &{&1, start_place(&1, game.tuning)})

    viewer = %{
      places: places,
      held: MapSet.new(),
      presses: Cauldron.Presses.new(),
      strength: %{},
      springs: nil,
      posed: nil,
      camera: nil
    }

    {:ok, %{game | viewers: Map.put(game.viewers, id, viewer)}}
  end

  @impl true
  def leave(%__MODULE__{} = game, id), do: %{game | viewers: Map.delete(game.viewers, id)}

  @impl true
  def handle_input(%__MODULE__{} = game, id, %{held: held} = input) do
    case Map.fetch(game.viewers, id) do
      {:ok, viewer} ->
        viewer = %{viewer | held: held, strength: Map.get(input, :strength, %{})}
        %{game | viewers: Map.put(game.viewers, id, viewer)}

      :error ->
        game
    end
  end

  @impl true
  def step(%__MODULE__{} = game, dt) do
    shown = game.scene
    game = game.viewers |> Map.values() |> Enum.reduce(game, &pressed/2) |> houred(dt)
    switched? = game.scene != shown

    viewers =
      Map.new(game.viewers, fn {id, viewer} ->
        viewer = if switched?, do: %{viewer | springs: nil}, else: viewer

        {id,
         %{
           advanced(game, viewer, dt)
           | presses: Cauldron.Presses.settle(viewer.presses, viewer.held, dt)
         }}
      end)

    %{game | viewers: viewers, time: game.time + dt}
  end

  @impl true
  def view(%__MODULE__{} = game, id) do
    viewer = Map.get(game.viewers, id)

    %{
      scene: game.scene,
      hour: game.hour,
      crates: game.crates,
      width: game.width,
      effects: game.effects,
      time: game.time,
      character: viewer && viewer.posed,
      camera: viewer && viewer.camera
    }
  end

  @impl true
  def drain_events(game), do: {[], game}

  defp start_place(scene, tuning) do
    start = Scenes.module(scene).start()

    %{
      position: start.position,
      facing: start.yaw,
      speed: 0.0,
      phase: 0.0,
      camera: %{yaw: start.yaw, pitch: start.pitch, distance: tuning.distance}
    }
  end

  defp advanced(game, viewer, dt) do
    place =
      viewer.places
      |> Map.fetch!(game.scene)
      |> swung(viewer, game.tuning, dt)
      |> walked(viewer, Map.get(game.grounds, game.scene), game.tuning, dt)

    viewer = %{viewer | places: Map.put(viewer.places, game.scene, place)}
    viewer = posed(viewer, game.character, place, game.time, dt)
    %{viewer | camera: camera(place, Map.get(game.grounds, game.scene), game.tuning)}
  end

  defp swung(place, viewer, tuning, dt) do
    camera = place.camera

    yaw =
      camera.yaw + turn(viewer, :turn_left, :turn_right, tuning.key_turn * dt) +
        turn(viewer, :pointer_left, :pointer_right, tuning.pointer_turn * dt)

    pitch =
      (camera.pitch + turn(viewer, :look_up, :look_down, tuning.key_turn * dt) +
         turn(viewer, :pointer_up, :pointer_down, tuning.pointer_turn * dt))
      |> max(-1.2)
      |> min(0.6)

    distance =
      (camera.distance + turn(viewer, :farther, :closer, tuning.zoom * dt))
      |> max(tuning.nearest)
      |> min(tuning.farthest)

    %{place | camera: %{camera | yaw: yaw, pitch: pitch, distance: distance}}
  end

  defp walked(place, viewer, grid, tuning, dt) do
    ahead = amount(viewer, :forward) - amount(viewer, :back)
    across = amount(viewer, :strafe_right) - amount(viewer, :strafe_left)
    push = min(:math.sqrt(ahead * ahead + across * across), 1.0)
    yaw = place.camera.yaw

    {dx, dz} =
      {-:math.sin(yaw) * ahead + :math.cos(yaw) * across,
       -:math.cos(yaw) * ahead - :math.sin(yaw) * across}

    facing =
      if push > 0.05,
        do: towards(place.facing, :math.atan2(-dx, -dz), tuning.turn * dt),
        else: place.facing

    speed = approach(place.speed, push * tuning.run, tuning.accelerate * dt)
    {x, y, z} = place.position
    to = {x - :math.sin(facing) * speed * dt, z - :math.cos(facing) * speed * dt}
    {nx, nz} = if grid, do: WalkGrid.slide(grid, {x, z}, to, tuning.radius), else: to
    moved = :math.sqrt((nx - x) * (nx - x) + (nz - z) * (nz - z)) / max(dt, 1.0e-6)
    speed = min(speed, moved)

    %{
      place
      | position: {nx, y, nz},
        facing: facing,
        speed: speed,
        phase: place.phase + 2 * :math.pi() * speed * dt / Gait.stride(speed)
    }
  end

  defp posed(viewer, nil, _place, _time, _dt), do: %{viewer | posed: nil}

  defp posed(viewer, %Character{rig: rig} = character, place, time, dt) do
    %{turns: turns, dip: dip} = Gait.pose(character.bones, place.speed, place.phase, time)
    {x, y, z} = place.position
    rotation = Cauldron3D.Quat.axis_angle(@up, place.facing)
    root = Skeleton.transform({x, y - dip, z}, rotation)
    springs = viewer.springs || Vrm.spring_bones(character.vrm, rig, root)

    {transforms, springs} =
      SpringBones.pose(springs, rig.parents, Rig.locals(rig, turns), root, dt)

    unroot = Rig.invert(root)
    skins = Map.new(0..(length(rig.skins) - 1)//1, &{&1, Rig.bones(rig, transforms, &1, unroot)})

    %{
      viewer
      | springs: springs,
        posed: %{position: {x, y - dip, z}, rotation: rotation, skins: skins}
    }
  end

  defp camera(place, grid, tuning) do
    {x, y, z} = place.position
    camera = place.camera
    rotation = Cauldron3D.Scene.Quat.yaw_pitch(camera.yaw, camera.pitch)
    {bx, by, bz} = Cauldron3D.Scene.Quat.rotate(rotation, {0.0, 0.0, camera.distance})
    pivot_y = y + tuning.shoulder

    reach =
      if grid do
        {rx, rz} = WalkGrid.reach(grid, {x, z}, {x + bx, z + bz}, 0.15)
        across = :math.sqrt(bx * bx + bz * bz)

        if across > 1.0e-6,
          do: :math.sqrt((rx - x) * (rx - x) + (rz - z) * (rz - z)) / across,
          else: 1.0
      else
        1.0
      end

    %{
      position: {x + bx * reach, max(pivot_y + by * reach, y + 0.15), z + bz * reach},
      rotation: rotation
    }
  end

  defp towards(from, to, step) do
    gap = :math.atan2(:math.sin(to - from), :math.cos(to - from))
    if abs(gap) <= step, do: to, else: from + step * sign(gap)
  end

  defp approach(from, to, step) when from < to, do: min(from + step, to)
  defp approach(from, to, step), do: max(from - step, to)

  defp sign(value) when value < 0, do: -1.0
  defp sign(_value), do: 1.0

  defp pressed(viewer, game) do
    tuning = game.tuning

    game
    |> press(viewer, :next_scene, &%{&1 | scene: Scenes.next(&1.scene)})
    |> numbered(viewer)
    |> press(
      viewer,
      :more_crates,
      &%{&1 | crates: min(&1.crates + tuning.crate_step, tuning.most_crates)}
    )
    |> press(
      viewer,
      :fewer_crates,
      &%{&1 | crates: max(&1.crates - tuning.crate_step, tuning.fewest_crates)}
    )
    |> press(viewer, :finer, &%{&1 | width: next_width(&1, 1)})
    |> press(viewer, :coarser, &%{&1 | width: next_width(&1, -1)})
    |> press(viewer, :ray_tracing, &switch(&1, :ray_tracing))
    |> press(viewer, :global_illumination, &switch(&1, :global_illumination))
    |> press(viewer, :upscaling, &switch(&1, :upscaling))
  end

  defp numbered(game, viewer) do
    Enum.reduce(@numbered, game, fn {action, index}, acc ->
      press(acc, viewer, action, &%{&1 | scene: Enum.at(Scenes.all(), index)})
    end)
  end

  defp press(game, viewer, action, change) do
    if MapSet.member?(Cauldron.Presses.pressed(viewer.presses, viewer.held), action),
      do: change.(game),
      else: game
  end

  defp houred(game, dt) do
    shift =
      game.viewers
      |> Map.values()
      |> Enum.map(&(amount(&1, :later) - amount(&1, :earlier)))
      |> Enum.sum()

    hour =
      (game.hour + shift * game.tuning.hour_rate * dt)
      |> max(game.tuning.dawn)
      |> min(game.tuning.dusk)

    %{game | hour: hour}
  end

  defp switch(game, effect), do: %{game | effects: Map.update!(game.effects, effect, &(not &1))}

  defp next_width(game, direction) do
    widths = game.tuning.widths
    index = Enum.find_index(widths, &(&1 == game.width)) || 0
    Enum.at(widths, index |> Kernel.+(direction) |> max(0) |> min(length(widths) - 1))
  end

  defp turn(viewer, positive, negative, step),
    do: (amount(viewer, positive) - amount(viewer, negative)) * step

  defp amount(viewer, action) do
    if MapSet.member?(viewer.held, action), do: Map.get(viewer.strength, action, 1.0), else: 0.0
  end
end
