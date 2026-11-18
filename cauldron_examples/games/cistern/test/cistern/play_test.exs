defmodule Cistern.PlayTest do
  use ExUnit.Case, async: false

  alias Cauldron.Audio.Sink
  alias Cauldron2D.Drafter.Test, as: DT

  setup do
    dir = Path.join(System.tmp_dir!(), "cistern_play_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    previous = System.get_env("XDG_CONFIG_HOME")
    System.put_env("XDG_CONFIG_HOME", dir)

    ctx =
      DT.start(
        %{
          game: Cistern.Client,
          username: "tester",
          sink: Sink.silent(),
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
    assert DT.screen_text(ctx) =~ "a storm has come"
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "square" end)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "STORM 1" end)
    DT.send_key(ctx, :escape)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "square" end)
  end
end
