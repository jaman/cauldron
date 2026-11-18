defmodule Town.ClientTest do
  use ExUnit.Case, async: false

  alias Cauldron.Audio.Sink
  alias Cauldron2D.Drafter.Test, as: DT

  test "the town comes up in the world and can be walked and looked at from every projection" do
    dir = Path.join(System.tmp_dir!(), "town_client_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    previous = System.get_env("XDG_CONFIG_HOME")
    System.put_env("XDG_CONFIG_HOME", Path.join(dir, "config"))

    ctx =
      DT.start(
        %{
          game: Town.Client,
          username: "alice",
          sink: Sink.silent(),
          settings: %{display: :octant, pointer: true}
        },
        size: {120, 40}
      )

    on_exit(fn ->
      DT.stop(ctx)
      File.rm_rf!(dir)

      if previous,
        do: System.put_env("XDG_CONFIG_HOME", previous),
        else: System.delete_env("XDG_CONFIG_HOME")
    end)

    assert :ok == DT.wait_for(ctx, fn c -> DT.get_state(c).screen == :play end, timeout: 2_000)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "alice" end, timeout: 3_000)
    assert DT.get_state(ctx).look.projection == :iso
    assert DT.screen_text(ctx) =~ "isometric"

    DT.send_key(ctx, :w)
    Process.sleep(200)

    assert :ok ==
             DT.wait_for(ctx, fn c -> DT.get_state(c).view.me.mover.y < 21.5 end, timeout: 2_000)

    DT.send_key(ctx, :e)
    DT.sync(ctx)
    assert DT.get_state(ctx).look.facing == 1

    for projection <- [:first_person, :iso] do
      DT.send_key(ctx, :tab)
      assert :ok == DT.wait_for(ctx, fn c -> DT.get_state(c).look.projection == projection end)
      Process.sleep(150)
      assert String.length(DT.screen_text(ctx)) > 0
    end

    DT.send_key(ctx, :t)
    DT.sync(ctx)
    assert DT.get_state(ctx).settings.display == :auto

    DT.send_key(ctx, :escape)
    DT.sync(ctx)
    assert DT.get_state(ctx).screen == :play
  end
end
