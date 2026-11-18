defmodule GpuShowcase.Showcase do
  @moduledoc """
  A lit courtyard: a checkered floor, a ring of turning cubes, metal and plastic spheres,
  a sun with shadows and coloured lamps. Fly with W A S D, Space and Left Shift, look
  with the mouse, Escape quits. `mix showcase [seconds] [backend]`
  stops by itself after `seconds` when given; with `CAPTURE=path.png` set it saves the
  last frame there before closing. `EFFECTS=rt,upscale` asks for ray-traced shadows, reflections and ambient
  occlusion, and for drawing at half size upscaled by the device (MetalFX).
  """

  alias Cauldron3D.Scene.{Camera, Quat}

  @tick_ms 50

  def run(args) do
    {seconds, backend} = parse(args)

    {:ok, gpu} =
      CauldronGPU.open(title: "cauldron_gpu showcase", width: 1280, height: 720, backend: backend)

    IO.inspect(gpu.info, label: "device")
    assets = GpuShowcase.Courtyard.upload(gpu)

    CauldronGPU.submit(gpu, [
      effects(System.get_env("EFFECTS")) | GpuShowcase.Courtyard.scene(assets)
    ])

    if seconds == nil, do: CauldronGPU.relative_mouse(gpu, true)
    deadline = seconds && System.monotonic_time(:millisecond) + seconds * 1000

    state = %{
      gpu: gpu,
      assets: assets,
      tick: 0,
      position: {0.0, 2.2, 9.0},
      yaw: 0.0,
      pitch: -0.15,
      keys: MapSet.new()
    }

    loop(state, deadline)
    IO.puts("frames drawn: #{CauldronGPU.frames(gpu)}")
    save_capture(gpu, System.get_env("CAPTURE"))
    CauldronGPU.close(gpu)
  end

  defp save_capture(_gpu, nil), do: :ok

  defp save_capture(gpu, path) do
    {:ok, frame} = CauldronGPU.capture(gpu)
    File.write!(path, Cauldron3D.Scene.PNG.encode(frame))
    IO.puts("saved #{frame.width}x#{frame.height} to #{path}")
  end

  defp effects(nil), do: {:effects, []}

  defp effects(names) do
    {:effects,
     names
     |> String.split(",")
     |> Enum.flat_map(
       &effect(&1, [:ray_traced_shadows, :ray_traced_reflections, :ray_traced_ambient_occlusion])
     )}
  end

  defp effect("rt", traced), do: traced
  defp effect("upscale", _traced), do: [:upscaling]
  defp effect("gi", _traced), do: [:ray_traced_global_illumination]
  defp effect(_, _traced), do: []

  defp parse([]), do: {nil, nil}
  defp parse([seconds]), do: {String.to_integer(seconds), nil}
  defp parse([seconds, "metal"]), do: {String.to_integer(seconds), :metal}
  defp parse([seconds, "vulkan"]), do: {String.to_integer(seconds), :vulkan}

  defp loop(state, deadline) do
    if deadline && System.monotonic_time(:millisecond) >= deadline do
      :done
    else
      state = state |> drain_events() |> fly()

      CauldronGPU.submit(
        state.gpu,
        GpuShowcase.Courtyard.ring(state.assets, state.tick) ++ [camera(state)]
      )

      if state[:quit],
        do: :done,
        else:
          (
            Process.sleep(@tick_ms)
            loop(%{state | tick: state.tick + 1}, deadline)
          )
    end
  end

  defp camera(state),
    do: %Camera{
      position: state.position,
      rotation: Quat.yaw_pitch(state.yaw, state.pitch),
      fov_y: 1.1
    }

  defp drain_events(state) do
    id = state.gpu.id

    receive do
      {:cauldron_gpu, ^id, {:key, :down, :escape, _}} ->
        Map.put(state, :quit, true)

      {:cauldron_gpu, ^id, :close_requested} ->
        Map.put(state, :quit, true)

      {:cauldron_gpu, ^id, {:key, :down, key, _}} ->
        drain_events(%{state | keys: MapSet.put(state.keys, key)})

      {:cauldron_gpu, ^id, {:key, :up, key, _}} ->
        drain_events(%{state | keys: MapSet.delete(state.keys, key)})

      {:cauldron_gpu, ^id, {:mouse_motion, _, _, dx, dy}} ->
        drain_events(look(state, dx, dy))

      {:cauldron_gpu, ^id, {:error, message}} ->
        IO.puts("renderer: #{message}") && drain_events(state)

      {:cauldron_gpu, ^id, _} ->
        drain_events(state)
    after
      0 -> state
    end
  end

  defp look(state, dx, dy),
    do: %{
      state
      | yaw: state.yaw - dx * 0.003,
        pitch: max(min(state.pitch - dy * 0.003, 1.5), -1.5)
    }

  defp fly(state) do
    rotation = Quat.yaw_pitch(state.yaw, state.pitch)
    moves = [w: {0, 0, -1}, s: {0, 0, 1}, a: {-1, 0, 0}, d: {1, 0, 0}]

    step =
      Enum.reduce(moves, {0.0, 0.0, 0.0}, fn {key, direction}, total ->
        if MapSet.member?(state.keys, key),
          do: add(total, Quat.rotate(rotation, direction)),
          else: total
      end)

    rise =
      if(MapSet.member?(state.keys, :space), do: 1.0, else: 0.0) -
        if(MapSet.member?(state.keys, :left_shift), do: 1.0, else: 0.0)

    %{state | position: add(state.position, scale(add(step, {0.0, rise, 0.0}), 0.25))}
  end

  defp add({ax, ay, az}, {bx, by, bz}), do: {ax + bx, ay + by, az + bz}
  defp scale({x, y, z}, factor), do: {x * factor, y * factor, z * factor}
end
