defmodule Cauldron2D.Client.StageTest do
  use ExUnit.Case, async: true

  alias Cauldron.Client.Stage

  defmodule Eye do
    @moduledoc false
    def view, do: Cauldron2D.Client.View
    def look, do: %{projection: :first_person}
    def keymaps, do: [keys: %{}]
    def client_keys, do: %{mouse_look: [:m]}
  end

  test "a left drag turns the first-person eye, a bare move turns it only with mouse look on" do
    stage = Stage.new(Eye, %{sfx: 1.0, music: 1.0, options: %{}})

    {moved, []} = Stage.pointer(stage, %{type: :move, at: {0.5, 0.5}})
    {moved, []} = Stage.pointer(moved, %{type: :move, at: {0.75, 0.5}})
    assert moved.look.heading == 0.0

    {held, []} = Stage.pointer(moved, %{type: :mouse_down, button: :left, at: {0.5, 0.5}})
    {dragged, [:redraw]} = Stage.pointer(held, %{type: :move, at: {0.75, 0.5}})
    assert dragged.look.heading > 0.0

    {let_go, []} = Stage.pointer(dragged, %{type: :mouse_up, button: :left, at: {0.75, 0.5}})
    {still, []} = Stage.pointer(let_go, %{type: :move, at: {0.5, 0.5}})
    assert still.look.heading == dragged.look.heading

    {looking, []} = Stage.key(still, :m)
    {turned, [:redraw]} = Stage.pointer(looking, %{type: :move, at: {0.25, 0.5}})
    assert turned.look.heading < still.look.heading
  end
end
