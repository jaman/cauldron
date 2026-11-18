defmodule Courtyard.Client do
  @moduledoc """
  The courtyard as a `Cauldron.Client.Game`: lit 3D scenes drawn by the graphics card
  in the terminal (or in a window of its own), or on the CPU where there is no card to
  draw on (`Cauldron3D.Scene.Software`). A character is walked with the keys, the mouse
  or a controller and seen from behind. It switches between the courtyard, a
  night-time alley and Intel's Sponza atrium (`Courtyard.Scenes`); the alley, the atrium
  and the character are downloaded first with `mix courtyard.fetch`.

  The world (`Courtyard.Game`) takes the character and the walk grids from the props'
  `:world` options (`Mix.Tasks.Courtyard` loads them).

      mix courtyard

  ## Keys

    * `W`/`S` or `↑`/`↓` — walk away from and towards the camera; `A`/`D` — walk across it
    * `←`/`→` — swing the camera round the character; `PgUp`/`PgDn` — swing it up and down;
      `Z`/`C` — bring it closer or take it farther
    * the mouse, once the `mouse` preset is chosen in the settings (`Tab`) — moving it
      swings the camera; in a window, a click captures the pointer and leaving the window
      lets it go
    * `R` — ray-traced shadows, reflections and ambient occlusion; `G` — ray-traced
      global illumination; `U` — drawing at a lower size and upscaling on the card
    * `=`/`-` — a wider or narrower picture, which the terminal scales to the pane
    * `]`/`[` — more or fewer crates
    * `1`, `2`, `3` — the courtyard, the alley, the atrium; `N` — the next scene. A scene
      loads while the one shown stays, dimmed, then fades in
    * `,`/`.` — the atrium's sun earlier or later in the day
    * `F` — hides or shows the frames a second; `?` — the key hints; `Tab` — the
      client's settings (frame rate, bindings); `Q` — quit

  Under the picture a status bar shows the scene, the effects, the crates, the picture
  size and the keys, or what a scene being switched to is doing (loading, not yet
  downloaded); under it the frames a second drawn and sent by the world.

  A controller: the left stick and d-pad walk, slower the less the stick is pushed; the
  right stick swings the camera, `A` brings it closer and `B` takes it farther; the
  bumpers change the crates.

  Where the terminal reports key releases a key is held as long as it is down; where it
  does not, it is held through the terminal's key repeat.
  """

  use Cauldron2D.Client.Game

  alias Cauldron.Net.Link
  alias Cauldron3D.Net.RemoteScene
  alias Courtyard.{Game, Loader, Picture, Scenes}

  @atlas :courtyard
  @presses [
    :more_crates,
    :fewer_crates,
    :finer,
    :coarser,
    :ray_tracing,
    :global_illumination,
    :upscaling,
    :next_scene,
    :scene_1,
    :scene_2,
    :scene_3
  ]
  @pointer [:pointer_left, :pointer_right, :pointer_up, :pointer_down]
  @moving [
    :forward,
    :back,
    :strafe_left,
    :strafe_right,
    :turn_left,
    :turn_right,
    :closer,
    :farther,
    :look_up,
    :look_down,
    :earlier,
    :later
  ]

  @impl true
  def title, do: %{name: "COURTYARD", tagline: "a lit scene on the graphics card"}

  @impl true
  def atlas do
    unless Cauldron2D.Atlas.installed?(@atlas) do
      @atlas |> Cauldron2D.Atlas.new(tile: 16, void: {0, 0, 0}) |> Cauldron2D.Atlas.install()
    end

    @atlas
  end

  @impl true
  def actions, do: @moving ++ @presses ++ @pointer

  @impl true
  def keymaps do
    keys = %{
      forward: [:w, :up],
      back: [:s, :down],
      strafe_left: [:a],
      strafe_right: [:d],
      turn_left: [:left],
      turn_right: [:right],
      closer: [:z],
      farther: [:c],
      look_up: [:page_up],
      look_down: [:page_down],
      more_crates: [:"]"],
      fewer_crates: [:"["],
      finer: [:=, :+],
      coarser: [:-],
      ray_tracing: [:r],
      global_illumination: [:g],
      upscaling: [:u],
      next_scene: [:n],
      scene_1: [:"1"],
      scene_2: [:"2"],
      scene_3: [:"3"],
      earlier: [:","],
      later: [:.],
      pointer_left: [],
      pointer_right: [],
      pointer_up: [],
      pointer_down: []
    }

    mouse = %{
      pointer_left: [{:mouse, :move_left}],
      pointer_right: [{:mouse, :move_right}],
      pointer_up: [{:mouse, :move_up}],
      pointer_down: [{:mouse, :move_down}]
    }

    [
      keyboard: keys,
      mouse: Map.merge(keys, mouse, fn _action, key, pointer -> key ++ pointer end)
    ]
  end

  @impl true
  def padmap(_props) do
    %{
      forward: [:dpad_up, {:axis, :left_y, :neg}],
      back: [:dpad_down, {:axis, :left_y, :pos}],
      strafe_left: [{:axis, :left_x, :neg}],
      strafe_right: [{:axis, :left_x, :pos}],
      turn_left: [:dpad_left, {:axis, :right_x, :neg}],
      turn_right: [:dpad_right, {:axis, :right_x, :pos}],
      look_up: [{:axis, :right_y, :neg}],
      look_down: [{:axis, :right_y, :pos}],
      closer: [:a],
      farther: [:b],
      next_scene: [:y],
      ray_tracing: [:x],
      more_crates: [:right_bumper],
      fewer_crates: [:left_bumper]
    }
  end

  @impl true
  def holds, do: Enum.map(@moving, &{&1, 160})

  @impl true
  def client_keys do
    %{
      fps: :f,
      title: :q,
      talk: nil,
      watch: nil,
      team: nil,
      chat: nil,
      guide: nil,
      settings_menu: nil,
      projection: nil,
      turn_left: nil,
      turn_right: nil,
      tilt_up: nil,
      tilt_down: nil,
      zoom_in: nil,
      zoom_out: nil,
      zoom_reset: nil
    }
  end

  @impl true
  def start, do: {:play, :courtyard}

  @impl true
  def look do
    %{
      projection: :picture,
      projections: [:picture],
      picture: [{:native, 1}, :swap],
      fps?: true
    }
  end

  @impl true
  def chat?, do: false

  @impl true
  def lobby?, do: false

  @impl true
  def worlds(props) do
    [
      %{
        id: :courtyard,
        name: "Courtyard",
        world: {Game, hz: 60, game_opts: Map.get_lazy(props, :world, &Game.prepared/0)},
        players: 0,
        humans: []
      }
    ]
  end

  @impl true
  def scene(%{remote: _} = view, _look), do: RemoteScene.scene(view)

  def scene(view, _look) do
    %{
      focus: {0.0, 0.0},
      bounds: :unbounded,
      cell: fn _cell -> nil end,
      movers: [],
      native: {view.width, round(view.width * 9 / 16)},
      gpu_size: {view.width, round(view.width * 9 / 16)},
      gpu: Picture.gpu(view)
    }
  end

  @impl true
  def hud(%{remote: _} = view), do: Link.World.hud(view)

  def hud(%{effects: effects, width: width} = view) do
    [
      {:status,
       [
         {" #{Scenes.module(view.scene).name()}", %{fg: {20, 20, 20}, bold: true}},
         " · ",
         effect("rt", effects.ray_tracing),
         " · ",
         effect("gi", effects.global_illumination),
         " · ",
         effect("upscale", effects.upscaling),
         " · " <> detail(view) <> " · picture #{width}×#{round(width * 9 / 16)}",
         {"   WASD walk  ←→ PgUp PgDn swing  Z C zoom  1 2 3 N scene  R G U effects  = - picture  " <>
            keys(view.scene) <> "Tab settings  Q quit", {70, 70, 70}}
       ]}
    ] ++ loading() ++ walker(view)
  end

  def hud(_view), do: []

  defp detail(%{scene: :courtyard, crates: crates}), do: "#{crates} crates"

  defp detail(%{scene: :atrium, hour: hour}),
    do: "#{trunc(hour)}:#{String.pad_leading("#{trunc((hour - trunc(hour)) * 60)}", 2, "0")}"

  defp detail(_view), do: "night"

  defp keys(:courtyard), do: "[ ] crates  "
  defp keys(:atrium), do: ", . time  "
  defp keys(_scene), do: ""

  defp walker(%{character: nil}),
    do: [
      {:status,
       [{" no character: run mix courtyard.fetch character", %{fg: {120, 50, 0}, bold: true}}]}
    ]

  defp walker(_view), do: []

  defp loading do
    case Loader.note() do
      nil -> []
      note -> [{:status, [{" " <> note, %{fg: {120, 50, 0}, bold: true}}]}]
    end
  end

  defp effect(name, true),
    do: {name <> " on", %{fg: {0, 120, 40}, bold: true}}

  defp effect(name, false), do: {name <> " off", {90, 90, 90}}
end
