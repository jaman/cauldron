defmodule Cauldron2D.Drafter.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link(
      [{DynamicSupervisor, strategy: :one_for_one, name: Cauldron2D.Drafter.Server.Supervisor}],
      strategy: :one_for_one,
      name: Cauldron2D.Drafter.Supervisor
    )
  end
end
