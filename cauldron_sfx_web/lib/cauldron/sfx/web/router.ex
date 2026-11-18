defmodule Cauldron.SFX.Web.Router do
  @moduledoc """
  The editor's routes: the page, and the scripts and stylesheet it loads.

  The assets are outside the browser pipeline, so they carry no session and no CSRF check —
  a browser fetching a script does not send either.
  """

  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:protect_from_forgery)
  end

  scope "/assets" do
    get("/:file", Cauldron.SFX.Web.Assets, :file)
  end

  scope "/" do
    pipe_through(:browser)

    live_session :editor, root_layout: {Cauldron.SFX.Web.Layout, :root} do
      live("/", Cauldron.SFX.Web.EditorLive, :edit)
    end
  end
end
