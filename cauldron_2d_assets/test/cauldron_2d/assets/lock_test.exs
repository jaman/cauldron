defmodule Cauldron2D.Assets.LockTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Assets.Lock

  setup do
    path = Path.join(System.tmp_dir!(), "lock_#{System.unique_integer([:positive])}.exs")
    on_exit(fn -> File.rm(path) end)
    {:ok, path: path}
  end

  test "a lock written and read back is the same term", %{path: path} do
    lock = %{
      jar: %{
        digest: 1234,
        candidates: [%{id: "a", path: "priv/art/jar.png", url: nil, seed: -7}],
        pick: 0
      }
    }

    assert :ok = Lock.write(path, lock)
    assert Lock.read(path) == lock
  end

  test "a missing lock is empty", %{path: path} do
    assert Lock.read(path) == %{}
  end

  test "a lock that holds code is refused, not run", %{path: path} do
    File.write!(path, "%{jar: File.rm_rf!(System.tmp_dir!())}")

    assert_raise ArgumentError, ~r/not an asset lock/, fn -> Lock.read(path) end
  end

  test "a call hidden in a value is refused", %{path: path} do
    File.write!(path, "%{jar: %{digest: System.cmd(\"rm\", [\"-rf\", \"/\"])}}")

    assert_raise ArgumentError, ~r/not an asset lock/, fn -> Lock.read(path) end
  end
end
