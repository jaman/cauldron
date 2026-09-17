defmodule Cauldron2D.Easel.Web.TestRouter do
  @moduledoc false
  use Phoenix.Router
  import Phoenix.LiveView.Router
  import Cauldron2D.Easel.Web.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:protect_from_forgery)
  end

  scope "/" do
    pipe_through(:browser)

    easel("/easel",
      dir: Path.join(System.tmp_dir!(), "easel_web_test"),
      tile: 4,
      atlas: :easel_web_test
    )
  end
end

defmodule Cauldron2D.Easel.Web.TestEndpoint do
  @moduledoc false
  use Phoenix.Endpoint, otp_app: :cauldron_2d_easel_web

  @session_options [store: :cookie, key: "_easel_test", signing_salt: "easel-test-salt"]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])
  plug(Plug.Session, @session_options)
  plug(Cauldron2D.Easel.Web.TestRouter)
end
