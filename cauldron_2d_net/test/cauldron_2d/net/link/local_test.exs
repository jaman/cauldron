defmodule Cauldron.Net.Link.LocalTest do
  use ExUnit.Case, async: false

  alias Cauldron.Net.Link
  alias Cauldron.World
  alias Cauldron2D.Atlas
  alias FrenchCurve.Raster

  defmodule Dots do
    @moduledoc false
    @behaviour Cauldron.Game

    @impl true
    def init(_opts), do: %{players: %{}, events: []}

    @impl true
    def join(state, id, props),
      do: {:ok, put_in(state.players[id], %{pos: {5.0, 5.0}, held: MapSet.new(), props: props})}

    @impl true
    def leave(state, id), do: %{state | players: Map.delete(state.players, id)}

    @impl true
    def handle_input(state, id, %{held: held, aim: aim}),
      do: update_in(state.players[id], &Map.merge(&1, %{held: held, aim: aim}))

    @impl true
    def step(state, dt) do
      players =
        Map.new(state.players, fn {id, p} ->
          {x, y} = p.pos
          {id, %{p | pos: {x + if(MapSet.member?(p.held, :right), do: 4.0 * dt, else: 0.0), y}}}
        end)

      %{state | players: players}
    end

    @impl true
    def view(state, id),
      do: %{
        me: state.players[id],
        movers: for({_, p} <- state.players, do: {:dot, p.pos}),
        width: 8,
        height: 6
      }

    @impl true
    def drain_events(state), do: {Enum.reverse(state.events), %{state | events: []}}
  end

  defmodule DotsWx do
    @moduledoc false
    use Cauldron2D.Client.Game

    def title, do: %{name: "DOTS"}
    def atlas, do: :dots_wx
    def actions, do: [:left, :right, :fire]
    def keymaps, do: [arrows: %{left: [:left], right: [:right], fire: [:" "]}]
    def toggles, do: []
    def worlds(_props), do: [%{id: :main, name: "Main", world: :dots_wx_world, players: 0}]

    def scene(view),
      do: %{
        focus: view.me.pos,
        bounds: {view.width, view.height},
        cell: fn _ -> :void end,
        movers: view.movers
      }

    def hud(view), do: [[{"x=#{elem(view.me.pos, 0)}", {255, 255, 255}}]]
    def listener(view), do: view.me.pos
    def sounds, do: fn _ -> nil end
    def music, do: []
    def cue(_view, _screen), do: nil
  end

  setup_all do
    Atlas.new(:dots_wx, tile: 4)
    |> Atlas.put(:wall, Raster.new(4, 4, background: {0, 0, 200, 255}))
    |> Atlas.put(:dot, Raster.new(4, 4, background: {250, 250, 250, 255}))
    |> Atlas.install()

    :ok
  end

  test "a local link joins a world on this node, hands over the sheet, statuses and pictures of its pane, takes input and leaves" do
    {:ok, world} = World.start_link(game: Dots, hz: 50, name: :dots_wx_world)

    {:ok, link} =
      Link.Local.start_link(
        game: DotsWx,
        drawer: Cauldron2D.Net.Drawer,
        world: world,
        name: "alice",
        props: %{},
        owner: self(),
        sink: TuningFork.Sink.Silent
      )

    assert_receive {:cauldron_link, :sheet, %{tile: 4, url: _}, <<137, "PNG", _::binary>>}

    assert_receive {:cauldron_link, :drawing, %{world: :server, screen: :server}}

    assert_receive {:cauldron_link, :status, %{focus: {5.0, 5.0}, hud: [[{"x=5.0", "#ffffff"}]]}},
                   500

    refute_receive {:cauldron_link, :picture, _}, 100
    Link.Local.pane(link, {10, 6})
    assert_receive {:cauldron_link, :picture, %Raster{width: 40, height: 24}}, 500

    Link.Local.key(link, :right, [], true)
    Process.sleep(100)
    assert_receive {:cauldron_link, :status, %{focus: {x, 5.0}}} when x > 5.0, 500

    assert "alice" in World.players(world)
    Link.Local.leave(link)
    Process.sleep(50)
    refute "alice" in World.players(world)
    GenServer.stop(world)
  end

  test "a local link starts a world of the player's own from `{module, opts}` and plays in it" do
    {:ok, link} =
      Link.Local.start_link(
        game: DotsWx,
        drawer: Cauldron2D.Net.Drawer,
        world: {Dots, [hz: 50]},
        name: "alice",
        props: %{},
        owner: self(),
        sink: TuningFork.Sink.Silent
      )

    assert_receive {:cauldron_link, :status, %{focus: {5.0, 5.0}}}, 500
    Link.Local.key(link, :right, [], true)
    assert_receive {:cauldron_link, :status, %{focus: {x, 5.0}}} when x > 5.0, 500
    Link.Local.leave(link)
  end
end
