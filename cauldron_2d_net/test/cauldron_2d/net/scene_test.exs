defmodule Cauldron2D.Net.SceneTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.{Atlas, Draw, Parallax}
  alias Cauldron2D.Net.Scene
  alias FrenchCurve.Raster

  setup_all do
    Atlas.new(:scene_test, tile: 4, void: {10, 10, 30})
    |> Atlas.put(:floor, Raster.new(4, 4, background: {40, 90, 40, 255}))
    |> Atlas.put(:wall, Raster.new(4, 4, background: {120, 120, 140, 255}), height: 1)
    |> Atlas.put(:hill, Raster.new(4, 4, background: {90, 60, 120, 200}))
    |> Atlas.put(:sky, Raster.new(8, 4, background: {30, 50, 160, 255}))
    |> Atlas.put(:hero, Raster.new(4, 8, background: {250, 200, 60, 255}))
    |> Atlas.tint(:dim, fn {r, g, b, a} -> {div(r, 2), div(g, 2), div(b, 2), a} end)
    |> Atlas.install()

    :ok
  end

  defp view(projection) do
    cell = fn {x, y} ->
      cond do
        y > 6 -> :void
        rem(x, 5) == 0 -> {:wall, [], nil}
        rem(x + y, 3) == 0 -> {:floor, [], :dim}
        true -> {:floor, [], nil}
      end
    end

    Draw.new(
      atlas: :scene_test,
      projection: projection,
      focus: {3.5, 2.25},
      cell: cell,
      movers: [{:hero, {3.0, 2.0}, 0.0, %{tint: :dim}}, {:hero, {5.0, 1.0}}],
      labels: [{"me", {3.0, 1.0}, {255, 255, 0}}],
      volumes: [
        %{at: {4.0, 3.0}, shape: {:sphere, 1.5, 0.0}, colour: {200, 40, 40}, strength: 0.5}
      ],
      layers: [
        Parallax.panorama(
          name: :sky,
          art: :sky,
          size: {2, 1},
          wrap: :x,
          factor: {0.1, 0.0},
          void: :opaque
        ),
        Parallax.layer(
          name: :hills,
          cell: fn {x, y} -> if y == 1 and rem(x, 2) == 0, do: {:hill, [], nil}, else: :void end,
          factor: {0.5, 0.2},
          drift: {0.3, 0.0}
        )
      ],
      screen: [
        {:fill, {0, 0}, {6, 3}, {0, 0, 0, 128}},
        {:art, :hero, {-2, 2}, anchor: :top_right, alpha: 0.5}
      ],
      outlines: [{{2.5, 1.0, 3.5, 3.0}, {90, 200, 255, 220}}]
    )
  end

  defp through_json(payload), do: payload |> Jason.encode!() |> Jason.decode!()

  test "a scene written as data and read back draws the same picture, top-down and isometric" do
    for projection <- [:top, :iso] do
      original = view(projection)
      {_writer, payload} = Scene.write(Scene.writer(), original, {12, 8}, at: 5_000)
      {_reader, read} = Scene.read(Scene.reader(:scene_test), through_json(payload))

      assert Raster.to_rgba_binary(Draw.picture(read, {12, 8}, at: 5_000)) ==
               Raster.to_rgba_binary(Draw.picture(original, {12, 8}, at: 5_000))
    end
  end

  test "cells and kinds already sent are not sent again; a changed or newly seen tile is" do
    original = view(:top)
    {writer, first} = Scene.write(Scene.writer(), original, {12, 8}, at: 0)
    assert first.cells["world"] != [] and first.kinds != []

    {writer, again} = Scene.write(writer, original, {12, 8}, at: 0)
    assert again.cells["world"] == [] and again.kinds == []

    moved = %{original | focus: {4.5, 2.25}}
    {_writer, step} = Scene.write(writer, moved, {12, 8}, at: 0)
    assert step.kinds == []
    assert length(step.cells["world"]) in 3..30
  end

  test "a scene with a volume of a shape the game defines can only be drawn by the server" do
    refute Scene.drawable?(%{
             view(:top)
             | volumes: [%{at: {0.0, 0.0}, shape: {__MODULE__, :mine}}]
           })

    assert Scene.drawable?(view(:top))
  end
end
