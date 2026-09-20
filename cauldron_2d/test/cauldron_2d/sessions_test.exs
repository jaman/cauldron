defmodule Cauldron2D.SessionsTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Sessions

  setup do
    Sessions.subscribe()
    on_exit(fn -> Sessions.unsubscribe() end)
    :ok
  end

  defp session(id, kind) do
    parent = self()

    pid =
      spawn(fn ->
        :ok = Sessions.track(id, kind)
        send(parent, :tracked)

        loop = fn loop ->
          receive do
            :stop ->
              :ok

            {:track, id, kind} ->
              :ok = Sessions.track(id, kind)
              loop.(loop)
          end
        end

        loop.(loop)
      end)

    assert_receive :tracked
    pid
  end

  test "a session is listed from track until its process exits, and watchers hear both" do
    pid = session("alice", :terminal)
    assert_receive {:cauldron_sessions, :opened, %{id: "alice", kind: :terminal, pid: ^pid}}
    assert [%{id: "alice", kind: :terminal, pid: ^pid, since: since}] = of("alice")
    assert is_integer(since)

    send(pid, :stop)
    assert_receive {:cauldron_sessions, :closed, %{id: "alice", kind: :terminal, pid: ^pid}}
    assert of("alice") == []
  end

  test "one id can hold several sessions of different kinds, oldest first" do
    first = session("bob", :terminal)
    second = session("bob", :web)
    assert [%{pid: ^first, kind: :terminal}, %{pid: ^second, kind: :web}] = of("bob")
    send(first, :stop)
    assert_receive {:cauldron_sessions, :closed, %{pid: ^first}}
    assert [%{pid: ^second}] = of("bob")
    send(second, :stop)
    assert_receive {:cauldron_sessions, :closed, %{pid: ^second}}
  end

  test "tracking again from the same process replaces its session" do
    pid = session("cal", :terminal)
    assert_receive {:cauldron_sessions, :opened, %{pid: ^pid}}
    send(pid, {:track, "cal", :touch})
    assert_receive {:cauldron_sessions, :opened, %{pid: ^pid, kind: :touch}}
    assert [%{kind: :touch}] = of("cal")
    send(pid, :stop)
    assert_receive {:cauldron_sessions, :closed, %{pid: ^pid}}
  end

  defp of(id), do: Enum.filter(Sessions.list(), &(&1.id == id))
end
