defmodule Cauldron2D.Easel.Web.Assets do
  @moduledoc """
  Serves the editor's scripts and stylesheet: `easel.js` and `easel.css` from this
  package, `phoenix.min.js` and `phoenix_live_view.min.js` from theirs.
  """

  @behaviour Plug

  import Plug.Conn

  @files %{
    "easel.js" => {:cauldron_2d_easel_web, "priv/static/easel.js", "application/javascript"},
    "easel.css" => {:cauldron_2d_easel_web, "priv/static/easel.css", "text/css"},
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
