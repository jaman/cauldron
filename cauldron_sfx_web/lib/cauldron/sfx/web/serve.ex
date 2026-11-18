defmodule Cauldron.SFX.Web.Serve do
  @moduledoc """
  Starts the editor as a small web application: a PubSub, and an endpoint on a port.
  """

  @doc """
  Start the editor, answering `{:ok, pid}`.

  ## Options

    * `:port` — the port to listen on, default 4040
    * `:bank` — the bank file to open, a path; the starter bank when not given
    * `:out` — where the editor writes, default `"sfx.json"`
  """
  @spec serve(keyword()) :: {:ok, pid()} | {:error, term()}
  def serve(opts \\ []) do
    port = Keyword.get(opts, :port, 4040)

    if path = Keyword.get(opts, :bank), do: Application.put_env(:cauldron_sfx_web, :bank, path)
    Application.put_env(:cauldron_sfx_web, :out, Keyword.get(opts, :out, "sfx.json"))

    Application.put_env(:cauldron_sfx_web, Cauldron.SFX.Web.Endpoint,
      http: [port: port],
      server: true,
      adapter: Bandit.PhoenixAdapter,
      secret_key_base: secret(),
      live_view: [signing_salt: "cauldron-sfx"],
      pubsub_server: Cauldron.SFX.Web.PubSub,
      render_errors: [formats: [html: Cauldron.SFX.Web.ErrorHTML], layout: false]
    )

    children = [
      {Phoenix.PubSub, name: Cauldron.SFX.Web.PubSub},
      Cauldron.SFX.Web.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  defp secret, do: Base.encode64(:crypto.strong_rand_bytes(48))
end
