defmodule Cauldron2D.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [Cauldron2D.Atlas, Cauldron2D.Atlas.Tables]
    Supervisor.start_link(children, strategy: :one_for_one, name: Cauldron2D.Supervisor)
  end
end
