defmodule Megablast.ClientTest do
  @moduledoc """
  The demo through a headless terminal: which screen it opens on, whether the layers reach
  the pane, and where leaving the world goes.
  """

  use ExUnit.Case, async: false

  alias Cauldron2D.Drafter.Client
  alias Drafter.Test, as: DT

  setup do
    Megablast.Art.install()
    Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
    Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)

    dir = Path.join(System.tmp_dir!(), "megablast_client_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    previous = System.get_env("XDG_CONFIG_HOME")
    System.put_env("XDG_CONFIG_HOME", dir)

    ctx =
      DT.start_headless(
        Client,
        %{
          game: Megablast.Client,
          username: "pilot",
          sink: TuningFork.Sink.Silent,
          settings: %{display: :octant, pointer: false}
        },
        size: {80, 24}
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

  test "it opens in the world, with no lobby and no title", %{ctx: ctx} do
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "shield" end)

    text = DT.screen_text(ctx)

    refute text =~ "Worlds"
    refute text =~ "The chitin lane"
    refute text =~ "down the chitin lane"
    assert DT.get_state(ctx).screen == :play
  end

  test "the parallax layers reach the pane rather than leaving it blank", %{ctx: ctx} do
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "shield" end)
    assert :ok == DT.wait_for(ctx, fn c -> painted(c) > 400 end)
  end

  test "leaving the world stops the client rather than showing a lobby", %{ctx: ctx} do
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "shield" end)

    DT.send_key(ctx, :escape)

    assert :ok == DT.wait_for(ctx, fn c -> not Process.alive?(c.app_pid) end)
  end

  defp painted(ctx) do
    ctx
    |> DT.screen_text()
    |> String.graphemes()
    |> Enum.count(&(&1 not in [" ", "\n"]))
  end
end
