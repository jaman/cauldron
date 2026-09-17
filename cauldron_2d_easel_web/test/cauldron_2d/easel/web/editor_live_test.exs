defmodule Cauldron2D.Easel.Web.EditorLiveTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Cauldron2D.Easel

  @endpoint Cauldron2D.Easel.Web.TestEndpoint

  setup do
    dir = Path.join(System.tmp_dir!(), "easel_web_test")
    File.write!(Path.join(dir, "gem.pic"), "G #00ff00\nB #0000ff\n\n....\n....\n....\n....\n")
    File.rm(Path.join(dir, "orb.pic"))
    {:ok, conn: Phoenix.ConnTest.build_conn(), dir: dir}
  end

  defp easel(view), do: :sys.get_state(view.pid).socket.assigns.easel

  test "the arts page lists the directory and links to the editor, with its own layout and assets",
       %{conn: conn} do
    {:ok, _view, html} = live(conn, "/easel")
    assert html =~ "gem"
    assert html =~ ~s|href="/easel/gem"|
    assert html =~ "/easel/assets/easel.js"
    assert get(conn, "/easel/assets/easel.js").resp_body =~ "EaselCanvas"
    assert get(conn, "/easel/assets/phoenix_live_view.min.js").status == 200
    assert get(conn, "/easel/assets/easel.css").status == 200
  end

  test "painting, tools, colours, frames, undo, save and install, over the wire", %{
    conn: conn,
    dir: dir
  } do
    {:ok, view, html} = live(conn, "/easel/gem")
    assert html =~ "frame 1/1"
    assert html =~ "phx-hook=\"EaselCanvas\""

    render_hook(view, "paint", %{"x" => 1, "y" => 0, "phase" => "start"})
    render_hook(view, "paint", %{"x" => 1, "y" => 0, "phase" => "end"})
    assert Easel.key_at(easel(view), {1, 0}, 0) == "G"
    assert_push_event(view, "frame", %{pixels: [[nil, "#00ff00", nil, nil] | _]})

    render_click(view, "pick", %{"key" => "B"})
    render_click(view, "tool", %{"tool" => "fill"})
    render_hook(view, "paint", %{"x" => 0, "y" => 3, "phase" => "start"})
    render_hook(view, "paint", %{"x" => 0, "y" => 3, "phase" => "end"})
    assert Easel.key_at(easel(view), {3, 3}, 0) == "B"
    assert Easel.key_at(easel(view), {1, 0}, 0) == "G"

    render_hook(view, "key", %{"key" => "u"})
    assert Easel.key_at(easel(view), {3, 3}, 0) == "."
    render_hook(view, "key", %{"key" => "U"})
    assert Easel.key_at(easel(view), {3, 3}, 0) == "B"

    render_click(view, "a", %{})
    assert render(view) =~ "frame 2/2"
    render_hook(view, "key", %{"key" => ","})
    assert render(view) =~ "frame 1/2"

    render_submit(view, "add_colour", %{"key" => "R", "colour" => "#ff0000"})
    assert Easel.colour(easel(view), "R") == {255, 0, 0, 255}
    assert :sys.get_state(view.pid).socket.assigns.key == "R"

    render_submit(view, "glyph", %{"glyph" => "*", "colour" => "#00ff00"})
    assert File.read!(Path.join(dir, "atlas.txt")) =~ "gem\t* \t#00ff00"

    Cauldron2D.Atlas.subscribe(:easel_web_test)
    render_click(view, "w", %{})
    assert render(view) =~ "saved gem.pic"
    assert render(view) =~ "installed as :easel_web_test"
    assert File.read!(Path.join(dir, "gem.pic")) =~ "---"
    assert_receive {:cauldron_atlas, :easel_web_test, :changed}, 1_000
    assert Cauldron2D.Atlas.entry(Cauldron2D.Atlas.fetch(:easel_web_test), :gem).glyph == "* "
  end

  test "a new art is made from the arts page and starts at the tile size", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/easel")
    render_submit(view, "new_art", %{"name" => "orb"})
    assert render(view) =~ "orb"
    assert Easel.size(easel(view)) == {4, 4}
    assert render(view) =~ "unsaved"
  end
end

defmodule Cauldron2D.Easel.Web.EditorLiveDeriveTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint Cauldron2D.Easel.Web.TestEndpoint

  setup do
    dir = Path.join(System.tmp_dir!(), "easel_web_test")
    File.write!(Path.join(dir, "gem.pic"), "G #00ff00\nB #0000ff\n\nG...\n....\n....\n....\n")
    File.rm(Path.join(dir, "atlas.txt"))
    File.rm(Path.join(dir, "garnet.pic"))

    on_exit(fn ->
      File.rm(Path.join(dir, "atlas.txt"))
      File.rm(Path.join(dir, "garnet.pic"))
    end)

    {:ok, conn: Phoenix.ConnTest.build_conn(), dir: dir}
  end

  test "an art is derived from the arts page, listed with its line, and cloned as a picture", %{
    conn: conn,
    dir: dir
  } do
    {:ok, view, _html} = live(conn, "/easel")

    html =
      view
      |> form("form[phx-submit=derive]", %{
        "name" => "ruby",
        "line" => "from gem; colour G #ff0000; flip h"
      })
      |> render_submit()

    assert html =~ "ruby"
    assert html =~ "from gem; colour G #ff0000; flip h"
    assert File.read!(Path.join(dir, "atlas.txt")) =~ "ruby\t\t\t\tfrom gem"

    html =
      view
      |> form("form[phx-submit=derive]", %{"name" => "ghost", "line" => "from nobody"})
      |> render_submit()

    assert html =~ "not derived"

    {:ok, view, html} = live(conn, "/easel/ruby")
    assert html =~ "frame 1/1"
    assert render_hook(view, "key", %{"key" => "s"}) =~ "ruby is derived"

    {:ok, view, _html} = live(conn, "/easel")

    html =
      view
      |> form("#clone-ruby", %{})
      |> render_submit(%{"from" => "ruby", "name" => "garnet"})

    assert html =~ "garnet.pic"
    assert File.read!(Path.join(dir, "garnet.pic")) =~ "...G"
  end
end
