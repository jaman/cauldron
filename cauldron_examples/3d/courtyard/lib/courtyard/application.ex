defmodule Courtyard.Application do
  @moduledoc "Starts the scene loader (`Courtyard.Loader`) and the tasks it uploads in."

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: Courtyard.Tasks},
      Courtyard.Loader
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Courtyard.Supervisor)
  end
end
