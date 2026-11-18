defmodule Vale.Game do
  @moduledoc """
  The vale's world: each viewer's walker on the land (`Vale.Land`), the clips it plays,
  its camera and the hour of the day. This is a `Cauldron.Game`; nothing here reads a
  clock, a file or draws.

  Each tick, for every viewer:

    * `:turn_left`, `:turn_right`, `:look_up`, `:look_down` swing the camera round the
      walker, and so does the pointer's travel (the input's `:drag`) while `:orbit` is
      held; `:closer` and `:farther` move it in and out
    * `:forward`, `:back`, `:strafe_left`, `:strafe_right` send the walker that way
      relative to the camera; `:dash` runs it flat out while its stamina lasts; a press
      of `:leap` jumps, or lets go of a rock face
    * the walker moves as `Cauldron.OpenWorld.Mover` allows: it walks, falls, climbs
      what is too steep to walk and swims in the lake, and the land's edges stop it
    * its clips are mixed for what it is doing (`Cauldron3D.Formats.Gltf.Mixer`) and its
      bones posed (`Vale.Figure`)
    * the camera is kept above the ground

  A press of `:wave` plays the wave while the walker stands. `:earlier` and `:later`
  move the hour.

  ## Options

    * `:figure` — a loaded `Vale.Figure`; without it nothing is posed
    * `:map` — the land; default `Vale.Land.map/0`
    * `:tuning` — overrides on `tuning/0`
  """

  @behaviour Cauldron.Game

  alias Cauldron.OpenWorld.Map, as: World
  alias Cauldron.OpenWorld.Mover
  alias Cauldron3D.Formats.Gltf.Mixer
  alias Cauldron3D.Scene.Quat
  alias Vale.{Figure, Land}

  @type t :: %__MODULE__{
          viewers: %{term() => map()},
          map: World.t(),
          figure: Figure.t() | nil,
          hour: float(),
          time: float(),
          tuning: map()
        }

  @enforce_keys [:map, :tuning]
  defstruct [:map, :tuning, viewers: %{}, figure: nil, hour: 10.5, time: 0.0]

  @doc """
  The tuning a world starts with: `:pace`, what the walker can do
  (`Cauldron.OpenWorld.Mover`); `:strides`, the ground speed each of the walk, jog and
  sprint clips is drawn for; `:key_turn` (radians a second the camera swings); `:drag_turn`
  (radians it swings for each unit the pointer is dragged across, and twice that for each
  unit down); `:zoom` (metres a second); `:distance`, `:nearest`, `:farthest` (the camera's
  distance); `:shoulder` (the height it looks at); `:clearance` (how far it stays above
  the ground); the `:hour` it starts at, how many hours a second `:earlier` and `:later`
  move it (`:hour_rate`) and the hours it stays between (`:dawn`, `:dusk`).
  """
  @spec tuning() :: map()
  def tuning do
    %{
      pace: %{
        run: 2.6,
        dash: 4.2,
        climb: 0.9,
        swim: 1.4,
        quicken: 14.0,
        turn: 10.0,
        leap: 4.4,
        fall: 14.0,
        steep: 1.0,
        ledge: 0.35,
        float: 0.6,
        draft: 0.62,
        radius: 0.22,
        tire_dash: 0.12,
        tire_climb: 0.09,
        tire_swim: 0.02,
        rest: 0.3
      },
      strides: %{walk: 0.9, jog: 2.1, sprint: 3.6},
      key_turn: 1.9,
      drag_turn: 0.02,
      zoom: 3.0,
      distance: 3.2,
      nearest: 1.2,
      farthest: 9.0,
      shoulder: 0.75,
      clearance: 0.3,
      hour: 10.5,
      hour_rate: 2.0,
      dawn: 5.5,
      dusk: 19.0
    }
  end

  @doc "The world options a client gives when it starts the world itself: the figure, read from its files."
  @spec prepared() :: keyword()
  def prepared do
    case Figure.load() do
      {:ok, figure} -> [figure: figure]
      {:error, _reason} -> []
    end
  end

  @impl true
  def init(opts) do
    tuning = Map.merge(tuning(), Map.new(Keyword.get(opts, :tuning, [])))

    %__MODULE__{
      map: Keyword.get_lazy(opts, :map, &Land.map/0),
      figure: Keyword.get(opts, :figure),
      tuning: tuning,
      hour: tuning.hour
    }
  end

  @impl true
  def join(%__MODULE__{} = game, id, _props) do
    viewer = %{
      mover: Mover.new(Land.start(), game.map),
      mixer: Mixer.new(),
      camera: %{yaw: 0.25, pitch: -0.22, distance: game.tuning.distance},
      held: MapSet.new(),
      presses: Cauldron.Presses.new(),
      strength: %{},
      drag: {0.0, 0.0},
      dragged: {0.0, 0.0},
      posed: nil,
      eye: nil
    }

    {:ok, %{game | viewers: Map.put(game.viewers, id, viewer)}}
  end

  @impl true
  def leave(%__MODULE__{} = game, id), do: %{game | viewers: Map.delete(game.viewers, id)}

  @impl true
  def handle_input(%__MODULE__{} = game, id, %{held: held} = input) do
    case Map.fetch(game.viewers, id) do
      {:ok, viewer} ->
        viewer = %{
          viewer
          | held: held,
            strength: Map.get(input, :strength, %{}),
            drag: Map.get(input, :drag, viewer.drag)
        }

        %{game | viewers: Map.put(game.viewers, id, viewer)}

      :error ->
        game
    end
  end

  @impl true
  def step(%__MODULE__{} = game, dt) do
    game = houred(game, dt)

    viewers =
      Map.new(game.viewers, fn {id, viewer} ->
        moved = advanced(game, viewer, dt)
        {id, %{moved | presses: Cauldron.Presses.settle(viewer.presses, viewer.held, dt)}}
      end)

    %{game | viewers: viewers, time: game.time + dt}
  end

  @impl true
  def view(%__MODULE__{} = game, id) do
    case Map.get(game.viewers, id) do
      nil ->
        %{hour: game.hour, time: game.time, walker: nil, posed: nil, camera: nil}

      viewer ->
        %{
          hour: game.hour,
          time: game.time,
          walker: Map.take(viewer.mover, [:point, :height, :mode, :stamina, :speed, :stopped]),
          posed: viewer.posed,
          camera: viewer.eye
        }
    end
  end

  @impl true
  def drain_events(game), do: {[], game}

  defp advanced(game, viewer, dt) do
    pressed = Cauldron.Presses.pressed(viewer.presses, viewer.held)
    camera = swung(viewer.camera, viewer, game.tuning, dt)

    intent = %{
      toward: toward(viewer, camera.yaw),
      dash: MapSet.member?(viewer.held, :dash),
      leap: MapSet.member?(pressed, :leap)
    }

    mover = Mover.step(viewer.mover, game.map, intent, game.tuning.pace, dt)
    mixer = mixed(viewer.mixer, mover, game, MapSet.member?(pressed, :wave), dt)

    %{
      viewer
      | camera: camera,
        dragged: viewer.drag,
        mover: mover,
        mixer: mixer,
        posed: posed(game.figure, mover, mixer),
        eye: eye(game, mover, camera)
    }
  end

  defp toward(viewer, yaw) do
    ahead = amount(viewer, :forward) - amount(viewer, :back)
    across = amount(viewer, :strafe_right) - amount(viewer, :strafe_left)
    x = -:math.sin(yaw) * ahead + :math.cos(yaw) * across
    y = -:math.cos(yaw) * ahead - :math.sin(yaw) * across
    length = :math.sqrt(x * x + y * y)
    if length > 1.0, do: {x / length, y / length}, else: {x, y}
  end

  defp swung(camera, viewer, tuning, dt) do
    {across, down} = dragged(viewer)

    yaw =
      camera.yaw + turn(viewer, :turn_left, :turn_right, tuning.key_turn * dt) -
        across * tuning.drag_turn

    pitch =
      (camera.pitch + turn(viewer, :look_up, :look_down, tuning.key_turn * dt) -
         down * 2.0 * tuning.drag_turn)
      |> max(-1.25)
      |> min(0.5)

    distance =
      (camera.distance + turn(viewer, :farther, :closer, tuning.zoom * dt))
      |> max(tuning.nearest)
      |> min(tuning.farthest)

    %{camera | yaw: yaw, pitch: pitch, distance: distance}
  end

  defp dragged(%{held: held, drag: {x, y}, dragged: {from_x, from_y}}) do
    if MapSet.member?(held, :orbit), do: {x - from_x, y - from_y}, else: {0.0, 0.0}
  end

  defp mixed(mixer, _mover, %__MODULE__{figure: nil}, _wave?, _dt), do: mixer

  defp mixed(mixer, mover, %__MODULE__{figure: figure, tuning: tuning}, wave?, dt) do
    {mix, opts, rate} = playing(mixer, mover, tuning.strides, wave?, figure.clips)
    mixer |> Mixer.play(mix, opts) |> Mixer.advance(figure.clips, dt, rate)
  end

  defp playing(mixer, %Mover{mode: :ground, speed: speed}, _strides, wave?, clips)
       when speed < 0.12 do
    waving? = match?(%{now: %{mix: [wave: _weight]}}, mixer) and not Mixer.done?(mixer, clips)

    if wave? or waving?,
      do: {[wave: 1.0], [fade: 0.2], 1.0},
      else: {[idle: 1.0], [loop: true, fade: 0.3], 1.0}
  end

  defp playing(_mixer, %Mover{mode: :ground, speed: speed}, strides, _wave?, _clips),
    do: stride(speed, strides)

  defp playing(_mixer, %Mover{mode: :air}, _strides, _wave?, _clips),
    do: {[fall: 1.0], [loop: true, fade: 0.15], 1.0}

  defp playing(_mixer, %Mover{mode: :climb, speed: speed}, _strides, _wave?, _clips),
    do: {[climb: 1.0], [loop: true, fade: 0.25], if(speed > 0.0, do: 1.0, else: 0.0)}

  defp playing(_mixer, %Mover{mode: :swim, speed: speed}, _strides, _wave?, _clips)
       when speed > 0.2,
       do: {[swim: 1.0], [loop: true, fade: 0.35], 1.0}

  defp playing(_mixer, %Mover{mode: :swim}, _strides, _wave?, _clips),
    do: {[tread: 1.0], [loop: true, fade: 0.35], 1.0}

  defp stride(speed, %{walk: walk}) when speed <= walk,
    do: {[walk: 1.0, jog: 0.0], [loop: true, fade: 0.2], max(speed / walk, 0.45)}

  defp stride(speed, %{walk: walk, jog: jog}) when speed <= jog do
    share = (speed - walk) / (jog - walk)
    {[walk: 1.0 - share, jog: share], [loop: true, fade: 0.2], 1.0}
  end

  defp stride(speed, %{jog: jog, sprint: sprint}) do
    share = min((speed - jog) / (sprint - jog), 1.0)
    {[jog: 1.0 - share, sprint: share], [loop: true, fade: 0.2], max(speed / sprint, 1.0)}
  end

  defp posed(nil, _mover, _mixer), do: nil

  defp posed(%Figure{} = figure, %Mover{point: {x, y}} = mover, mixer) do
    %{
      position: {x, mover.height + figure.lift, y},
      rotation:
        Quat.axis_angle(
          {0.0, 1.0, 0.0},
          :math.atan2(:math.cos(mover.heading), :math.sin(mover.heading))
        ),
      scale: figure.scale,
      skins: Figure.pose(figure, Mixer.sample(mixer, figure.clips))
    }
  end

  defp eye(game, %Mover{point: {x, y}} = mover, camera) do
    rotation = Quat.yaw_pitch(camera.yaw, camera.pitch)
    {boom_x, boom_y, boom_z} = Quat.rotate(rotation, {0.0, 0.0, camera.distance})
    {eye_x, eye_z} = {x + boom_x, y + boom_z}
    floor = (World.height(game.map, {eye_x, eye_z}) || mover.height) + game.tuning.clearance
    lake = (World.water(game.map, {eye_x, eye_z}) || floor) + game.tuning.clearance
    eye_y = Enum.max([mover.height + game.tuning.shoulder + boom_y, floor, lake])
    %{position: {eye_x, eye_y, eye_z}, rotation: rotation}
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

  defp turn(viewer, positive, negative, step),
    do: (amount(viewer, positive) - amount(viewer, negative)) * step

  defp amount(viewer, action) do
    if MapSet.member?(viewer.held, action), do: Map.get(viewer.strength, action, 1.0), else: 0.0
  end
end
