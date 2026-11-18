defmodule Cauldron2D.Native.Application do
  @moduledoc """
  Starts `Cauldron2D.Native.Client` for the game `config :cauldron_2d_native, game:`
  names, with the rest of that config as its options, when the BEAM runs inside a
  mobile app (`CauldronNative.available?/0`); otherwise starts nothing.

      config :cauldron_2d_native, game: MyGame.Client, point_size: 0.6
  """

  use Application

  @impl Application
  def start(_type, _args) do
    config = Application.get_all_env(:cauldron_2d_native)

    children =
      if CauldronNative.available?() and Keyword.has_key?(config, :game),
        do: [{Cauldron2D.Native.Client, config}],
        else: []

    Supervisor.start_link(children, strategy: :one_for_one, name: Cauldron2D.Native.Supervisor)
  end
end
