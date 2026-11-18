defmodule NowInAndroidServer.Application do
  @moduledoc """
  The news server Now in Android syncs from: the feed (`NowInAndroidServer.Feed`) and its
  HTTP API (`NowInAndroidServer.Router`) on `:port` (`PORT`, default 4180).

      mix run --no-halt
  """

  use Application

  @impl Application
  def start(_type, _args) do
    config = Application.get_all_env(:now_in_android_server)

    children = [
      {NowInAndroidServer.Feed, data: config[:data], publish_every: config[:publish_every]},
      {Bandit, plug: NowInAndroidServer.Router, port: config[:port]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: NowInAndroidServer.Supervisor)
  end
end
