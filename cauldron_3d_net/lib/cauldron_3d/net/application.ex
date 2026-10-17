defmodule Cauldron3D.Net.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Cauldron3D.Net.Scenes},
      {Phoenix.PubSub, name: Cauldron3D.Net.PubSub}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Cauldron3D.Net.Supervisor)
  end
end
