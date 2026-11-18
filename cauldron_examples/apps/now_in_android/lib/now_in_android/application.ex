defmodule NowInAndroid.Application do
  @moduledoc "Starts the user's data, the news, the sync's tasks, then the app's screens (`NowInAndroid.App`)."

  use Application

  @impl Application
  def start(_type, _args),
    do:
      Supervisor.start_link(
        [
          NowInAndroid.Store,
          NowInAndroid.News,
          {Task.Supervisor, name: NowInAndroid.Tasks},
          NowInAndroid.App
        ],
        strategy: :one_for_one,
        name: NowInAndroid.Supervisor
      )
end
