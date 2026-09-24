defmodule Cauldron2D.Net.PagesTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Plug.Test

  alias Cauldron2D.Atlas
  alias Cauldron2D.Net.Pages
  alias FrenchCurve.Raster

  defmodule PageGame do
    @moduledoc false
    @behaviour Cauldron2D.Client.Game

    def title, do: %{name: "PAGES", tagline: "a game with pages"}
    def atlas, do: :pages_test
    def actions, do: [:left, :right, :fire]

    def keymaps,
      do: [
        arrows: %{left: [:left], right: [:right], fire: [:" ", {:mouse, :left}]},
        wasd: %{left: [:a], right: [:d], fire: [:" "]}
      ]

    def toggles, do: []
    def steering, do: [:left, :right]

    def worlds(%{username: "alice"}),
      do: [
        %{
          id: :pit,
          name: "The Pit",
          world: :none,
          players: 1,
          map: "pit",
          note: "two racers",
          kind: {"race", {0, 200, 0}},
          teams: [1, 2]
        }
      ]

    def worlds(_props), do: [%{id: :pit, name: "The Pit", world: :none, players: 0, map: "pit"}]
    def scene(_view), do: %{focus: {0, 0}, bounds: {1, 1}, cell: fn _ -> :void end, movers: []}
    def hud(_view), do: []
    def listener(_view), do: nil
    def sounds, do: fn _ -> nil end
    def music, do: []
    def cue(_view, _screen), do: nil
    def guide, do: [{"Things", [%{art: :gem, name: "Gem", text: "shiny"}]}]
  end

  setup_all do
    Atlas.new(:pages_test, tile: 4)
    |> Atlas.put(:gem, Raster.new(4, 4, background: {0, 255, 0, 255}))
    |> Atlas.install()

    :ok
  end

  defp opts(extra \\ []),
    do: Pages.init([game: PageGame, username: fn conn -> conn.assigns[:user] end] ++ extra)

  defp get(path, user \\ "alice", extra \\ []) do
    :get |> conn(path) |> assign(:user, user) |> Pages.call(opts(extra))
  end

  test "the title names the game and links to its screens" do
    conn = get("/")
    assert conn.status == 200
    assert conn.resp_body =~ "PAGES"
    assert conn.resp_body =~ "a game with pages"
    assert conn.resp_body =~ ~s|href="/lobby"|
    assert conn.resp_body =~ ~s|href="/guide"|
    assert conn.resp_body =~ ~s|href="/settings"|
  end

  test "the lobby lists the player's worlds with kind, players, map, note, teams and a way to watch" do
    conn = get("/lobby")
    assert conn.resp_body =~ "The Pit"
    assert conn.resp_body =~ "race"
    assert conn.resp_body =~ "two racers"
    assert conn.resp_body =~ ~s|href="/world/pit"|
    assert conn.resp_body =~ ~s|href="/world/pit?team=1"|
    assert conn.resp_body =~ ~s|href="/world/pit?spectate=1"|
    assert get("/worlds.json").resp_body |> Jason.decode!() |> hd() |> Map.get("players") == 1
  end

  test "the world page mounts the canvas with the topic, the presets, the padmap, the steering and the pause key" do
    conn = get("/world/pit?team=2")
    assert conn.resp_body =~ "<canvas"
    assert conn.resp_body =~ ~s|"world:pit"|
    assert conn.resp_body =~ "KeyA"
    assert conn.resp_body =~ "ArrowLeft"
    assert conn.resp_body =~ ~s|"team":"2"|
    assert conn.resp_body =~ "KeyP"
    assert conn.resp_body =~ "cauldron.js"
    assert conn.resp_body =~ "gamepad.js"
    assert conn.resp_body =~ ~s|"dpad_left":["left"]|
    assert conn.resp_body =~ ~s|"left_x":{"neg":["left"]|
    assert get("/world/nope").status == 404
  end

  test "settings and guide pages, the sheet and the scripts are served" do
    assert get("/settings").resp_body =~ "wasd"
    guide = get("/guide")

    assert guide.resp_body =~ "Gem" and guide.resp_body =~ "shiny" and
             guide.resp_body =~ "atlas.png"

    png = get("/atlas.png")
    assert png.status == 200
    assert <<137, "PNG", _::binary>> = png.resp_body
    assert get("/cauldron.js").resp_body =~ "Cauldron"
    assert get("/gamepad.js").resp_body =~ "Gamepad"
    assert get("/phoenix.min.js").status == 200
  end

  test "without a player the pages send them to the login page, or say so" do
    assert get("/lobby", nil, login: "/login").status == 302
    assert get("/lobby", nil).status == 401
    assert get("/", nil).status == 200
  end

  test "links follow the path the pages are mounted at" do
    conn =
      :get
      |> conn("/lobby")
      |> Map.put(:script_name, ["play"])
      |> assign(:user, "alice")
      |> Pages.call(opts())

    assert conn.resp_body =~ ~s|href="/play/world/pit"|
  end
end
