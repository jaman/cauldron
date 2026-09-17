defmodule Cauldron2D.TraceTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Trace

  setup do
    path =
      Path.join(System.tmp_dir!(), "cauldron_trace_#{System.unique_integer([:positive])}.log")

    previous = System.get_env("CAULDRON_TRACE")
    System.put_env("CAULDRON_TRACE", path)

    on_exit(fn ->
      Trace.stop()

      if previous,
        do: System.put_env("CAULDRON_TRACE", previous),
        else: System.delete_env("CAULDRON_TRACE")

      File.rm(path)
    end)

    {:ok, path: path}
  end

  test "events are lines of key=value with a time, read back and summarised", %{path: path} do
    assert Trace.start()
    assert Trace.on?()
    Trace.write(:mouse, x: 3, tile: 1.256)
    Trace.write(:mouse, x: 5)
    Trace.write(:key, key: :left)
    Trace.stop()
    refute Trace.on?()

    events = Trace.read!(path)

    assert [
             %{"kind" => "start"},
             %{"kind" => "mouse", "x" => "3", "tile" => "1.26"},
             %{"kind" => "mouse", "x" => "5"},
             %{"kind" => "key", "key" => "left"},
             %{"kind" => "stop"}
           ] = events

    assert Enum.all?(events, &is_float(Trace.at(&1)))

    summary = Trace.summary(events)
    assert summary.counts["mouse"] == 2
    assert %{median: _, p90: _, max: _, count: 1} = summary.gaps["mouse"]
    assert %{count: 1} = Trace.latency(events, "mouse", "key")
  end

  test "without the variable nothing is written" do
    System.delete_env("CAULDRON_TRACE")
    refute Trace.start()
    assert :ok = Trace.write(:mouse, x: 1)
  end
end

defmodule Cauldron2D.TraceOwnerTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Trace

  test "a trace whose opener has exited is closed with it: later writes and stop are no-ops and the lines written stay" do
    path =
      Path.join(
        System.tmp_dir!(),
        "cauldron_trace_owner_#{System.unique_integer([:positive])}.log"
      )

    System.put_env("CAULDRON_TRACE", path)

    on_exit(fn ->
      System.delete_env("CAULDRON_TRACE")
      File.rm(path)
    end)

    parent = self()

    opener =
      spawn(fn ->
        Trace.start()
        Trace.write(:kept, n: 1)
        send(parent, :written)
        receive do: (:exit -> :ok)
      end)

    assert_receive :written
    send(opener, :exit)
    ref = Process.monitor(opener)
    assert_receive {:DOWN, ^ref, :process, ^opener, _reason}

    assert Trace.write(:dropped) == :ok
    assert Trace.stop() == :ok
    refute Trace.on?()
    assert Enum.map(Trace.read!(path), & &1["kind"]) == ["start", "kept"]
  end
end
