defmodule Cauldron2D.Net.ApiTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Plug.Test

  alias Cauldron2D.{Ledger, Worlds}
  alias Cauldron2D.Net.Api

  defmodule Race do
    @moduledoc false
    @behaviour Cauldron2D.Game
    def init(_opts), do: %{}
    def join(state, _id, _props), do: {:ok, state}
    def leave(state, _id), do: state
    def handle_input(state, _id, _input), do: state
    def step(state, _dt), do: state
    def view(_state, _id), do: nil
    def drain_events(state), do: {[], state}
  end

  defp login("alice", "secret"), do: {:ok, "alice"}
  defp login(_name, _password), do: :error
  defp register("taken", _password), do: {:error, :taken}
  defp register(name, _password), do: {:ok, name}

  defp opts(extra \\ []),
    do: Api.init([login: &login/2, register: &register/2, token: &("tok-" <> &1)] ++ extra)

  defp post_json(path, body, extra \\ []) do
    :post
    |> conn(path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> Api.call(opts(extra))
  end

  test "a token for a name and password, registration, and the refusals" do
    assert %{status: 200, resp_body: body} =
             post_json("/token", %{username: "alice", password: "secret"})

    assert Jason.decode!(body) == %{"token" => "tok-alice", "username" => "alice"}
    assert %{status: 401} = post_json("/token", %{username: "alice", password: "wrong"})
    assert %{status: 200} = post_json("/token", %{username: "bob", password: "x", register: true})

    assert %{status: 422, resp_body: taken} =
             post_json("/token", %{username: "taken", password: "x", register: true})

    assert Jason.decode!(taken) == %{"error" => "taken"}
    assert %{status: 400} = post_json("/token", %{})
  end

  test "the worlds and the stats, as a remote lobby reads them" do
    :ok =
      Worlds.register(:api_pit,
        game: Race,
        name: "The Pit",
        kind: {"race", {0, 200, 0}},
        teams: [1, 2]
      )

    on_exit(fn -> Worlds.close(:api_pit) end)

    assert [
             %{
               "id" => "api_pit",
               "name" => "The Pit",
               "kind" => %{"text" => "race", "colour" => "#00c800"},
               "teams" => [1, 2],
               "players" => 0
             }
           ] =
             :get
             |> conn("/worlds")
             |> Api.call(opts())
             |> Map.get(:resp_body)
             |> Jason.decode!()
             |> Enum.filter(&(&1["id"] == "api_pit"))

    assert %{"worlds" => _, "node" => %{"processes" => _}} =
             :get |> conn("/stats") |> Api.call(opts()) |> Map.get(:resp_body) |> Jason.decode!()
  end

  test "the boards when there is a ledger, and 404 when there is none" do
    path =
      Path.join(
        System.tmp_dir!(),
        "cauldron_api_ledger_#{System.unique_integer([:positive])}.dets"
      )

    {:ok, ledger} =
      Ledger.start_link(
        path: path,
        name: nil,
        metrics: [kills: {:sum, :kills}, wins: {:count, :won?}]
      )

    :ok = Ledger.record(ledger, "Pit", %{id: "a1", name: "alice", kills: 4, won?: true})
    conn = :get |> conn("/leaders?period=all&metric=kills") |> Api.call(opts(ledger: ledger))

    assert [
             %{
               "account" => "a1",
               "name" => "alice",
               "value" => 4,
               "values" => %{"kills" => 4, "wins" => 1}
             }
           ] = Jason.decode!(conn.resp_body)

    assert %{status: 404} = :get |> conn("/leaders") |> Api.call(opts())
    GenServer.stop(ledger)
    File.rm(path)
  end
end
