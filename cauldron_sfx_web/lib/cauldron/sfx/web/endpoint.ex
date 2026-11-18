defmodule Cauldron.SFX.Web.Endpoint do
  @moduledoc """
  The editor's HTTP endpoint: the LiveView socket and the page.
  """

  use Phoenix.Endpoint, otp_app: :cauldron_sfx_web

  @session_options [store: :cookie, key: "_cauldron_sfx", signing_salt: "cauldron-sfx-salt"]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  plug(Plug.Session, @session_options)
  plug(Cauldron.SFX.Web.Router)
end
