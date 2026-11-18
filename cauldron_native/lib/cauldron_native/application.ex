defmodule CauldronNative.Application do
  @moduledoc """
  Inside a native app, loads the certificates TLS trusts (`CauldronNative.Certificates`),
  keeps the resolver on the device's DNS servers
  (`CauldronNative.Network`) and starts the app named by
  `config :cauldron_native, app: MyApp.App` (a `CauldronNative.App`), with
  `config :cauldron_native, params: %{}` given to its `mount/1`. An app started in its
  own supervision tree is not named there. Outside a native app nothing runs.
  """

  use Application

  alias CauldronNative.App.Runtime

  @impl Application
  def start(_type, _args) do
    available? = CauldronNative.available?()
    trusted(available?)

    Supervisor.start_link(children(available?),
      strategy: :one_for_one,
      name: CauldronNative.Supervisor
    )
  end

  defp trusted(false), do: :ok
  defp trusted(true), do: CauldronNative.Certificates.load(CauldronNative.Device.system())

  defp children(false), do: []

  defp children(true),
    do: [CauldronNative.Network | app(Application.get_env(:cauldron_native, :app))]

  defp app(nil), do: []

  defp app(app),
    do: [
      {Runtime,
       app: app, params: Application.get_env(:cauldron_native, :params, %{}), name: Runtime}
    ]
end
