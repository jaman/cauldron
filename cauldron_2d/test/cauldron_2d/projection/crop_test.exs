defmodule Cauldron2D.Projection.CropTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias Cauldron2D.Projection.{Iso, Oblique}
  alias FrenchCurve.Raster

  @tile 8
  @pane {160, 96}
  @rect {32, 16, 48, 32}
  @points [{0.0, 0.0}, {3.5, -2.25}, {-7.0, 11.75}, {21.0, 4.0}]
  @movers [{:hero, {5.0, 7.0}}, {:hero, {2.0, 9.0}}]

  setup_all do
    Atlas.new(:crop_test, tile: @tile, void: {6, 7, 11})
    |> Atlas.put(:grass, Raster.new(@tile, @tile, background: {40, 160, 40, 255}))
    |> Atlas.put(:house, Raster.new(@tile, @tile, background: {160, 120, 80, 255}),
      height: 2,
      faces: %{top: Raster.new(@tile, @tile, background: {200, 40, 40, 255})}
    )
    |> Atlas.put(:hero, Raster.new(@tile, @tile, background: {250, 250, 20, 255}))
    |> Atlas.install()

    :ok
  end

  defp crowded({x, y}) when rem(x + y, 3) == 0, do: {:grass, [:house], nil}
  defp crowded(_position), do: {:grass, [], nil}

  defp town({3, 6}), do: {:grass, [:house], nil}
  defp town({6, 8}), do: {:grass, [:house], nil}
  defp town(_position), do: {:grass, [], nil}

  defp opts(Iso, focus, size) do
    [
      focus: focus,
      cell: &town/1,
      size: size,
      facing: 1,
      facings: 8,
      tilt: 1.0,
      movers: @movers
    ]
  end

  defp opts(Oblique, focus, size),
    do: [focus: focus, cell: &town/1, size: size, squash: 0.5, movers: @movers]

  defp centre_focus(module, opts, {px, py, pw, ph}),
    do: module.unproject(:crop_test, {px + pw / 2, py + ph / 2}, opts)

  for module <- [Iso, Oblique] do
    describe "#{inspect(module)} crops" do
      test "a crop focused on a rectangle's middle projects the pane shifted by its corner" do
        pane = opts(unquote(module), {4.0, 6.0}, @pane)
        {px, py, pw, ph} = @rect
        focus = centre_focus(unquote(module), pane, @rect)
        crop = opts(unquote(module), focus, {pw, ph})

        for point <- @points do
          {fx, fy} = unquote(module).project(:crop_test, point, pane)
          {cx, cy} = unquote(module).project(:crop_test, point, crop)

          assert_in_delta cx, fx - px, 0.001
          assert_in_delta cy, fy - py, 0.001
        end
      end

      test "a crop draws the same pixels as that part of the whole picture" do
        pane = opts(unquote(module), {4.0, 6.0}, @pane)
        {px, py, pw, ph} = @rect
        focus = centre_focus(unquote(module), pane, @rect)

        crop = unquote(module).compose(:crop_test, opts(unquote(module), focus, {pw, ph}))
        whole = unquote(module).compose(:crop_test, pane)

        assert Raster.to_rgba_binary(crop) ==
                 whole |> Raster.crop({px, py}, {pw, ph}) |> Raster.to_rgba_binary()
      end

      test "a patch focused through the scene's own offset matches the scene's pixels" do
        {pane_w, pane_h} = @pane
        size = {pane_w + 64, pane_h + 48}
        scene = Keyword.put(opts(unquote(module), {4.0, 6.0}, size), :cell, &crowded/1)
        drawn = unquote(module).compose(:crop_test, scene)

        {fx, fy} = unquote(module).project(:crop_test, {4.37, 6.21}, scene)
        {sx, sy} = {round(fx - pane_w / 2), round(fy - pane_h / 2)}

        assert {fx - pane_w / 2, fy - pane_h / 2} != {sx / 1, sy / 1},
               "pick a focus whose offset actually rounds, or this proves nothing"

        {px, py, pw, ph} = @rect
        middle = {sx + px + pw / 2, sy + py + ph / 2}
        focus = unquote(module).unproject(:crop_test, middle, scene)
        settings = Keyword.put(opts(unquote(module), focus, {pw, ph}), :cell, &crowded/1)
        patch = unquote(module).compose(:crop_test, settings)

        assert Raster.to_rgba_binary(patch) ==
                 drawn |> Raster.crop({sx + px, sy + py}, {pw, ph}) |> Raster.to_rgba_binary()
      end

      test "a bigger picture shows the pane at the offset of where the focus lands in it" do
        {pane_w, pane_h} = @pane
        composed = {4.0, 6.0}
        moved = {6.5, 9.25}
        scene = opts(unquote(module), composed, {pane_w + 64, pane_h + 48})
        pane = Keyword.put(opts(unquote(module), moved, @pane), :cell, &crowded/1)

        {fx, fy} = unquote(module).project(:crop_test, moved, scene)
        {ox, oy} = {fx - pane_w / 2, fy - pane_h / 2}

        for point <- @points do
          {sx, sy} = unquote(module).project(:crop_test, point, scene)
          {ppx, ppy} = unquote(module).project(:crop_test, point, pane)

          assert_in_delta sx - ox, ppx, 0.001
          assert_in_delta sy - oy, ppy, 0.001
        end
      end

      test "the ground map walks to the same world points unproject answers" do
        pane = opts(unquote(module), {4.0, 6.0}, @pane)
        {origin, across, down} = unquote(module).ground_map(:crop_test, pane)

        for px <- [0, 1, 37, 159], py <- [0, 1, 23, 95] do
          {ox, oy} = origin
          {ax, ay} = across
          {dx, dy} = down
          walked = {ox + px * ax + py * dx, oy + px * ay + py * dy}
          {ux, uy} = unquote(module).unproject(:crop_test, {px, py}, pane)

          assert_in_delta elem(walked, 0), ux, 0.000001
          assert_in_delta elem(walked, 1), uy, 0.000001
        end
      end

      test "the ground map's origin is the world point at the top-left pixel" do
        pane = opts(unquote(module), {4.0, 6.0}, @pane)
        {origin, _across, _down} = unquote(module).ground_map(:crop_test, pane)

        assert origin == unquote(module).unproject(:crop_test, {0, 0}, pane)
      end

      test "the cells a picture shows leave out the void and cover what it draws" do
        pane = opts(unquote(module), {4.0, 6.0}, @pane)
        cells = unquote(module).cells(:crop_test, pane)

        assert {{3, 6}, {:grass, [:house], nil}} in cells
        assert Enum.all?(cells, fn {_position, tile} -> tile != :void end)
        assert Enum.uniq(cells) == cells
      end

      test "a smaller picture shows fewer cells than a larger one on the same focus" do
        {pane_w, pane_h} = @pane
        small = unquote(module).cells(:crop_test, opts(unquote(module), {4.0, 6.0}, @pane))

        big =
          unquote(module).cells(
            :crop_test,
            opts(unquote(module), {4.0, 6.0}, {pane_w + 64, pane_h + 48})
          )

        assert length(small) < length(big)
        assert MapSet.subset?(MapSet.new(small), MapSet.new(big))
      end

      test "a picture composed on the focus it is shown at starts the pane at its margin" do
        {pane_w, pane_h} = @pane
        focus = {4.0, 6.0}
        scene = opts(unquote(module), focus, {pane_w + 64, pane_h + 48})

        {fx, fy} = unquote(module).project(:crop_test, focus, scene)

        assert_in_delta fx - pane_w / 2, 32, 0.001
        assert_in_delta fy - pane_h / 2, 24, 0.001
      end
    end
  end

  test "an isometric patch focused through the unrounded camera misses the scene's pixels" do
    {pane_w, pane_h} = @pane
    size = {pane_w + 64, pane_h + 48}
    scene = Keyword.put(opts(Iso, {4.0, 6.0}, size), :cell, &crowded/1)
    drawn = Iso.compose(:crop_test, scene)

    moved = {4.37, 6.21}
    {fx, fy} = Iso.project(:crop_test, moved, scene)
    {sx, sy} = {round(fx - pane_w / 2), round(fy - pane_h / 2)}

    {px, py, pw, ph} = @rect
    pane = Keyword.put(opts(Iso, moved, @pane), :cell, &crowded/1)
    focus = Iso.unproject(:crop_test, {px + pw / 2, py + ph / 2}, pane)
    patch = Iso.compose(:crop_test, Keyword.put(opts(Iso, focus, {pw, ph}), :cell, &crowded/1))

    refute Raster.to_rgba_binary(patch) ==
             drawn |> Raster.crop({sx + px, sy + py}, {pw, ph}) |> Raster.to_rgba_binary()
  end
end
