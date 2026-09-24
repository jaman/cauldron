defmodule Cauldron2D.Drafter.SoloClientTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias Cauldron2D.Drafter.Client
  alias Cauldron2D.TestGames.Dots
  alias Drafter.Test, as: DT
  alias FrenchCurve.Raster

  defmodule SoloClient do
    @moduledoc false
    @behaviour Cauldron2D.Client.Game

    def title, do: %{name: "SOLO", tagline: "one player, own world"}
    def atlas, do: :solo_dots
    def actions, do: [:left, :right]
    def keymaps, do: [arrows: %{left: [:left], right: [:right]}]
    def toggles, do: []
    def lobby?, do: false
    def chat?, do: false

    def worlds(_props),
      do: [%{id: :solo, name: "Solo", world: {Dots, [hz: 50]}, players: 0, map: "flat"}]

    def scene(view),
      do: %{
        focus: view.me.pos,
        bounds: {view.width, view.height},
        cell: fn _ -> {:floor, [], nil} end,
        movers: view.movers,
        labels: [{"me", view.me.pos, {255, 255, 0}}]
      }

    def hud(view), do: [["x=#{elem(view.me.pos, 0) |> Float.round(1)}"]]
    def listener(view), do: view.me.pos
    def sounds, do: fn _ -> nil end
    def music, do: []
    def cue(_view, _screen), do: nil
  end

  setup do
    Atlas.new(:solo_dots, tile: 8)
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

    dir = Path.join(System.tmp_dir!(), "solo_client_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    previous = System.get_env("XDG_CONFIG_HOME")
    System.put_env("XDG_CONFIG_HOME", dir)
    trace = Path.join(dir, "trace.log")
    System.put_env("CAULDRON_TRACE", trace)

    ctx =
      DT.start_headless(
        Client,
        %{
          game: SoloClient,
          username: "solo",
          sink: TuningFork.Sink.Silent,
          settings: %{display: :glyphs, pointer: false}
        },
        size: {60, 20}
      )

    on_exit(fn ->
      DT.stop(ctx)
      Cauldron2D.Trace.stop()
      System.delete_env("CAULDRON_TRACE")
      File.rm_rf!(dir)

      if previous,
        do: System.put_env("XDG_CONFIG_HOME", previous),
        else: System.delete_env("XDG_CONFIG_HOME")
    end)

    {:ok, ctx: ctx, trace: trace}
  end

  test "with CAULDRON_TRACE set, the keys pressed in the world, the inputs sent and the frames received are traced",
       %{ctx: ctx, trace: trace} do
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "x=" end)
    DT.send_key(ctx, :right)
    assert :ok == DT.wait_for(ctx, fn c -> DT.get_state(c).last_input.held != MapSet.new() end)
    DT.send_key(ctx, :escape)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "one player, own world" end)
    DT.stop(ctx)
    Cauldron2D.Trace.stop()

    kinds = trace |> Cauldron2D.Trace.read!() |> Enum.map(& &1["kind"])
    assert "frame" in kinds
    assert "input" in kinds

    assert Enum.any?(
             Cauldron2D.Trace.read!(trace),
             &(&1["kind"] == "key" and &1["key"] == "right")
           )
  end

  test "enter on the title starts the player's own world and plays; p pauses it; escape stops it and returns to the title",
       %{ctx: ctx} do
    assert DT.screen_text(ctx) =~ "one player, own world"
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "x=" end)
    refute DT.screen_text(ctx) =~ "Worlds"
    assert DT.screen_text(ctx) =~ "me"
    worlds_before = length(Process.list())

    DT.send_key(ctx, :p)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "paused" end)
    DT.send_key(ctx, :p)
    assert :ok == DT.wait_for(ctx, fn c -> not (DT.screen_text(c) =~ "paused") end)

    DT.send_key(ctx, :escape)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "one player, own world" end)
    assert length(Process.list()) < worlds_before
  end
end
