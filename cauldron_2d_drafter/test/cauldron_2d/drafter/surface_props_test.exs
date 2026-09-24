defmodule Cauldron2D.Drafter.SurfacePropsTest do
  @moduledoc """
  Every option the surface takes in a component tree reaches its state, on the first
  render and on a later one.

  The options are listed in three places — the keys `from_component_opts/2` keeps, the
  fields `mount/1` reads and the fields `update/2` folds — and a key added to one and
  missed in another is lost silently, with the state keeping its default. That is how
  `:density`, `:facings` and `:eye` were each lost in turn.
  """

  use ExUnit.Case, async: true

  alias Cauldron2D.Drafter.Surface

  @options [
    atlas: :some_atlas,
    focus: {3.5, 4.5},
    cell: :some_cell_fun,
    movers: [{:hero, {1.0, 2.0}}],
    labels: [{"x", {0, 0}, {1, 2, 3}}],
    mode: :half,
    zoom: 2,
    compress: false,
    placements: :never,
    on_geometry: :some_message,
    projection: :first_person,
    facing: 3,
    facings: 16,
    tilt: 1.25,
    heading: 0.75,
    pitch: -0.25,
    density: 16,
    eye: 1.35
  ]

  defp props, do: Surface.from_component_opts(nil, @options)

  test "every option it keeps is one it reads on mount" do
    state = Surface.mount(props())

    for {key, value} <- @options do
      assert Map.fetch!(state, key) == value,
             "mount dropped #{inspect(key)}: state holds #{inspect(Map.fetch!(state, key))}"
    end
  end

  test "every option it keeps is one a later render can change" do
    state = Surface.mount(%{})

    changed = Surface.update(props(), state)

    for {key, value} <- @options do
      assert Map.fetch!(changed, key) == value,
             "update dropped #{inspect(key)}: state holds #{inspect(Map.fetch!(changed, key))}"
    end
  end

  test "a later render that mentions none of them changes none of them" do
    state = Surface.mount(props())

    kept = Surface.update(%{}, state)

    for {key, value} <- @options, do: assert(Map.fetch!(kept, key) == value)
  end
end
