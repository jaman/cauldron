defmodule Cauldron.SFX.Web.TestEndpoint do
  @moduledoc false
  use Phoenix.Endpoint, otp_app: :cauldron_sfx_web

  @session_options [store: :cookie, key: "_sfx_test", signing_salt: "sfx-test-salt"]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])
  plug(Plug.Session, @session_options)
  plug(Cauldron.SFX.Web.Router)
end
