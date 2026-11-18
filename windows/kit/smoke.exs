# A GPU smoke test that needs no window: open the card, upload a cube, draw one frame,
# keep it as a PNG, and print what the renderer says about itself.
#
# Run it from this directory with:
#
#     mix run smoke.exs
#
# Exit codes: 0 drew a frame, 1 the card accepted the scene but not the capture,
# 2 there is no renderer at all (the NIF was not built, or no backend was found).

alias Cauldron3D.Scene.{Camera, Instance, Light, Material, Mesh}

defmodule Smoke do
  @width 320
  @height 200

  def run do
    case CauldronGPU.backends() do
      [] ->
        IO.puts("no backend: #{inspect(CauldronGPU.Native.load_error())}")
        2

      backends ->
        IO.puts("backends: #{Enum.map_join(backends, ", ", &to_string/1)}")
        draw()
    end
  end

  defp draw do
    case CauldronGPU.open(window: false, width: @width, height: @height) do
      {:ok, gpu} ->
        IO.puts("device:   #{gpu.info.device}")
        IO.puts("backend:  #{gpu.info.backend}")

        cube = CauldronGPU.mesh(gpu, Mesh.cube(1.0))
        red = CauldronGPU.material(gpu, %Material{base_color: {0.8, 0.1, 0.1, 1.0}})

        CauldronGPU.submit(gpu, [
          {:instance, 1, %Instance{mesh: cube, materials: [red]}},
          {:light, 1, %Light{kind: :directional, direction: {-0.4, -1.0, -0.3}, shadows: false}},
          %Camera{position: {0.0, 1.0, 4.0}}
        ])

        code = capture(gpu)
        CauldronGPU.close(gpu)
        code

      {:error, reason} ->
        IO.puts("the card refused: #{reason}")
        1
    end
  end

  defp capture(gpu) do
    case CauldronGPU.capture(gpu, 15_000) do
      {:ok, %{width: w, height: h, pixels: pixels}} ->
        path = Path.expand("gpu-smoke.png")
        File.write!(path, png(w, h, pixels))

        digest =
          :crypto.hash(:sha256, pixels) |> Base.encode16(case: :lower) |> binary_part(0, 16)

        IO.puts("frame:    #{w}x#{h}, #{byte_size(pixels)} bytes, sha256 #{digest}")
        IO.puts("picture:  #{path}")
        0

      {:error, reason} ->
        IO.puts("capture failed: #{inspect(reason)}")
        1
    end
  end

  # A PNG of the frame, written here so the test needs nothing but cauldron_gpu.
  defp png(width, height, rgba) do
    raw =
      for <<row::binary-size(width * 4) <- rgba>>, into: <<>> do
        <<0>> <> row
      end

    ihdr = <<width::32, height::32, 8, 6, 0, 0, 0>>

    <<137, 80, 78, 71, 13, 10, 26, 10>> <>
      chunk("IHDR", ihdr) <> chunk("IDAT", :zlib.compress(raw)) <> chunk("IEND", "")
  end

  defp chunk(type, data) do
    <<byte_size(data)::32, type::binary, data::binary, :erlang.crc32(type <> data)::32>>
  end
end

System.halt(Smoke.run())
