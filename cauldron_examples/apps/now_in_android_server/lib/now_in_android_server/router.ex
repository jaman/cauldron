defmodule NowInAndroidServer.Router do
  @moduledoc """
  The news server's HTTP API, which `NowInAndroid.Sync` reads: `GET /news`, the
  published resources newest first, and `GET /topics`, both as the sample's JSON.
  """

  use Plug.Router

  alias NowInAndroidServer.Feed

  plug(:match)
  plug(:dispatch)

  get "/news" do
    json(conn, Feed.published())
  end

  get "/topics" do
    json(conn, Feed.topics())
  end

  match _ do
    send_resp(conn, 404, "")
  end

  defp json(conn, value) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, JSON.encode!(value))
  end
end
