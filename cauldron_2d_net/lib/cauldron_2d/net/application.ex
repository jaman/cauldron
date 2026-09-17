defmodule Cauldron2D.Net.Application do
  @moduledoc false

  use Application

  alias Cauldron2D.Net.{Audio, Link, Remote}

  @impl true
  def start(_type, _args) do
    Supervisor.start_link(
      [Remote.Worlds, Link.World] ++ Audio.child_specs(),
      strategy: :one_for_one,
      name: Cauldron2D.Net.Supervisor
    )
  end
end
