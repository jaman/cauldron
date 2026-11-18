defmodule Cauldron.SFX.Web.EditorLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Cauldron.SFX
  alias Cauldron.SFX.Editor

  @endpoint Cauldron.SFX.Web.TestEndpoint

  setup do
    Application.delete_env(:cauldron_sfx_web, :bank)
    Application.put_env(:cauldron_sfx_web, :out, "sfx.json")

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  defp editor(view), do: :sys.get_state(view.pid).socket.assigns.editor

  test "the page lists the bank's events and its scripts", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert html =~ "fire"
    assert html =~ "6 events"
    assert html =~ "/assets/sfx.js"
    assert html =~ ~s(id="sfx-player")

    js = get(conn, "/assets/sfx.js").resp_body
    assert js =~ "phx:sfx"
    assert js =~ "sfx-player"
    assert get(conn, "/assets/sfx.css").status == 200
    assert get(conn, "/assets/phoenix_live_view.min.js").status == 200
  end

  test "clicking an event selects it", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    html = view |> element("button[phx-value-index='2']") |> render_click()

    assert Editor.current(editor(view)) == "fire"
    assert html =~ "tone square"
  end

  test "p asks the page to play the event", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view |> element("button[phx-value-key='p']") |> render_click()

    assert_push_event(view, "sfx", %{wav: wav})
    assert byte_size(Base.decode64!(wav)) > 44
    assert editor(view).said =~ "played"
  end

  test "a button does what its key does", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view |> element("button[phx-value-key='down']") |> render_click()
    assert editor(view).selected == 1

    view |> element("button[phx-value-key='+']") |> render_click()
    assert_in_delta SFX.event(editor(view).bank, "click").gain, 1.05, 0.001
  end

  test "a new event is named in the form and selected", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    html =
      view
      |> element("form.new")
      |> render_submit(%{"name" => "laser"})

    assert html =~ "laser"
    assert Editor.current(editor(view)) == "laser"
    assert [%{"kind" => "tone"}] = SFX.event(editor(view).bank, "laser").variants
  end

  test "delete event removes the selected one", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view |> element("button[phx-value-key='x']") |> render_click()

    refute "boom" in editor(view).names
    assert length(editor(view).names) == 5
  end

  test "w writes the bank where it is told", %{conn: conn} do
    out = Path.join(System.tmp_dir!(), "sfx_web_#{System.unique_integer([:positive])}.json")
    on_exit(fn -> File.rm(out) end)
    Application.put_env(:cauldron_sfx_web, :out, out)

    {:ok, view, _html} = live(conn, "/")
    view |> element("button[phx-value-key='w']") |> render_click()

    assert File.exists?(out)
    assert length(SFX.events(SFX.read!(out))) == 6
    assert editor(view).said =~ "wrote"
  end

  test "a bank file is read when one is configured", %{conn: conn} do
    dir = Path.join(System.tmp_dir!(), "sfx_web_bank_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)

    bank = %{SFX.starter() | events: Map.take(SFX.starter().events, ["click"])}
    :ok = SFX.write(bank, dir)
    Application.put_env(:cauldron_sfx_web, :bank, Path.join(dir, "sfx.json"))

    {:ok, _view, html} = live(conn, "/")

    assert html =~ "click"
    refute html =~ "boom"
  end
end
