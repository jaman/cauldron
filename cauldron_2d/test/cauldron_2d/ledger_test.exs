defmodule Cauldron2D.LedgerTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Ledger

  defp metrics do
    [
      kills: {:sum, :kills},
      ratio: {:ratio, :kills, :deaths},
      wins: {:count, :won?},
      streak: {:max, :best_streak},
      laps: fn rows -> rows |> Enum.map(& &1.laps) |> Enum.sum() end
    ]
  end

  defp start do
    path =
      Path.join(System.tmp_dir!(), "cauldron_ledger_#{System.unique_integer([:positive])}.dets")

    {:ok, ledger} = Ledger.start_link(path: path, name: nil, metrics: metrics())
    on_exit(fn -> File.rm(path) end)
    ledger
  end

  defp row(id, name, kills, deaths, won?, streak, laps \\ 0) do
    %{
      id: id,
      name: name,
      kills: kills,
      deaths: deaths,
      won?: won?,
      best_streak: streak,
      laps: laps
    }
  end

  test "results are kept and ranked by a metric, an account shown by the name it last used" do
    ledger = start()
    :ok = Ledger.record(ledger, "Pit", row("a1", "alice", 5, 1, true, 3))
    :ok = Ledger.record(ledger, "Pit", row("b1", "bob", 2, 0, false, 2))
    :ok = Ledger.record(ledger, "Ring", row("a1", "Alice!", 1, 4, false, 1, 2))
    assert Ledger.count(ledger) == 3

    assert [
             %{
               account: "a1",
               name: "Alice!",
               value: 6,
               rounds: 2,
               values: %{kills: 6, wins: 1, streak: 3, laps: 2}
             },
             %{account: "b1", value: 2}
           ] = Ledger.board(ledger, :all, :kills)

    assert [%{account: "b1", value: 2.0}, %{account: "a1", value: 1.2}] =
             Ledger.board(ledger, :all, :ratio)

    assert [%{account: "a1", value: 1}, %{account: "b1", value: 0}] =
             Ledger.board(ledger, :all, :wins)

    assert [%{account: "a1", value: 2} | _] = Ledger.board(ledger, :all, :laps)

    assert [%{account: "a1", value: 5}, %{account: "b1", value: 2}] =
             Ledger.board(ledger, :all, :kills, arena: "Pit")
  end

  test "a period leaves out what is older, and a robot's result is dropped" do
    ledger = start()

    :ok =
      Ledger.record(
        ledger,
        "Pit",
        row("a1", "alice", 9, 0, true, 9),
        DateTime.add(DateTime.utc_now(), -10, :day)
      )

    :ok = Ledger.record(ledger, "Pit", row("a1", "alice", 1, 0, false, 1))
    :ok = Ledger.record(ledger, "Pit", row({:robot, 1}, "Robot 1", 50, 0, true, 50))
    assert [%{value: 1}] = Ledger.board(ledger, :week, :kills)
    assert [%{value: 10}] = Ledger.board(ledger, :all, :kills)
    assert Ledger.count(ledger) == 2
  end

  test "results are forgotten by what is true of them, and the boards forget them at once" do
    ledger = start()
    :ok = Ledger.record(ledger, "Pit", row("a1", "alice", 3, 0, true, 3))
    :ok = Ledger.record(ledger, "Pit", row("load_1", "load_1", 9, 0, true, 9))
    :ok = Ledger.record(ledger, "Pit", row("load_2", "load_2", 8, 0, true, 8))

    assert [%{name: "load_1"}, %{name: "load_2"}, %{name: "alice"}] =
             Ledger.board(ledger, :all, :kills)

    assert Ledger.forget(ledger, &String.starts_with?(&1.name, "load_")) == 2
    assert Ledger.count(ledger) == 1
    assert [%{name: "alice"}] = Ledger.board(ledger, :all, :kills)
    assert Ledger.forget(ledger, fn _ -> false end) == 0
  end

  test "a result survives a restart" do
    path =
      Path.join(
        System.tmp_dir!(),
        "cauldron_ledger_restart_#{System.unique_integer([:positive])}.dets"
      )

    {:ok, ledger} = Ledger.start_link(path: path, name: nil, metrics: metrics())
    :ok = Ledger.record(ledger, "Pit", row("a1", "alice", 3, 0, true, 3))
    GenServer.stop(ledger)
    {:ok, again} = Ledger.start_link(path: path, name: nil, metrics: metrics())
    assert Ledger.count(again) == 1
    GenServer.stop(again)
    File.rm(path)
  end
end
