defmodule Cauldron3D.Scene.SoftwareTest do
  use ExUnit.Case, async: true

  alias Cauldron3D.Scene.{Camera, Instance, Mesh, Software, Target}

  test "a cube is twelve triangles of 48-byte vertices" do
    cube = Mesh.cube(1.0)

    assert byte_size(cube.vertices) == 24 * 48
    assert byte_size(cube.indices) == 36 * 4
    assert cube.parts == []
  end

  test "the CPU renderer draws a frame of a submitted scene" do
    test = self()

    {:ok, software} =
      Software.open(
        width: 64,
        height: 64,
        present: fn rgba, width, height -> send(test, {:frame, rgba, width, height}) end
      )

    cube = Target.mesh(software, Mesh.cube(1.0))

    Target.submit(software, [
      {:instance, 1, %Instance{mesh: cube}},
      %Camera{position: {0.0, 0.0, 4.0}}
    ])

    assert_receive {:frame, rgba, 64, 64}, 5_000
    assert byte_size(rgba) == 64 * 64 * 4
  end

  test "the renderer claims none of the card's effects" do
    {:ok, software} =
      Software.open(width: 8, height: 8, present: fn _rgba, _width, _height -> :ok end)

    capabilities = Target.capabilities(software)
    refute capabilities.ray_tracing
    refute capabilities.upscaling
    refute capabilities.frame_generation
  end
end
