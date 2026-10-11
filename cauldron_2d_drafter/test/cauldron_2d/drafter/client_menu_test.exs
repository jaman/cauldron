defmodule Cauldron2D.Drafter.ClientMenuTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias Cauldron2D.Drafter.Client
  alias Cauldron2D.Drafter.Client.Settings
  alias Cauldron2D.TestGames.Dots
  alias Drafter.Test, as: DT
  alias FrenchCurve.Raster

  defmodule MenuClient do
    @moduledoc false
    @behaviour Cauldron2D.Client.Game

    def title, do: %{name: "MENU", tagline: "a game with its own menu"}
    def atlas, do: :menu_dots
    def actions, do: [:left, :right]
    def keymaps, do: [arrows: %{left: [:left], right: [:right]}]
    def toggles, do: []
    def lobby?, do: false
    def chat?, do: false
    def client_keys, do: %{menu: :m}
    def options, do: %{speed: 1}
    def open_menu(_settings), do: %{opened: true}

    def menu_event(menu, {:key, :right}, settings),
      do: %{
        menu: menu,
        settings: %{settings | options: Map.update!(settings.options, :speed, &(&1 + 1))}
      }

    def menu_event(menu, {:key, :n}, settings),
      do: %{menu: menu, settings: settings, request: :again}

    def menu_event(_menu, {:key, :escape}, settings), do: %{menu: nil, settings: settings}
    def menu_event(menu, _event, settings), do: %{menu: menu, settings: settings}

    def worlds(_props),
      do: [%{id: :solo, name: "Solo", world: {Dots, [hz: 50]}, players: 0, map: "flat"}]

    def scene(view),
      do: %{
        focus: view.me.pos,
        bounds: {view.width, view.height},
        cell: fn _ -> {:floor, [], nil} end,
        movers: view.movers
      }

    def hud(view), do: [["x=#{elem(view.me.pos, 0) |> Float.round(1)}"]]
    def listener(view), do: view.me.pos
    def sounds, do: fn _ -> nil end
    def music, do: []
    def cue(_view, _screen), do: nil
  end

  setup do
    Atlas.new(:menu_dots, tile: 8)
    |> Atlas.put(:floor, Raster.new(8, 8, background: {20, 20, 30, 255}),
      glyph: "· ",
      color: {60, 60, 80}
    )
    |> Atlas.put(:dot, Raster.new(8, 8, background: {250, 250, 250, 255}),
      glyph: "@ ",
      color: {250, 250, 250}
    )
    |> Atlas.install()

    Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
    Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)

    dir = Path.join(System.tmp_dir!(), "client_menu_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    previous = System.get_env("XDG_CONFIG_HOME")
    System.put_env("XDG_CONFIG_HOME", dir)

    ctx =
      DT.start_headless(
        Client,
        %{
          game: MenuClient,
          username: "solo",
          sink: TuningFork.Sink.Silent,
          settings: %{display: :glyphs, pointer: false}
        },
        size: {60, 20}
      )

    on_exit(fn ->
      DT.stop(ctx)
      File.rm_rf!(dir)

      if previous,
        do: System.put_env("XDG_CONFIG_HOME", previous),
        else: System.delete_env("XDG_CONFIG_HOME")
    end)

    {:ok, ctx: ctx}
  end

  test "the game's menu takes the keys while open, pauses the player's own world, and its settings and requests reach the world",
       %{ctx: ctx} do
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "x=" end)
    world = DT.get_state(ctx).local_world

    DT.send_key(ctx, :m)
    assert DT.get_state(ctx).menu == %{opened: true}
    assert Cauldron2D.World.paused?(world)

    Process.sleep(350)

    assert DT.get_state(ctx).menu_frame >= 2,
           "the menu was not drawn again while the world stood still"

    DT.send_key(ctx, :right)
    state = DT.get_state(ctx)
    assert state.settings.options.speed == 2
    assert state.last_input.held == MapSet.new(), "the menu's key reached the world"
    assert state.last_input.options == %{speed: 2}
    assert Settings.load(MenuClient, "solo").options.speed == 2

    DT.send_key(ctx, :n)
    DT.send_key(ctx, :n)
    assert DT.get_state(ctx).last_input.request == {2, :again}

    DT.send_key(ctx, :escape)
    assert DT.get_state(ctx).menu == nil
    frames = DT.get_state(ctx).menu_frame
    Process.sleep(250)
    assert DT.get_state(ctx).menu_frame == frames
    refute Cauldron2D.World.paused?(world)
    assert DT.get_state(ctx).screen == :play
  end
end
