defmodule Cistern.WebTest do
  use ExUnit.Case, async: false
  import Plug.Test

  alias Cistern.Web.Router

  test "the pages serve the title, the lobby and the world for a guest" do
    Cistern.Art.install()
    :ok = Cistern.Worlds.register()
    opts = Router.init([])

    title = :get |> conn("/play") |> Router.call(opts)
    assert title.status == 200
    assert title.resp_body =~ "CISTERN"

    lobby = :get |> conn("/play/lobby") |> Router.call(opts)
    assert lobby.resp_body =~ "The yard"

    world = :get |> conn("/play/world/yard") |> Router.call(opts)
    assert world.status == 200
    assert world.resp_body =~ "cauldron.js"

    assert :get |> conn("/") |> Router.call(opts) |> Map.fetch!(:status) == 302
  end
end
