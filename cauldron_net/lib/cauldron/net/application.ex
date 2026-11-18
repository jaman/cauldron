defmodule Cauldron.Net.Application do
  @moduledoc false

  use Application

  alias Cauldron.Net.{Audio, Link, Remote, Voice}

  @impl true
  def start(_type, _args) do
    Supervisor.start_link(
      [Remote.Worlds, Link.World, Voice.Calls] ++ Audio.child_specs(),
      strategy: :one_for_one,
      name: Cauldron.Net.Supervisor
    )
  end
end
