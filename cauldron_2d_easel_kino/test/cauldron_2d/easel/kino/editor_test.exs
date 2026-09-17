defmodule Cauldron2D.Easel.Kino.EditorTest do
  use ExUnit.Case, async: true

  import Kino.Test

  alias Cauldron2D.Easel
  alias Cauldron2D.Easel.Kino.Editor

  setup :configure_livebook_bridge

  defp easel do
    Easel.new(4, 4, palette: [{"A", "#ff0000"}, {"B", "#00ff00"}])
  end

  defp editor(easel \\ easel(), opts \\ []), do: Editor.new(easel, opts)

  test "connecting gives the canvas payload with the tools and the chosen colour" do
    editor = editor()
    data = connect(editor)
    assert data.width == 4
    assert data.key == "A"
    assert data.tool == :brush
    assert :fill in data.tools
    refute data.can_save
  end

  test "a stroke paints with the chosen colour and broadcasts the frame" do
    editor = editor()
    connect(editor)
    push_event(editor, "paint", %{"x" => 1, "y" => 2, "phase" => "start"})
    push_event(editor, "paint", %{"x" => 1, "y" => 2, "phase" => "end"})
    assert_broadcast_event(editor, "frame", %{pixels: pixels})
    assert pixels |> Enum.at(2) |> Enum.at(1) == "#ff0000"
    assert Easel.key_at(Editor.easel(editor), {1, 2}, 0) == "A"
  end

  test "picking a colour changes what the brush paints" do
    editor = editor()
    connect(editor)
    push_event(editor, "pick", %{"key" => "B"})
    push_event(editor, "paint", %{"x" => 0, "y" => 0, "phase" => "start"})
    push_event(editor, "paint", %{"x" => 0, "y" => 0, "phase" => "end"})
    assert Easel.key_at(Editor.easel(editor), {0, 0}, 0) == "B"
  end

  test "a line is previewed while dragging and kept on release" do
    editor = editor()
    connect(editor)
    push_event(editor, "tool", %{"tool" => "line"})
    push_event(editor, "paint", %{"x" => 0, "y" => 0, "phase" => "start"})
    push_event(editor, "paint", %{"x" => 3, "y" => 0, "phase" => "drag"})
    push_event(editor, "paint", %{"x" => 0, "y" => 3, "phase" => "end"})
    easel = Editor.easel(editor)
    assert Easel.key_at(easel, {0, 3}, 0) == "A"
    assert Easel.key_at(easel, {3, 0}, 0) == "."
  end

  test "adding a colour takes the next free key and chooses it" do
    editor = editor()
    connect(editor)
    push_event(editor, "add_colour", %{"colour" => "#0000ff"})
    assert_broadcast_event(editor, "frame", %{key: "C", palette: palette})
    assert Enum.map(palette, & &1.key) == ["A", "B", "C"]
  end

  test "frames are added and chosen, undo walks back" do
    editor = editor()
    connect(editor)
    push_event(editor, "add_frame", %{})
    assert_broadcast_event(editor, "frame", %{frames: 2, frame: 1})
    push_event(editor, "frame", %{"index" => 0})
    assert_broadcast_event(editor, "frame", %{frame: 0})
    push_event(editor, "undo", %{})
    assert_broadcast_event(editor, "frame", %{frames: 1})
  end

  test "the eyedropper picks the key under the pointer" do
    editor = editor(Easel.paint(easel(), {2, 2}, "B"))
    connect(editor)
    push_event(editor, "tool", %{"tool" => "eyedropper"})
    push_event(editor, "paint", %{"x" => 2, "y" => 2, "phase" => "start"})
    assert_broadcast_event(editor, "frame", %{key: "B", tool: :brush})
  end

  test "save writes the pic it was given" do
    dir = Path.join(System.tmp_dir!(), "easel_kino_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "dot.pic")
    :ok = Easel.save(easel(), path)
    editor = Editor.new(path)
    connect(editor)
    push_event(editor, "paint", %{"x" => 0, "y" => 0, "phase" => "start"})
    push_event(editor, "paint", %{"x" => 0, "y" => 0, "phase" => "end"})
    push_event(editor, "save", %{})
    assert_broadcast_event(editor, "frame", %{status: "saved dot.pic"})
    {:ok, saved} = Easel.load(path)
    assert Easel.key_at(saved, {0, 0}, 0) == "A"
  end
end
