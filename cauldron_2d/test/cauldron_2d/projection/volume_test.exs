defmodule Cauldron2D.Projection.VolumeTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Projection.Volume

  defmodule Slab do
    @behaviour Cauldron2D.Projection.Volume.Shape

    @impl true
    def span({:slab, half}, {_ox, _oy, oz}, {_dx, _dy, dz}) when dz == 0,
      do: if(abs(oz) <= half, do: [{-1.0e9, 1.0e9}], else: [])

    def span({:slab, half}, {_ox, _oy, oz}, {_dx, _dy, dz}) do
      one = (-half - oz) / dz
      other = (half - oz) / dz
      [{min(one, other), max(one, other)}]
    end

    @impl true
    def bounds({:slab, half}), do: {{-half, -half, 0.0}, {half, half, half}}

    @impl true
    def thickness({:slab, half}), do: 2 * half
  end

  defp volume(fields \\ []) do
    Volume.new(Keyword.merge([at: {0.0, 0.0}, shape: {:sphere, 2.0, 0.0}, strength: 0.5], fields))
  end

  describe "through/4" do
    test "a ray straight down the middle of a dome crosses its top half only" do
      length = Volume.through(volume(), {0.0, 0.0, 10.0}, {0.0, 0.0, -1.0}, :infinity)

      assert_in_delta length, 2.0, 1.0e-9
    end

    test "a ray along the ground through the middle crosses the whole diameter" do
      length = Volume.through(volume(), {-10.0, 0.0, 0.0}, {1.0, 0.0, 0.0}, :infinity)

      assert_in_delta length, 4.0, 1.0e-9
    end

    test "the length is the same however big a step the direction takes" do
      one = Volume.through(volume(), {-10.0, 0.0, 0.0}, {1.0, 0.0, 0.0}, :infinity)
      wide = Volume.through(volume(), {-10.0, 0.0, 0.0}, {2.0, 0.0, 0.0}, :infinity)
      slanted = Volume.through(volume(), {-10.0, -10.0, 0.0}, {1.0, 1.0, 0.0}, :infinity)

      assert_in_delta wide, one, 1.0e-9
      assert_in_delta slanted, 4.0, 1.0e-9
    end

    test "an axonometric projection's own eyeline measures the same length as a unit one" do
      eyeline = Volume.eyeline({16.0, 8.0}, {-16.0, 8.0}, 16.0)
      {dx, dy, dz} = eyeline
      size = :math.sqrt(dx * dx + dy * dy + dz * dz)
      unit = {dx / size, dy / size, dz / size}

      assert_in_delta Volume.through(volume(), {0.0, 0.0, 0.0}, eyeline, :infinity),
                      Volume.through(volume(), {0.0, 0.0, 0.0}, unit, :infinity),
                      1.0e-9
    end

    test "a ray that passes beside the volume crosses nothing" do
      assert Volume.through(volume(), {-10.0, 3.0, 0.0}, {1.0, 0.0, 0.0}, :infinity) == 0.0
    end

    test "nothing below the ground counts, whatever the shape says" do
      raised = volume(shape: {:sphere, 2.0, 0.0})
      through = Volume.through(raised, {0.0, 0.0, 1.0}, {0.0, 0.0, -1.0}, :infinity)

      assert_in_delta through, 1.0, 1.0e-9
    end

    test "a surface nearer than the far side cuts the ray short" do
      length = Volume.through(volume(), {-10.0, 0.0, 0.0}, {1.0, 0.0, 0.0}, 9.0)

      assert_in_delta length, 1.0, 1.0e-9
    end

    test "the limit counts the direction's own steps, not the answer's units" do
      length = Volume.through(volume(), {-10.0, 0.0, 0.0}, {2.0, 0.0, 0.0}, 4.5)

      assert_in_delta length, 1.0, 1.0e-9
    end

    test "a surface in front of the volume leaves nothing to tint" do
      assert Volume.through(volume(), {-10.0, 0.0, 0.0}, {1.0, 0.0, 0.0}, 5.0) == 0.0
    end

    test "a ray starting inside counts only what is ahead of it" do
      length = Volume.through(volume(), {0.0, 0.0, 0.5}, {1.0, 0.0, 0.0}, :infinity)

      assert_in_delta length, :math.sqrt(4.0 - 0.25), 1.0e-9
    end

    test "the volume stands where `:at` puts it" do
      moved = volume(at: {5.0, 0.0})

      assert Volume.through(moved, {0.0, 0.0, 0.0}, {1.0, 0.0, 0.0}, :infinity) > 0.0
      assert Volume.through(volume(), {10.0, 0.0, 0.0}, {1.0, 0.0, 0.0}, :infinity) == 0.0
    end

    test "every stretch a shape reports is counted" do
      split = Volume.new(at: {0.0, 0.0}, shape: {:cells, MapSet.new([{0, 0}, {2, 0}]), 2.0})

      length = Volume.through(split, {-1.0, 0.5, 0.5}, {1.0, 0.0, 0.0}, :infinity)

      assert_in_delta length, 2.0, 1.0e-6
    end
  end

  describe "a shape of the caller's own" do
    test "is asked for its spans like any other" do
      own = Volume.new(at: {0.0, 0.0}, shape: {Slab, {:slab, 1.0}})

      length = Volume.through(own, {0.0, 0.0, 3.0}, {0.0, 0.0, -1.0}, :infinity)

      assert_in_delta length, 1.0, 1.0e-9
    end

    test "settles the strength against its own thickness" do
      own = Volume.new(at: {0.0, 0.0}, shape: {Slab, {:slab, 1.0}}, strength: 0.5)

      assert_in_delta own.thickness, 2.0, 1.0e-9
    end
  end

  describe "mix/3" do
    test "nothing crossed leaves the pixel alone" do
      assert Volume.mix(<<10, 20, 30, 255>>, volume(colour: {255, 0, 0}), 0.0) ==
               <<10, 20, 30, 255>>
    end

    test "the thickest crossing tints by the volume's strength" do
      pixel = Volume.mix(<<0, 0, 0, 255>>, volume(colour: {200, 0, 0}, strength: 0.5), 4.0)

      assert <<red, 0, 0, 255>> = pixel
      assert_in_delta red, 100, 1
    end

    test "a thinner crossing tints less" do
      tinted = volume(colour: {200, 0, 0}, strength: 0.5)
      <<thin, _, _, _>> = Volume.mix(<<0, 0, 0, 255>>, tinted, 1.0)
      <<thick, _, _, _>> = Volume.mix(<<0, 0, 0, 255>>, tinted, 3.0)

      assert thin < thick
      assert thin > 0
    end

    test "a flat falloff tints the same however thin the crossing" do
      flat = volume(colour: {200, 0, 0}, strength: 0.5, falloff: :flat)
      <<thin, _, _, _>> = Volume.mix(<<0, 0, 0, 255>>, flat, 0.1)
      <<thick, _, _, _>> = Volume.mix(<<0, 0, 0, 255>>, flat, 4.0)

      assert thin == thick
      assert_in_delta thin, 100, 1
    end

    test "a shell falloff tints the grazing ray most and the middle least" do
      shell = volume(colour: {200, 0, 0}, strength: 0.5, falloff: :shell)
      <<grazing, _, _, _>> = Volume.mix(<<0, 0, 0, 255>>, shell, 0.1)
      <<middle, _, _, _>> = Volume.mix(<<0, 0, 0, 255>>, shell, 4.0)

      assert grazing > middle
      assert middle == 0
    end

    test "a pixel's own opacity is kept" do
      assert <<_, _, _, 0>> = Volume.mix(<<0, 0, 0, 0>>, volume(), 4.0)
    end

    test "full strength stays short of opaque, so a volume is always seen through" do
      <<red, _, _, _>> =
        Volume.mix(<<255, 255, 255, 255>>, volume(colour: {0, 0, 0}, strength: 1.0), 4.0)

      assert red > 0
    end
  end

  describe "eyeline/3" do
    test "the direction a projection flattens to nothing, pointing towards the viewer" do
      across = {12.0, 6.0}
      down = {-12.0, 6.0}
      lift = 16.0
      {dx, dy, dz} = Volume.eyeline(across, down, lift)

      {ax, ay} = across
      {bx, by} = down
      assert_in_delta dx * ax + dy * bx, 0.0, 1.0e-9
      assert_in_delta dx * ay + dy * by - dz * lift, 0.0, 1.0e-9
      assert dz > 0
    end

    test "a projection with no rotation looks along its own vertical" do
      {dx, dy, dz} = Volume.eyeline({16.0, 0.0}, {0.0, 8.0}, 12.0)

      assert_in_delta dx, 0.0, 1.0e-9
      assert_in_delta dy * 8.0 - dz * 12.0, 0.0, 1.0e-9
      assert dz > 0
    end
  end

  describe "box/2 and reach/1" do
    test "the rectangle holds every corner the volume can reach" do
      project = fn {x, y, z} -> {100 + x * 10, 100 + y * 10 - z * 10} end

      assert Volume.box(volume(), project) == {80, 60, 120, 120}
    end

    test "no corner in front of the camera means no rectangle" do
      assert Volume.box(volume(), fn _ -> nil end) == nil
    end

    test "the reach is how far across the ground the shape spreads" do
      beam = Volume.new(at: {0.0, 0.0}, shape: {:beam, 8.0, 1.0, 0.0, 2.0})

      assert Volume.reach(beam) > 8.0
      assert_in_delta Volume.reach(volume()), :math.sqrt(8.0), 1.0e-9
    end
  end

  describe "new/1" do
    test "fills in what a caller leaves out" do
      built = Volume.new(at: {1.0, 2.0})

      assert built.at == {1.0, 2.0}
      assert built.falloff == :depth
      assert {_, _, _} = built.colour
      assert {Cauldron2D.Projection.Volume.Shapes, {:sphere, _, _}} = built.shape
    end

    test "is idempotent, so a projection may normalise what it is handed" do
      built = volume(colour: {1, 2, 3})

      assert Volume.new(built) == built
    end
  end
end
