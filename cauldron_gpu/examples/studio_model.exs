defmodule StudioModelExample do
  @moduledoc """
  Shows a Half-Life studio model on a floor, playing a sequence, posed on the graphics
  card by its bones. Escape quits.

      mix run examples/studio_model.exs path/to/valve/models/barney.mdl [sequence] [seconds] [backend]

  The model's `…t.mdl` texture file and `…01.mdl`, `…02.mdl` animation files are read
  from beside it when they are there. `sequence` is a name or index (default `walk`);
  `SEQUENCES=1` lists the model's sequences. With `seconds` it stops by itself;
  `CAPTURE=path.png` saves the last frame, and `CAPTURE_AT=seconds` one that many seconds
  in as `path` with `-early` before its extension.
  """

  alias Cauldron3D.Formats.Studio
  alias CauldronGPU.{Camera, Environment, Light, Material, Mesh, Placement, StudioModel, Transform}

  @tick_ms 33
  @id 2

  def run([path | rest]) do
    {sequence, seconds, backend} = parse(rest)
    studio = load(Path.expand(path))
    {:ok, gpu} = CauldronGPU.open(title: "#{Path.basename(path)} — cauldron_gpu", width: 1280, height: 720, backend: backend)
    model = StudioModel.upload(gpu, studio)
    if System.get_env("SEQUENCES"), do: IO.puts(Enum.join(StudioModel.sequences(model), " "))
    materials = StudioModel.materials(gpu, model)
    floor = CauldronGPU.mesh(gpu, Mesh.plane(20, 10))
    stone = CauldronGPU.material(gpu, %Material{base_color: {0.35, 0.33, 0.3, 1.0}, roughness: 0.8})
    instance = StudioModel.instance(model, materials, Placement.transform(1 / 32, {0.0, 0.0, 0.0}, 270))

    CauldronGPU.submit(gpu, [
      %Environment{ambient_intensity: 0.35, fog_density: 0.0, shadow_distance: 10.0},
      {:light, 1, %Light{kind: :directional, direction: {-0.4, -1.0, -0.6}, color: {1.0, 0.96, 0.9}, intensity: 3.0, shadows: true}},
      {:instance, 1, %CauldronGPU.Instance{mesh: floor, materials: [stone], transform: %Transform{}}},
      {:instance, @id, instance},
      %Camera{position: {0.0, 1.3, 3.6}, rotation: CauldronGPU.Quat.axis_angle({1, 0, 0}, -0.12), fov_y: 0.9}
    ])

    started = System.monotonic_time(:millisecond)
    early = early_capture(System.get_env("CAPTURE"), System.get_env("CAPTURE_AT"))
    state = %{gpu: gpu, model: model, keep: [materials, floor, stone], sequence: sequence, started: started, early: early}
    loop(state, seconds && started + seconds * 1000)
    save_capture(gpu, System.get_env("CAPTURE"))
    CauldronGPU.close(gpu)
  end

  defp load(path) do
    {:ok, studio} = Studio.parse(File.read!(path))
    base = Path.rootname(path)
    studio = with {:ok, bytes} <- File.read(base <> "t.mdl"), do: Studio.add_textures(studio, bytes), else: (_ -> studio)

    Enum.reduce(Studio.missing_groups(studio), studio, fn group, studio ->
      case File.read(base <> String.pad_leading("#{group}", 2, "0") <> ".mdl") do
        {:ok, bytes} -> Studio.add_group(studio, group, bytes)
        _ -> studio
      end
    end)
  end

  defp parse([]), do: {"walk", nil, nil}
  defp parse([sequence]), do: {sequence(sequence), nil, nil}
  defp parse([sequence, seconds]), do: {sequence(sequence), String.to_integer(seconds), nil}
  defp parse([sequence, seconds, backend]), do: {sequence(sequence), String.to_integer(seconds), String.to_existing_atom(backend)}

  defp sequence(text) do
    case Integer.parse(text) do
      {index, ""} -> index
      _ -> text
    end
  end

  defp early_capture(nil, _at), do: nil
  defp early_capture(_path, nil), do: nil

  defp early_capture(path, at) do
    {seconds, _} = Float.parse(at)
    {Path.rootname(path) <> "-early" <> Path.extname(path), round(seconds * 1000)}
  end

  defp loop(state, deadline) do
    now = System.monotonic_time(:millisecond)

    if (deadline && now >= deadline) or quit?(state.gpu) do
      :done
    else
      time = (now - state.started) / 1000
      CauldronGPU.submit(state.gpu, [StudioModel.pose(state.model, @id, state.sequence, time)])
      state = maybe_capture_early(state, now - state.started)
      Process.sleep(@tick_ms)
      loop(state, deadline)
    end
  end

  defp quit?(%{id: id} = gpu) do
    receive do
      {:cauldron_gpu, ^id, {:key, :down, :escape, _}} -> true
      {:cauldron_gpu, ^id, :close_requested} -> true
      {:cauldron_gpu, ^id, {:error, message}} -> IO.puts("renderer: #{message}") && quit?(gpu)
      {:cauldron_gpu, ^id, _} -> quit?(gpu)
    after
      0 -> false
    end
  end

  defp maybe_capture_early(%{early: {path, at}} = state, elapsed) when elapsed >= at do
    save_capture(state.gpu, path)
    %{state | early: nil}
  end

  defp maybe_capture_early(state, _elapsed), do: state

  defp save_capture(_gpu, nil), do: :ok

  defp save_capture(gpu, path) do
    {:ok, frame} = CauldronGPU.capture(gpu)
    File.write!(path, CauldronGPU.PNG.encode(frame))
    IO.puts("saved #{frame.width}x#{frame.height} to #{path}")
  end
end

StudioModelExample.run(System.argv())
