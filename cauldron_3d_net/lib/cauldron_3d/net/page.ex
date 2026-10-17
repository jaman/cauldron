defmodule Cauldron3D.Net.Page do
  @moduledoc """
  A plug serving a page that shows one scene, filling the browser window, with the scripts
  it loads: `GET /` the page, `GET /cauldron3d.js` the client, `GET /phoenix.min.js`
  Phoenix's socket client. three.js comes from jsDelivr (version `three_version/0`).

      forward "/watch", to: Cauldron3D.Net.Page, init_opts: [scene: "courtyard", socket: "/scene_socket"]

  Options: `:scene` (required, the scene id), `:socket` (the socket path, default
  `"/socket"`), `:topic` (default `"scene"`), `:title`.
  """

  @behaviour Plug

  import Plug.Conn

  @three "0.170.0"

  @doc "The three.js version the page loads."
  @spec three_version() :: String.t()
  def three_version, do: @three

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_info: ["cauldron3d.js"]} = conn, _opts),
    do: script(conn, Application.app_dir(:cauldron_3d_net, "priv/static/cauldron3d.js"))

  def call(%Plug.Conn{path_info: ["phoenix.min.js"]} = conn, _opts),
    do: script(conn, Application.app_dir(:phoenix, "priv/static/phoenix.min.js"))

  def call(%Plug.Conn{path_info: []} = conn, opts) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, page(conn, opts))
  end

  def call(%Plug.Conn{path_info: ["favicon.ico"]} = conn, _opts), do: send_resp(conn, 204, "")
  def call(conn, _opts), do: send_resp(conn, 404, "")

  defp script(conn, path) do
    conn
    |> put_resp_content_type("text/javascript")
    |> send_resp(200, File.read!(path))
  end

  defp page(conn, opts) do
    base = Enum.map_join(conn.script_name, &("/" <> &1))

    settings =
      Jason.encode!(%{
        scene: Keyword.fetch!(opts, :scene),
        socket: Keyword.get(opts, :socket, "/socket"),
        topic: Keyword.get(opts, :topic, "scene")
      })

    """
    <!doctype html>
    <html>
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>#{Plug.HTML.html_escape(Keyword.get(opts, :title, "cauldron"))}</title>
    <style>html, body { margin: 0; height: 100%; background: #000; overflow: hidden; } canvas { display: block; width: 100%; height: 100%; }</style>
    <script type="importmap">{"imports": {"three": "https://cdn.jsdelivr.net/npm/three@#{@three}/build/three.module.js", "three/addons/": "https://cdn.jsdelivr.net/npm/three@#{@three}/examples/jsm/"}}</script>
    <script src="#{base}/phoenix.min.js"></script>
    </head>
    <body>
    <canvas id="cauldron3d" tabindex="0"></canvas>
    <script type="module">
    import { start } from "#{base}/cauldron3d.js";
    start(document.getElementById("cauldron3d"), #{settings});
    </script>
    </body>
    </html>
    """
  end
end
