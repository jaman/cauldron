defmodule Cauldron2D.Drafter.SurfacePannedTest do
  @moduledoc """
  The isometric and oblique panes drawn as one stored picture with small patches over the
  parts of it that move.
  """

  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias Cauldron2D.Drafter.Surface
  alias Drafter.Session.Context
  alias FrenchCurve.Raster

  setup_all do
    Atlas.new(:panned_widget, tile: 8, void: {6, 7, 11})
    |> Atlas.put(:floor, Raster.new(8, 8, background: {40, 45, 62, 255}), glyph: "· ")
    |> Atlas.put(:house, Raster.new(8, 8, background: {160, 120, 80, 255}), height: 2)
    |> Atlas.put(:hero, Raster.new(8, 8, background: {245, 232, 200, 255}), glyph: "@ ")
    |> Atlas.install()

    :ok
  end

  setup do
    Context.put_terminal_env(%{"TERM" => "xterm-kitty"})
    Context.put_terminal_protocol(:kitty)
    Context.put_cell_size({10, 20})

    on_exit(fn ->
      Process.delete(:drafter_terminal_env)
      Process.delete(:drafter_terminal_protocol)
      Process.delete(:drafter_cell_size)
    end)

    :ok
  end

  defp mount(id, overrides \\ %{}) do
    %{
      atlas: :panned_widget,
      projection: :iso,
      focus: {5.5, 5.5},
      cell: fn
        {7, 5} -> {:floor, [:house], nil}
        _other -> {:floor, [], nil}
      end,
      movers: [{:hero, {5.5, 5.5}, 0.0}],
      placements: true,
      id: id
    }
    |> Map.merge(overrides)
    |> Surface.mount()
  end

  defp rect, do: %{x: 0, y: 0, width: 40, height: 12}

  defp frame(state, id),
    do: state |> Surface.image(rect(), id) |> elem(0) |> IO.iodata_to_binary()

  defp scene_id(id), do: FrenchCurve.image_id({id, :scene})

  defp transmits?(bytes, image), do: bytes =~ "a=t,i=#{image},"

  defp source(bytes, image) do
    [[_whole, x, y]] = Regex.scan(~r/a=p,i=#{image},[^;]*?,x=(\d+),y=(\d+)/, bytes)
    {String.to_integer(x), String.to_integer(y)}
  end

  test "the first frame sends the scene and patches the part the mover covers" do
    id = :panned_first
    bytes = frame(mount(id), id)

    assert transmits?(bytes, scene_id(id))
    assert bytes =~ "z=2"
    assert source(bytes, scene_id(id)) == {20, 12}
  end

  test "a mover that moved is patched without the scene being sent again" do
    id = :panned_mover
    state = mount(id)
    _first = frame(state, id)

    bytes = frame(%{state | movers: [{:hero, {6.5, 5.5}, 0.0}]}, id)

    refute transmits?(bytes, scene_id(id))
    assert bytes =~ "a=p,i=#{scene_id(id)},"
    assert bytes =~ "z=2"
  end

  test "panning inside the margin shows the stored scene at a new offset" do
    id = :panned_pan
    state = mount(id)
    first = frame(state, id)

    bytes = frame(%{state | focus: {6.0, 5.5}}, id)

    refute transmits?(bytes, scene_id(id))
    assert source(bytes, scene_id(id)) != source(first, scene_id(id))
  end

  test "panning past the margin composes the scene again, centred" do
    id = :panned_far
    state = mount(id)
    _first = frame(state, id)

    bytes = frame(%{state | focus: {25.0, 25.0}}, id)

    assert transmits?(bytes, scene_id(id))
    assert source(bytes, scene_id(id)) == {20, 12}
  end

  test "a label is patched over the scene rather than composed into it" do
    id = :panned_labels
    state = mount(id)
    _first = frame(state, id)

    bytes = frame(%{state | labels: [{"x", {6.5, 6.5}, {255, 255, 255}}]}, id)

    refute transmits?(bytes, scene_id(id))
    assert bytes =~ "z=2"
  end

  test "a label drawn where no mover stands gets a patch of its own" do
    id = :panned_far_label
    state = mount(id, %{movers: []})
    _first = frame(state, id)

    still = frame(state, id)
    labelled = frame(%{state | labels: [{"x", {6.5, 6.5}, {255, 255, 255}}]}, id)

    refute still =~ "z=2"
    assert labelled =~ "z=2"
    refute transmits?(labelled, scene_id(id))
  end

  test "a scene that changes every frame stops being stored and is drawn whole" do
    id = :panned_churn
    whole = FrenchCurve.image_id(id)

    drawn =
      for step <- 1..6 do
        grid = fn {x, y} ->
          if {x, y} == {step, step}, do: {:floor, [:house], nil}, else: {:floor, [], nil}
        end

        frame(mount(id, %{cell: grid}), id)
      end

    assert Enum.any?(drawn, &transmits?(&1, scene_id(id)))
    assert transmits?(List.last(drawn), whole)
    refute transmits?(List.last(drawn), scene_id(id))
  end

  test "a volume draws the whole picture and takes the stored scene down" do
    id = :panned_volume
    state = mount(id)
    _first = frame(state, id)

    volume = %{at: {5.5, 5.5}, shape: {:sphere, 3.0, 0.0}, colour: {255, 0, 0}, strength: 0.5}
    bytes = frame(%{state | volumes: [volume]}, id)

    assert bytes =~ "a=d,d=i,i=#{scene_id(id)},"
    refute transmits?(bytes, scene_id(id))
    assert transmits?(bytes, FrenchCurve.image_id(id))
  end

  test "the scene is sent again on the frame after one drawn whole" do
    id = :panned_return
    state = mount(id)
    _first = frame(state, id)
    volume = %{at: {5.5, 5.5}, shape: {:sphere, 3.0, 0.0}, colour: {255, 0, 0}, strength: 0.5}
    _whole = frame(%{state | volumes: [volume]}, id)

    bytes = frame(state, id)

    assert transmits?(bytes, scene_id(id))
  end

  test "movers spread across the pane are drawn whole rather than patched" do
    id = :panned_crowd

    movers =
      for x <- 3..8, y <- 3..8, do: {:hero, {x / 1, y / 1}, 0.0}

    bytes = frame(mount(id, %{movers: movers}), id)

    refute transmits?(bytes, scene_id(id))
    assert transmits?(bytes, FrenchCurve.image_id(id))
  end

  test "the oblique pane is stored and patched the same way" do
    id = :panned_oblique
    state = mount(id, %{projection: :oblique})

    assert transmits?(frame(state, id), scene_id(id))

    bytes = frame(%{state | movers: [{:hero, {6.5, 5.5}, 0.0}]}, id)

    refute transmits?(bytes, scene_id(id))
    assert bytes =~ "z=2"
  end
end
