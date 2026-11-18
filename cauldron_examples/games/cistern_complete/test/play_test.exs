defmodule CisternComplete.PlayTest do
  use ExUnit.Case, async: false

  alias Cauldron.Audio.Sink
  alias Cauldron2D.Drafter.Test, as: DT

  setup do
    dir = Path.join(System.tmp_dir!(), "cistern_complete_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    previous = {System.get_env("XDG_CONFIG_HOME"), System.get_env("XDG_DATA_HOME")}
    System.put_env("XDG_CONFIG_HOME", dir)
    System.put_env("XDG_DATA_HOME", dir)
    CisternComplete.Worlds.register()

    ctx =
      DT.start(
        %{
          game: CisternComplete.Client,
          username: "tester",
          sink: Sink.silent(),
          settings: %{display: :glyphs, pointer: false, music: 0.0}
        },
        size: {120, 40}
      )

    on_exit(fn ->
      DT.stop(ctx)
      File.rm_rf!(dir)
      restore("XDG_CONFIG_HOME", elem(previous, 0))
      restore("XDG_DATA_HOME", elem(previous, 1))
    end)

    {:ok, ctx: ctx}
  end

  defp restore(name, nil), do: System.delete_env(name)
  defp restore(name, value), do: System.put_env(name, value)

  defp shows(ctx, words), do: DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ words end)

  test "the game's own title opens a storm, Escape pauses it, and the pause menu leaves for the title",
       %{ctx: ctx} do
    assert :ok == shows(ctx, "VERSUS THE ROBOT")
    DT.send_key(ctx, :enter)
    assert :ok == shows(ctx, "STORM 1")
    DT.send_key(ctx, :escape)
    assert :ok == shows(ctx, "PAUSED")
    DT.send_key(ctx, :up)
    DT.send_key(ctx, :enter)
    assert :ok == shows(ctx, "LEAVE THIS STORM")
    DT.send_key(ctx, :y)
    assert :ok == shows(ctx, "VERSUS THE ROBOT")
  end
end
