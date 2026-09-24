defmodule Cauldron2D.Projection.VolumeNativeTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Projection.Canvas
  alias Cauldron2D.Projection.Volume
  alias Cauldron2D.Projection.Volume.Native
  alias FrenchCurve.Raster

  @width 96
  @height 72

  defp canvas do
    Canvas.new(@width, @height, {40, 60, 90})
  end

  defp plan do
    Volume.ground_plan(
      fn {px, py} -> {px / 12, py / 12} end,
      Volume.eyeline({12.0, 6.0}, {-12.0, 6.0}, 12.0)
    )
  end

  defp painted(volume, plan) do
    box = Volume.box(volume, fn {x, y, _z} -> {x * 12, y * 12} end)

    canvas() |> Volume.paint(volume, box, plan) |> Canvas.to_raster()
  end

  defp apart(one, other) do
    Enum.zip(
      for(<<byte <- Raster.to_rgba_binary(one)>>, do: byte),
      for(<<byte <- Raster.to_rgba_binary(other)>>, do: byte)
    )
    |> Enum.map(fn {a, b} -> abs(a - b) end)
    |> Enum.max()
  end

  @shapes [
    {:sphere, 2.5, 0.0},
    {:sphere, 1.5, 2.0},
    {:cylinder, 2.0, 1.5},
    {:cone, 4.0, :math.pi() / 2, 0.7, 2.0},
    {:beam, 5.0, 1.2, 0.4, 2.0},
    {:cells, MapSet.new([{0, 0}, {1, 0}, {1, 1}, {3, 1}]), 2.0}
  ]

  describe "the C painter and the Elixir one" do
    test "the library is built, so both are being compared" do
      assert Native.available?()
    end

    for {shape, index} <- Enum.with_index(@shapes) do
      test "agree on #{elem(shape, 0)} #{index}" do
        volume =
          Volume.new(
            at: {3.0, 3.0},
            shape: unquote(Macro.escape(shape)),
            colour: {250, 120, 40},
            strength: 0.7
          )

        assert apart(painted(volume, plan()), painted(volume, Map.put(plan(), :native, false))) <=
                 1
      end
    end

    for falloff <- [:depth, :flat, :shell] do
      test "agree on a #{falloff} falloff" do
        volume =
          Volume.new(
            at: {3.0, 3.0},
            shape: {:sphere, 2.5, 0.0},
            colour: {250, 120, 40},
            strength: 0.7,
            falloff: unquote(falloff)
          )

        assert apart(painted(volume, plan()), painted(volume, Map.put(plan(), :native, false))) <=
                 1
      end
    end

    test "agree when something nearer cuts the rays short" do
      volume = Volume.new(at: {3.0, 3.0}, shape: {:sphere, 2.5, 0.0}, colour: {250, 120, 40})

      limits =
        for index <- 0..(@width * @height - 1), into: <<>> do
          <<rem(index, 7) + 1.0::float-native-64>>
        end

      near = Map.put(plan(), :limits, limits)

      assert apart(painted(volume, near), painted(volume, Map.put(near, :native, false))) <= 1
    end
  end
end
