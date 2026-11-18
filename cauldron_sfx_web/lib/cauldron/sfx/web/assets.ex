defmodule Cauldron.SFX.Web.Assets do
  @moduledoc """
  Serves the editor's script and stylesheet, and the Phoenix and LiveView ones they need.
  """

  @behaviour Plug

  import Plug.Conn

  @files %{
    "sfx.js" => {:cauldron_sfx_web, "priv/static/sfx.js", "application/javascript"},
    "sfx.css" => {:cauldron_sfx_web, "priv/static/sfx.css", "text/css"},
    "phoenix.min.js" => {:phoenix, "priv/static/phoenix.min.js", "application/javascript"},
    "phoenix_live_view.min.js" =>
      {:phoenix_live_view, "priv/static/phoenix_live_view.min.js", "application/javascript"}
  }

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%{path_params: %{"file" => file}} = conn, _opts) do
    case Map.get(@files, file) do
      nil ->
        send_resp(conn, 404, "not found")

      {app, path, type} ->
        conn
        |> put_resp_content_type(type)
        |> send_resp(200, File.read!(Application.app_dir(app, path)))
    end
  end

  @doc "The files served, by name."
  @spec files() :: [String.t()]
  def files, do: Map.keys(@files)
end
