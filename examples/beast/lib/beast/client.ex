defmodule Beast.Client do
  @moduledoc """
  The `Cauldron2D.Client.Game` for the beast: a side-scrolling run across a sunset plain
  under five parallax layers.

      mix beast

  Arrow keys or A and D run, space jumps, `^Q` quits. The sunset holds still, the ridge
  and the ruins slide at a fifth and two fifths of the runner's pace, a scattered treeline
  at under two thirds, and the scrub blows past in front at a third again faster than the
  ground.
  """

  @behaviour Cauldron2D.Client.Game

  alias Beast.{Art, Game, Scenery, Terrain}

  @camera_lift 5

  @impl true
  def title, do: %{name: "BEAST", tagline: "a run under five skies"}

  @impl true
  def atlas, do: Art.install()

  @impl true
  def actions, do: [:left, :right, :jump]

  @impl true
  def keymaps do
    [
      arrows: %{left: [:left], right: [:right], jump: [:" "]},
      wasd: %{left: [:a], right: [:d], jump: [:" "]}
    ]
  end

  @impl true
  def toggles, do: []

  @impl true
  def holds, do: [{:left, 120}, {:right, 120}, {:jump, 120}]

  @impl true
  def start, do: {:play, :plain}

  @impl true
  def look, do: %{projection: :top, projections: [:top], zoom: 2}

  @impl true
  def chat?, do: false

  @impl true
  def lobby?, do: false

  @impl true
  def worlds(_props) do
    [%{id: :plain, name: "The red plain", world: {Game, [hz: 50]}, players: 0, humans: []}]
  end

  @impl true
  def scene(%{me: nil}) do
    %{
      focus: {12.0, Terrain.surface() - @camera_lift},
      bounds: :unbounded,
      cell: &Terrain.cell/1,
      movers: [],
      layers: Scenery.layers()
    }
  end

  def scene(%{me: me} = view) do
    %{
      focus: {me.x, Terrain.surface() - @camera_lift},
      bounds: :unbounded,
      cell: &Terrain.cell/1,
      movers: movers(view),
      layers: Scenery.layers(),
      subject: :runner
    }
  end

  @impl true
  def hud(%{me: nil}), do: [["watching"]]

  def hud(%{me: me}) do
    [
      [{"BEAST", {240, 236, 224}}],
      ["lives ", {String.duplicate("♥", me.lives), {224, 64, 64}}],
      ["run   ", {"#{round(me.best)} m", {240, 200, 120}}]
    ]
  end

  @impl true
  def listener(%{me: nil}), do: nil
  def listener(%{me: me}), do: {me.x, me.y}

  @impl true
  def sounds, do: fn _event -> nil end

  @impl true
  def music, do: []

  @impl true
  def cue(_view, _screen), do: nil

  defp movers(view) do
    Enum.map(view.crawlers, &{:crawler, {&1.x, Terrain.floor_at(&1.x) - 1.0}}) ++
      Enum.map(view.bats, &{:bat, {&1.x, &1.y}}) ++
      Enum.map(view.others, &figure/1) ++
      [figure(view.me)]
  end

  defp figure(runner) do
    art = if runner.running?, do: Art.step(runner.stride), else: :stander
    {art, {runner.x, runner.y}, facing(runner.facing)}
  end

  defp facing(1), do: 0.0
  defp facing(_left), do: :math.pi()
end
