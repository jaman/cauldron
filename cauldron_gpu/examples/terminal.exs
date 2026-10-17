defmodule TerminalQuake do
  @moduledoc """
  A Quake map drawn on the graphics card with no window and shown in the terminal through
  the kitty graphics protocol (Ghostty, kitty, WezTerm). The camera turns slowly at the
  player start.

      mix run examples/terminal.exs ~/quake e1m1 [seconds] [width] [height]

  The picture fills the terminal, drawn at the terminal's own pixel size (or `width` by
  `height` when given, scaled by the terminal to fill), and follows it when it is resized.
  A terminal that reports no pixel size is taken to have 8×16-pixel cells.

  Prints frames per second to standard error when it stops. `EFFECTS=rt` adds ray-traced
  ambient occlusion, `EFFECTS=rt,upscale` also draws at half size and upscales. With
  `FRAMES=path` the escape sequences go to that file instead of the terminal.

  `KITTY` picks how pixels reach the terminal: `shm` (default) writes each frame into a
  POSIX shared-memory object (one of four names, reused) and sends only its name; `file`
  writes a temporary file and sends its path; `direct` sends the zlib-compressed pixels in
  the escape sequence itself. The terminal deletes the shared memory or file after
  reading it. `FPS` caps the frame rate (default 60, `0` for none).
  """

  alias Cauldron3D.Formats.{Bsp, Entities, Files}
  alias CauldronGPU.{Camera, Environment}

  @chunk 4096
  @pool 4
  @size_check_ms 1000

  def run([directory, map | rest]) do
    [seconds | fixed] = numbers(rest, [10, nil, nil])
    {:ok, files} = Files.open(Path.expand(directory), within: "id1")
    palette = binary_part(Files.read(files, "gfx/palette.lmp"), 0, 768)
    {:ok, %{bsp: bsp, entities: text}} = Bsp.parse(Files.read(files, "maps/#{map}.bsp"), texture: &texture/2)
    layout = layout(fixed)
    {:ok, gpu} = CauldronGPU.open(window: false, width: layout.width, height: layout.height)
    world = CauldronGPU.Bsp.upload(gpu, bsp, palette)
    {origin, angle} = spawn_point(Entities.parse(text))
    environment = %Environment{ambient_intensity: 0.0, reflections: 0.0, ao_radius: 1.2}
    CauldronGPU.submit(gpu, [environment, effects(System.get_env("EFFECTS")) | CauldronGPU.Bsp.instances(world)])
    out = output(System.get_env("FRAMES"))
    IO.binwrite(out, "\e[2J\e[?25l")
    started = System.monotonic_time(:millisecond)
    eye = CauldronGPU.Bsp.point(world, {elem(origin, 0), elem(origin, 1), elem(origin, 2) + 22})
    state = %{gpu: gpu, out: out, eye: eye, angle: angle, layout: layout, fixed: fixed, checked: started, count: 0}
    count = loop(state, started + seconds * 1000)
    elapsed = System.monotonic_time(:millisecond) - started
    IO.binwrite(out, "\e_Ga=d,d=a,q=2\e\\\e[2J\e[H\e[?25h")
    Enum.each(0..(@pool - 1), &CauldronGPU.remove_shared_memory(shm_name(&1)))
    IO.puts(:stderr, "#{count} frames in #{elapsed} ms: #{Float.round(count * 1000 / max(elapsed, 1), 1)} frames a second")
    CauldronGPU.close(gpu)
  end

  defp loop(%{count: count} = state, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      count
    else
      state = follow_terminal(state)
      rotation = CauldronGPU.Bsp.facing(state.angle + count * 1.5)
      CauldronGPU.submit(state.gpu, [%Camera{position: state.eye, rotation: rotation, fov_y: 1.3, snap: true}])
      started = System.monotonic_time(:millisecond)
      IO.binwrite(state.out, ["\e[H", frame(state.gpu, medium(System.get_env("KITTY")), count, placement(state.layout))])
      pace(started, System.get_env("FPS", "60"))
      loop(%{state | count: count + 1}, deadline)
    end
  end

  defp follow_terminal(state) do
    now = System.monotonic_time(:millisecond)

    if now - state.checked < @size_check_ms do
      state
    else
      layout = layout(state.fixed)
      if {layout.width, layout.height} != {state.layout.width, state.layout.height}, do: CauldronGPU.resize(state.gpu, layout.width, layout.height)
      if {layout.columns, layout.rows} != {state.layout.columns, state.layout.rows}, do: IO.binwrite(state.out, "\e[2J")
      %{state | layout: layout, checked: now}
    end
  end

  defp layout(fixed) do
    terminal =
      case CauldronGPU.terminal_size() do
        {:ok, size} -> size
        {:error, _} -> %{columns: 120, rows: 34, width: 0, height: 0}
      end

    columns = max(terminal.columns, 1)
    rows = max(terminal.rows - 1, 1)
    cell_width = if terminal.width > 0, do: terminal.width / terminal.columns, else: 8
    cell_height = if terminal.height > 0, do: terminal.height / terminal.rows, else: 16

    case fixed do
      [nil, nil] -> %{columns: columns, rows: rows, width: round(columns * cell_width), height: round(rows * cell_height)}
      [width, height] -> %{columns: columns, rows: rows, width: width, height: height}
    end
  end

  defp placement(layout), do: "c=#{layout.columns},r=#{layout.rows},C=1"

  defp pace(_started, "0"), do: :ok

  defp pace(started, fps) do
    spent = System.monotonic_time(:millisecond) - started
    Process.sleep(max(div(1000, String.to_integer(fps)) - spent, 0))
  end

  defp medium(nil), do: :shm
  defp medium("shm"), do: :shm
  defp medium("file"), do: :file
  defp medium("direct"), do: :direct

  defp frame(gpu, :shm, count, placement) do
    name = shm_name(count)
    {:ok, %{width: width, height: height}} = CauldronGPU.capture(gpu, 5000, shared_memory: name)
    ["\e_Ga=T,f=32,t=s,i=1,q=2,s=#{width},v=#{height},#{placement};", Base.encode64(name), "\e\\"]
  end

  defp frame(gpu, :file, count, placement) do
    {:ok, %{width: width, height: height, pixels: pixels}} = CauldronGPU.capture(gpu)
    path = Path.join(System.tmp_dir!(), "tty-graphics-protocol-cgpu-#{System.pid()}-#{rem(count, @pool)}.rgba")
    File.write!(path, pixels)
    ["\e_Ga=T,f=32,t=t,i=1,q=2,s=#{width},v=#{height},#{placement};", Base.encode64(path), "\e\\"]
  end

  defp frame(gpu, :direct, _count, placement) do
    {:ok, frame} = CauldronGPU.capture(gpu)
    kitty(frame, placement)
  end

  defp shm_name(count), do: "/cgpu#{System.pid()}_#{rem(count, @pool)}"

  defp kitty(%{width: width, height: height, pixels: pixels}, placement) do
    encoded = pixels |> :zlib.compress() |> Base.encode64()
    chunks = for <<chunk::binary-size(@chunk) <- encoded>>, do: chunk
    rest = binary_part(encoded, length(chunks) * @chunk, byte_size(encoded) - length(chunks) * @chunk)
    pieces = if rest == "", do: chunks, else: chunks ++ [rest]
    last = length(pieces) - 1

    pieces
    |> Enum.with_index()
    |> Enum.map(fn
      {piece, 0} ->
        ["\e_Ga=T,f=32,o=z,i=1,q=2,s=#{width},v=#{height},#{placement},m=#{if last == 0, do: 0, else: 1};", piece, "\e\\"]

      {piece, ^last} ->
        ["\e_Gm=0;", piece, "\e\\"]

      {piece, _} ->
        ["\e_Gm=1;", piece, "\e\\"]
    end)
  end

  defp output(nil), do: :stdio
  defp output(path), do: File.open!(path, [:write, :binary])

  defp numbers(given, defaults) do
    Enum.with_index(defaults, fn default, index ->
      case Enum.at(given, index) do
        nil -> default
        text -> String.to_integer(text)
      end
    end)
  end

  defp effects(nil), do: {:effects, []}

  defp effects(names) do
    {:effects, names |> String.split(",") |> Enum.flat_map(&effect/1)}
  end

  defp effect("rt"), do: [:ray_traced_ambient_occlusion]
  defp effect("upscale"), do: [:upscaling]
  defp effect(_), do: []

  defp texture(name, mips) do
    kind =
      cond do
        String.starts_with?(name, "sky") -> :sky
        String.starts_with?(name, "*") -> :liquid
        name in ["trigger", "clip", "hint", "skip"] -> :hidden
        String.starts_with?(name, "{") -> :masked
        true -> :solid
      end

    %{Bsp.solid(name, mips) | kind: kind}
  end

  defp spawn_point(entities) do
    start = Enum.find(entities, &(&1["classname"] == "info_player_start")) || %{}
    [x, y, z] = (start["origin"] || "0 0 0") |> String.split() |> Enum.map(&parse_number/1)
    {{x, y, z}, parse_number(start["angle"] || "0")}
  end

  defp parse_number(text) do
    case Float.parse(text) do
      {value, _} -> value
      :error -> 0.0
    end
  end
end

TerminalQuake.run(System.argv())
