defmodule Vale.Client do
  @moduledoc """
  The vale as a `Cauldron.Client.Game`: an open land with a lake, meadows, woods and a
  crag, walked by a small figure seen from behind and drawn by the graphics card in the
  terminal or in a window of its own.

  The figure's files are copied in first with `mix vale.figure`.

      mix vale
      mix vale --window

  ## Keys

    * `W`/`S` or `↑`/`↓` — walk away from and towards the camera; `A`/`D` — walk across it
    * `X` or left `Shift`, held — dash while the stamina lasts
    * `Space` — jump, or let go of a rock face; walking into ground too steep to walk
      starts a climb
    * `←`/`→` — swing the camera round the figure; `PgUp`/`PgDn` — swing it up and down;
      `Z`/`C` — bring it closer or take it farther
    * the mouse — hold the right button and drag to swing the camera; the wheel brings
      it closer or takes it farther
    * `G` — wave
    * `,`/`.` — the sun earlier or later in the day
    * `F` — hides or shows the frames a second; `Tab` — the client's settings; `Q` — quit

  Under the picture a status bar shows what the figure is doing, its stamina, the hour
  and the keys, and says so when the end of the land has stopped it.

  A controller: the left stick walks, the right stick swings the camera, `A` jumps, `X`
  dashes and `Y` waves.
  """

  use Cauldron2D.Client.Game

  alias Vale.{Game, Picture}

  @atlas :vale
  @size {960, 540}
  @presses [:leap, :wave]
  @moving [
    :forward,
    :back,
    :strafe_left,
    :strafe_right,
    :dash,
    :orbit,
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
  def title, do: %{name: "VALE", tagline: "an open land on the graphics card"}

  @impl true
  def atlas do
    unless Cauldron2D.Atlas.installed?(@atlas) do
      @atlas |> Cauldron2D.Atlas.new(tile: 16, void: {0, 0, 0}) |> Cauldron2D.Atlas.install()
    end

    @atlas
  end

  @impl true
  def actions, do: @moving ++ @presses

  @impl true
  def keymaps do
    [
      keys: %{
        forward: [:w, :up],
        back: [:s, :down],
        strafe_left: [:a],
        strafe_right: [:d],
        dash: [:x, :left_shift],
        leap: [:" ", :space],
        wave: [:g],
        orbit: [{:mouse, :right}],
        turn_left: [:left],
        turn_right: [:right],
        closer: [:z, {:mouse, :wheel_up}],
        farther: [:c, {:mouse, :wheel_down}],
        look_up: [:page_up],
        look_down: [:page_down],
        earlier: [:","],
        later: [:.]
      }
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
      leap: [:a],
      dash: [:x],
      wave: [:y],
      closer: [:right_bumper],
      farther: [:left_bumper]
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
  def start, do: {:play, :vale}

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
        id: :vale,
        name: "Vale",
        world: {Game, hz: 60, game_opts: Map.get_lazy(props, :world, &Game.prepared/0)},
        players: 0,
        humans: []
      }
    ]
  end

  @impl true
  def scene(view, _look) do
    %{
      focus: {0.0, 0.0},
      bounds: :unbounded,
      cell: fn _cell -> nil end,
      movers: [],
      native: @size,
      gpu_size: @size,
      gpu: Picture.gpu(view)
    }
  end

  @impl true
  def hud(%{walker: %{} = walker, hour: hour} = view) do
    [
      {:status,
       [
         {" #{doing(walker.mode, walker.speed)}", %{fg: {20, 20, 20}, bold: true}},
         " · stamina ",
         {meter(walker.stamina), stamina_colour(walker.stamina)},
         " · " <> clock(hour),
         {"   WASD walk  X dash  Space jump  right-drag swing  wheel zoom  G wave  , . time  Tab settings  Q quit",
          {70, 70, 70}}
       ]}
    ] ++ edge(walker.stopped) ++ figure(view)
  end

  def hud(_view), do: []

  defp doing(:ground, speed) when speed < 0.12, do: "standing"
  defp doing(:ground, _speed), do: "walking"
  defp doing(:air, _speed), do: "in the air"
  defp doing(:climb, _speed), do: "climbing"
  defp doing(:swim, _speed), do: "swimming"

  defp meter(stamina) do
    full = round(stamina * 10)
    String.duplicate("█", full) <> String.duplicate("░", 10 - full)
  end

  defp stamina_colour(stamina) when stamina < 0.25, do: %{fg: {170, 40, 20}, bold: true}
  defp stamina_colour(_stamina), do: {0, 120, 40}

  defp clock(hour),
    do: "#{trunc(hour)}:#{String.pad_leading("#{trunc((hour - trunc(hour)) * 60)}", 2, "0")}"

  defp edge([]), do: []

  defp edge(_stopped),
    do: [{:status, [{" the land goes on, but not for walking", %{fg: {120, 50, 0}, bold: true}}]}]

  defp figure(%{posed: nil}),
    do: [{:status, [{" no figure: run mix vale.figure", %{fg: {120, 50, 0}, bold: true}}]}]

  defp figure(_view), do: []
end
