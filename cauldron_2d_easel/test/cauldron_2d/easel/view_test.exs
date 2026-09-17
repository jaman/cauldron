defmodule Cauldron2D.Easel.ViewTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Easel
  alias Cauldron2D.Easel.View

  test "the payload carries the frame as colours, the ghost, the palette and the counts" do
    easel =
      Easel.new(2, 1, palette: [{"R", :red}, {"T", "#00ff0080"}])
      |> Easel.paint({0, 0}, "R")
      |> Easel.duplicate_frame()
      |> Easel.paint({1, 0}, "T")

    payload = View.payload(easel, zoom: 8, onion: true)
    assert payload.pixels == [["#ff0000", "rgba(0,255,0,0.502)"]]
    assert payload.ghost == [["#ff0000", nil]]

    assert payload.palette == [
             %{key: "R", css: "#ff0000"},
             %{key: "T", css: "rgba(0,255,0,0.502)"}
           ]

    assert %{width: 2, height: 1, zoom: 8, frame: 1, frames: 2, fps: 8, undo: true, redo: false} =
             payload

    assert View.payload(easel, shown: 0).pixels == [["#ff0000", nil]]
    assert View.payload(easel).ghost == nil
  end
end
