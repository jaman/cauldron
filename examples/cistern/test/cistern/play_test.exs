defmodule Cistern.PlayTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Drafter.Client
  alias Drafter.Test, as: DT

  setup do
    Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
    Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)
    dir = Path.join(System.tmp_dir!(), "cistern_play_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    previous = System.get_env("XDG_CONFIG_HOME")
    System.put_env("XDG_CONFIG_HOME", dir)

    ctx =
      DT.start_headless(
        Client,
        %{
          game: Cistern.Client,
          username: "tester",
          sink: TuningFork.Sink.Silent,
          settings: %{display: :glyphs, pointer: false, music: 0.0}
        },
        size: {80, 30}
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

  test "the terminal client runs the game: title, lobby, the field with its hud, and back", %{
    ctx: ctx
  } do
    assert DT.screen_text(ctx) =~ "catch the rain"
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "cistern" end)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "caught 0" end)
    DT.send_key(ctx, :escape)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "cistern" end)
  end
end
