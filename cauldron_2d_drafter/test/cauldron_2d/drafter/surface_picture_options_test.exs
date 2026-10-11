defmodule Cauldron2D.Drafter.SurfacePictureOptionsTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias Cauldron2D.Drafter.Surface
  alias Drafter.Session.Context
  alias FrenchCurve.Raster

  setup_all do
    Atlas.new(:picture_options, tile: 8)
    |> Atlas.put(:floor, Raster.new(8, 8, background: {40, 45, 62, 255}), glyph: "· ")
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

  defp surface(options) do
    test = self()

    draw = fn {width, height} = size, _aspect ->
      send(test, {:asked, size})
      Raster.new(width, height, background: {200, 40, 40, 255})
    end

    Surface.mount(
      Map.merge(
        %{atlas: :picture_options, focus: {0.0, 0.0}, cell: fn _ -> {:floor, [], nil} end},
        Map.merge(%{picture: draw, id: :pane}, options)
      )
    )
  end

  defp asked(options) do
    options |> surface() |> Surface.image(%{x: 0, y: 0, width: 98, height: 32}, :pane)
    assert_received {:asked, size}
    size
  end

  test "a native size is asked for at the largest whole scale fitting the pane's pixels, in the pane's shape" do
    assert asked(%{}) == {196, 128}
    assert asked(%{native: {320, 180}}) == {960, 627}
    assert asked(%{native: {320, 180}, native_scale: 1}) == {320, 209}
  end

  test "png and swap send a stored image, the swap leaving the pixels to the compositor" do
    rect = %{x: 0, y: 0, width: 98, height: 32}

    {paint, _clear, region} = Surface.image(surface(%{}), rect, :pane)
    assert IO.iodata_to_binary(paint) =~ "f=32"
    assert Map.has_key?(region, :place)

    {paint, _clear, region} = Surface.image(surface(%{picture_format: :png}), rect, :pane)
    assert IO.iodata_to_binary(paint) =~ "a=t,i=#{region.crop.image},f=100"
    refute Map.has_key?(region.crop, :spare)

    {paint, clear, region} = Surface.image(surface(%{swap: true}), rect, :pane)
    refute IO.iodata_to_binary(paint) =~ "a=t"
    assert %{spare: spare, encoded: %{control: "f=32" <> _}} = region.crop
    assert IO.iodata_to_binary(clear) =~ "a=d,d=i,i=#{spare}"
  end
end
