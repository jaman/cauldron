defmodule Spheres do
  @moduledoc """
  A load test: rows of metal and plastic spheres of every roughness on a polished floor,
  under a sun with shadows, the camera sweeping across them, and a line a second with
  what the renderer is doing.

      mix run examples/spheres.exs [seconds] [backend]

  `COUNT=n` starts with `n` spheres (default 2000); `=` adds 500 and `-` takes 500 away
  while it runs, Escape quits. `EFFECTS=rt,gi,upscale,fg` asks for ray-traced shadows,
  reflections and ambient occlusion (`rt`), one-bounce global illumination (`gi`),
  drawing at a smaller size upscaled by the device (`upscale`) and frame generation (`fg`).
  With `seconds` it stops by itself; `backend` is `metal` or `vulkan`.

  Each report line gives the frames drawn in the last second, the time the graphics card
  (`gpu`) and the renderer thread (`cpu`) spend on a frame, and the display's refresh rate.
  Frames are paced to the display, so frames a second stop at its refresh rate; the frame
  times are what show how much room is left: a frame fits while the larger of the two is
  under `1000 / refresh` milliseconds.
  """

  alias CauldronGPU.{Camera, Environment, Instance, Light, Material, Mesh, Quat, Transform}

  @tick_ms 33
  @step 500
  @columns 50
  @spacing 1.2
  @first_id 10

  def run(args) do
    {seconds, backend} = parse(args)
    {:ok, gpu} = CauldronGPU.open(title: "cauldron_gpu spheres", width: 1920, height: 1080, backend: backend)
    IO.inspect(gpu.info, label: "device")
    assets = assets(gpu)
    count = String.to_integer(System.get_env("COUNT", "2000"))

    CauldronGPU.submit(gpu, [
      effects(System.get_env("EFFECTS")),
      %Environment{exposure: 1.1, shadow_distance: 40.0, reflections: 1.0},
      {:instance, 1, %Instance{mesh: assets.plane, materials: [assets.floor]}},
      {:light, 1, %Light{kind: :directional, direction: {-0.4, -1.0, -0.5}, intensity: 3.0, shadows: true}}
      | spheres(assets, 0, count)
    ])

    deadline = seconds && System.monotonic_time(:millisecond) + seconds * 1000
    now = System.monotonic_time(:millisecond)
    state = %{gpu: gpu, assets: assets, count: count, tick: 0, reported_at: now, frames: CauldronGPU.frames(gpu)}
    loop(state, deadline)
    CauldronGPU.close(gpu)
  end

  defp assets(gpu) do
    metals = [{0.95, 0.78, 0.35}, {0.95, 0.95, 0.95}, {0.95, 0.64, 0.54}, {0.56, 0.57, 0.58}]
    plastics = [{0.8, 0.1, 0.1}, {0.1, 0.35, 0.9}, {0.1, 0.7, 0.3}]

    materials =
      for roughness <- [0.05, 0.2, 0.4, 0.7],
          {color, metallic} <- Enum.map(metals, &{&1, 1.0}) ++ Enum.map(plastics, &{&1, 0.0}) do
        {r, g, b} = color
        CauldronGPU.material(gpu, %Material{base_color: {r, g, b, 1.0}, metallic: metallic, roughness: roughness})
      end

    %{
      ball: CauldronGPU.mesh(gpu, Mesh.sphere(0.4, 48)),
      plane: CauldronGPU.mesh(gpu, Mesh.plane(200, 40)),
      floor: CauldronGPU.material(gpu, %Material{base_color: {0.45, 0.45, 0.48, 1.0}, roughness: 0.15}),
      materials: List.to_tuple(materials)
    }
  end

  defp spheres(_assets, from, to) when from >= to, do: []

  defp spheres(assets, from, to) do
    for index <- from..(to - 1) do
      {row, column} = {div(index, @columns), rem(index, @columns)}
      material = elem(assets.materials, rem(index * 7 + row, tuple_size(assets.materials)))
      position = {(column - @columns / 2) * @spacing, 0.4, -row * @spacing}

      {:instance, @first_id + index,
       %Instance{mesh: assets.ball, materials: [material], transform: Transform.new(position: position)}}
    end
  end

  defp removed(from, to) when from >= to, do: []
  defp removed(from, to), do: for(index <- from..(to - 1), do: {:remove_instance, @first_id + index})

  defp loop(state, deadline) do
    if deadline && System.monotonic_time(:millisecond) >= deadline do
      :done
    else
      state = drain_events(state)

      if state[:quit] do
        :done
      else
        CauldronGPU.submit(state.gpu, [camera(state.tick)])
        Process.sleep(@tick_ms)
        loop(report(%{state | tick: state.tick + 1}), deadline)
      end
    end
  end

  defp camera(tick) do
    sweep = :math.sin(tick / 90)
    %Camera{position: {sweep * 12.0, 3.0, 6.0}, rotation: Quat.yaw_pitch(sweep * -0.35, -0.25), fov_y: 1.1, far: 400.0}
  end

  defp report(state) do
    now = System.monotonic_time(:millisecond)

    if now - state.reported_at >= 1000 do
      stats = CauldronGPU.stats(state.gpu)
      drawn = round((stats.frames - state.frames) * 1000 / (now - state.reported_at))

      IO.puts(
        "#{state.count} spheres  #{drawn} frames/s  gpu #{Float.round(stats.gpu_ms, 2)} ms  " <>
          "cpu #{Float.round(stats.cpu_ms, 2)} ms  display #{round(stats.refresh_rate)} Hz" <>
          if(stats.generating, do: "  generating", else: "")
      )

      %{state | reported_at: now, frames: stats.frames}
    else
      state
    end
  end

  defp resize(state, count) do
    count = max(count, 0)

    changes =
      if count > state.count,
        do: spheres(state.assets, state.count, count),
        else: removed(count, state.count)

    CauldronGPU.submit(state.gpu, changes)
    %{state | count: count}
  end

  defp drain_events(state) do
    id = state.gpu.id

    receive do
      {:cauldron_gpu, ^id, {:key, :down, :escape, _}} -> Map.put(state, :quit, true)
      {:cauldron_gpu, ^id, :close_requested} -> Map.put(state, :quit, true)
      {:cauldron_gpu, ^id, {:key, :down, :=, _}} -> drain_events(resize(state, state.count + @step))
      {:cauldron_gpu, ^id, {:key, :down, :-, _}} -> drain_events(resize(state, state.count - @step))
      {:cauldron_gpu, ^id, {:error, message}} -> IO.puts("renderer: #{message}") && drain_events(state)
      {:cauldron_gpu, ^id, _} -> drain_events(state)
    after
      0 -> state
    end
  end

  defp effects(nil), do: {:effects, []}

  defp effects(names),
    do: {:effects, names |> String.split(",", trim: true) |> Enum.flat_map(&effect/1)}

  defp effect("rt"), do: [:ray_traced_shadows, :ray_traced_reflections, :ray_traced_ambient_occlusion]
  defp effect("gi"), do: [:ray_traced_global_illumination]
  defp effect("upscale"), do: [:upscaling]
  defp effect("fg"), do: [:frame_generation]
  defp effect(_name), do: []

  defp parse([]), do: {nil, nil}
  defp parse([seconds]), do: {String.to_integer(seconds), nil}
  defp parse([seconds, "metal"]), do: {String.to_integer(seconds), :metal}
  defp parse([seconds, "vulkan"]), do: {String.to_integer(seconds), :vulkan}
end

Spheres.run(System.argv())
