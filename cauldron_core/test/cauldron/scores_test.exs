defmodule Cauldron.ScoresTest do
  use ExUnit.Case, async: false

  alias Cauldron.Scores

  setup do
    dir = Path.join(System.tmp_dir!(), "scores_test_#{System.unique_integer([:positive])}")
    previous = System.get_env("XDG_DATA_HOME")
    System.put_env("XDG_DATA_HOME", dir)

    on_exit(fn ->
      if previous,
        do: System.put_env("XDG_DATA_HOME", previous),
        else: System.delete_env("XDG_DATA_HOME")

      File.rm_rf!(dir)
    end)

    {:ok, dir: dir}
  end

  test "the table keeps the best, in order, and a score must beat the last kept" do
    table = Enum.reduce([300, 100, 200], [], &Scores.add(&2, %{score: &1}, 2))
    assert table == [%{score: 300}, %{score: 200}]
    refute Scores.qualifies?(table, 150, 2)
    assert Scores.qualifies?(table, 250, 2)
    refute Scores.qualifies?([], 0)
  end

  test "a table kept as text is read as data, and nothing in it is run", %{dir: dir} do
    File.mkdir_p!(Path.join(dir, "game"))
    File.write!(Path.join([dir, "game", "scores.exs"]), ~S|[%{initials: "ABC", score: 7}]|)
    assert Scores.read(:game) == [%{initials: "ABC", score: 7}]

    File.write!(Path.join([dir, "game", "scores.exs"]), ~S|[%{score: System.halt()}]|)
    assert Scores.read(:game) == []
  end
end
