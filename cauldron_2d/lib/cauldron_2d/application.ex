defmodule Cauldron2D.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        Cauldron2D.Atlas,
        Cauldron2D.Atlas.Tables,
        Cauldron2D.Audio.Rendered,
        Cauldron2D.World.Presence,
        Cauldron2D.World.Events
      ] ++
        Cauldron2D.Arenas.child_specs() ++
        [{Cauldron2D.Arenas.Sweeper, Application.get_env(:cauldron_2d, :sweeper, [])}]

    Supervisor.start_link(children, strategy: :one_for_one, name: Cauldron2D.Supervisor)
  end
end
