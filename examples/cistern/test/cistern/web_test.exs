defmodule Cistern.WebTest do
  use ExUnit.Case, async: false
  import Plug.Test

  alias Cistern.Web.Router

  test "the pages serve the title, the lobby and the arena for a guest" do
    Cistern.Art.install()
    :ok = Cistern.Arenas.register()
    opts = Router.init([])

    title = :get |> conn("/play") |> Router.call(opts)
    assert title.status == 200
    assert title.resp_body =~ "CISTERN"

    lobby = :get |> conn("/play/lobby") |> Router.call(opts)
    assert lobby.resp_body =~ "The yard"

    arena = :get |> conn("/play/arena/yard") |> Router.call(opts)
    assert arena.status == 200
    assert arena.resp_body =~ "cauldron.js"

    assert :get |> conn("/") |> Router.call(opts) |> Map.fetch!(:status) == 302
  end
end
