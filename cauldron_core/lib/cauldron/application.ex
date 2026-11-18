defmodule Cauldron.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        Cauldron.Audio.Rendered,
        Cauldron.World.Presence,
        Cauldron.Sessions,
        Cauldron.World.Events,
        Cauldron.Chat
      ] ++
        Cauldron.Worlds.child_specs() ++
        [{Cauldron.Worlds.Sweeper, Application.get_env(:cauldron_core, :sweeper, [])}]

    Supervisor.start_link(children, strategy: :one_for_one, name: Cauldron.Supervisor)
  end
end
