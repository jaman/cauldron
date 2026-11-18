defmodule FoodTruck.Application do
  @moduledoc "Starts the truck's data (`FoodTruck.Store`), then its screens (`FoodTruck.App`)."

  use Application

  @impl Application
  def start(_type, _args),
    do:
      Supervisor.start_link([FoodTruck.Store, FoodTruck.App],
        strategy: :one_for_one,
        name: FoodTruck.Supervisor
      )
end
