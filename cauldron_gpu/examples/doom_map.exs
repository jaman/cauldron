defmodule DoomWad do
  @moduledoc """
  The parts of a Doom WAD a level is drawn from: the directory, a level's lumps, the
  palette, composed wall textures and floor flats.
  """

  alias Cauldron2D.Sectors.Pictures

  def open(path) do
    <<magic::binary-size(4), count::little-32, offset::little-32, _::binary>> = bytes = File.read!(path)
    true = magic in ["IWAD", "PWAD"]

    lumps =
      for <<at::little-32, size::little-32, name::binary-size(8) <- binary_part(bytes, offset, count * 16)>>,
        do: {clean(name), binary_part(bytes, at, size)}

    %{lumps: lumps, names: lumps |> Enum.reverse() |> Map.new()}
  end

  def lump(wad, name), do: Map.get(wad.names, name)

  def level(wad, name) do
    wad.lumps
    |> Enum.drop_while(fn {lump, _} -> lump != name end)
    |> Enum.drop(1)
    |> Enum.take_while(fn {lump, _} -> lump in ~w(THINGS LINEDEFS SIDEDEFS VERTEXES SEGS SSECTORS NODES SECTORS REJECT BLOCKMAP) end)
    |> Map.new()
  end

  def flats(wad) do
    wad.lumps
    |> Enum.reduce({false, %{}}, fn
      {name, _}, {_, found} when name in ["F_START", "FF_START"] -> {true, found}
      {name, _}, {_, found} when name in ["F_END", "FF_END"] -> {false, found}
      {name, data}, {true, found} when byte_size(data) == 4096 -> {true, Map.put(found, name, data)}
      _, state -> state
    end)
    |> elem(1)
  end

  def textures(wad) do
    names = patch_names(lump(wad, "PNAMES"))

    ["TEXTURE1", "TEXTURE2"]
    |> Enum.map(&lump(wad, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.flat_map(&texture_definitions(&1, names))
    |> Map.new()
  end

  def compose(wad, %{width: width, height: height, patches: patches}) do
    filled =
      for {x0, y0, name} <- patches,
          data = lump(wad, name),
          data != nil,
          {column, posts} <- patch_columns(data),
          x = x0 + column,
          x >= 0 and x < width,
          {top, bytes} <- posts,
          {colour, row} <- Enum.with_index(:binary.bin_to_list(bytes)),
          y = y0 + top + row,
          y >= 0 and y < height,
          into: %{},
          do: {x * height + y, colour}

    pixels = for at <- 0..(width * height - 1), into: <<>>, do: <<Map.get(filled, at, 0)>>
    mask = for at <- 0..(width * height - 1), into: <<>>, do: <<if(Map.has_key?(filled, at), do: 1, else: 0)>>
    %{width: width, height: height, pixels: pixels, mask: if(map_size(filled) == width * height, do: nil, else: mask)}
  end

  def flat_picture(data), do: Pictures.from_rows(64, 64, data)

  defp patch_names(<<count::little-32, rest::binary>>) do
    for <<name::binary-size(8) <- binary_part(rest, 0, count * 8)>>, do: clean(name)
  end

  defp texture_definitions(<<count::little-32, _::binary>> = lump, names) do
    for index <- 0..(count - 1) do
      <<at::little-32>> = binary_part(lump, 4 + index * 4, 4)

      <<name::binary-size(8), _masked::little-32, width::little-16, height::little-16, _columns::little-32,
        patch_count::little-16, rest::binary>> = binary_part(lump, at, byte_size(lump) - at)

      patches =
        for <<x::little-signed-16, y::little-signed-16, patch::little-16, _step::little-16, _colormap::little-16 <-
                binary_part(rest, 0, patch_count * 10)>>,
            do: {x, y, Enum.at(names, patch)}

      {clean(name), %{width: width, height: height, patches: patches}}
    end
  end

  defp patch_columns(<<width::little-16, _height::little-16, _left::little-signed-16, _top::little-signed-16, rest::binary>> = data) do
    for {<<offset::little-32>>, column} <- Enum.with_index(for(<<o::binary-size(4) <- binary_part(rest, 0, width * 4)>>, do: o)),
        do: {column, posts(binary_part(data, offset, byte_size(data) - offset))}
  end

  defp posts(<<255, _::binary>>), do: []
  defp posts(<<top, length, _pad, bytes::binary-size(length), _pad2, rest::binary>>), do: [{top, bytes} | posts(rest)]
  defp posts(_), do: []

  defp clean(name), do: name |> String.split(<<0>>, parts: 2) |> hd() |> String.upcase()
end

defmodule DoomLevel do
  @moduledoc """
  A level of a Doom WAD as a `Cauldron2D.Sectors.Map` with the WAD's own BSP, the
  `Cauldron2D.Sectors.Pictures` its ids index, and its player 1 start.
  """

  alias Cauldron2D.Sectors.Map, as: SectorMap
  alias Cauldron2D.Sectors.Pictures

  @line_flags [{1, :blocks}, {2, :blocks_walkers}, {8, :upper_unpegged}, {16, :lower_unpegged}, {32, :secret}, {64, :blocks_sound}, {128, :hidden}, {256, :mapped}]

  def load(wad, name) do
    lumps = DoomWad.level(wad, name)
    sky = sky_name(name)
    side_records = side_records(lumps["SIDEDEFS"])
    sector_records = sector_records(lumps["SECTORS"])
    pictures = pictures(wad, side_records, sector_records, sky)

    map = %SectorMap{
      vertices: for(<<x::little-signed-16, y::little-signed-16 <- lumps["VERTEXES"]>>, do: {x * 1.0, y * 1.0}) |> List.to_tuple(),
      lines: lines(lumps["LINEDEFS"]),
      sides: side_records |> Enum.map(&side(&1, pictures)) |> List.to_tuple(),
      sectors: sector_records |> Enum.map(&sector(&1, pictures)) |> List.to_tuple()
    }

    map = with_bsp(map, lumps)

    %{
      map: map,
      pictures: pictures,
      palette: binary_part(DoomWad.lump(wad, "PLAYPAL"), 0, 768),
      start: start(map, lumps["THINGS"]),
      sky: Pictures.id(pictures, {:wall, sky}),
      sky_flats: [Pictures.id(pictures, {:flat, "F_SKY1"})] |> Enum.reject(&is_nil/1)
    }
  end

  defp sky_name(<<"E", episode, "M", _::binary>>), do: "SKY#{episode - ?0}"
  defp sky_name("MAP" <> number) when number < "12", do: "SKY1"
  defp sky_name("MAP" <> number) when number < "21", do: "SKY2"
  defp sky_name(_), do: "SKY3"

  defp pictures(wad, side_records, sector_records, sky) do
    definitions = DoomWad.textures(wad)
    flats = DoomWad.flats(wad)

    walls =
      side_records
      |> Enum.flat_map(fn {_x, _y, upper, lower, middle, _sector} -> [upper, lower, middle] end)
      |> Kernel.++([sky])
      |> Enum.uniq()
      |> Enum.filter(&Map.has_key?(definitions, &1))
      |> Enum.map(&{{:wall, &1}, DoomWad.compose(wad, definitions[&1])})

    floors =
      sector_records
      |> Enum.flat_map(fn {_floor, _ceiling, floor_flat, ceiling_flat, _light} -> [floor_flat, ceiling_flat] end)
      |> Enum.uniq()
      |> Enum.filter(&Map.has_key?(flats, &1))
      |> Enum.map(&{{:flat, &1}, DoomWad.flat_picture(flats[&1])})

    Pictures.new(walls ++ floors, DoomWad.lump(wad, "COLORMAP"), native: false)
  end

  defp side_records(lump) do
    for <<x::little-signed-16, y::little-signed-16, upper::binary-size(8), lower::binary-size(8), middle::binary-size(8),
          sector::little-16 <- lump>>,
        do: {x * 1.0, y * 1.0, clean(upper), clean(lower), clean(middle), sector}
  end

  defp side({x, y, upper, lower, middle, sector}, pictures) do
    %{sector: sector, x_offset: x, y_offset: y, upper: wall(pictures, upper), lower: wall(pictures, lower), middle: wall(pictures, middle)}
  end

  defp wall(pictures, name), do: Pictures.id(pictures, {:wall, name})

  defp sector_records(lump) do
    for <<floor::little-signed-16, ceiling::little-signed-16, floor_flat::binary-size(8), ceiling_flat::binary-size(8),
          light::little-signed-16, _special::little-signed-16, _tag::little-signed-16 <- lump>>,
        do: {floor * 1.0, ceiling * 1.0, clean(floor_flat), clean(ceiling_flat), light |> max(0) |> min(255)}
  end

  defp sector({floor, ceiling, floor_flat, ceiling_flat, light}, pictures) do
    %{
      floor: floor,
      ceiling: ceiling,
      floor_picture: Pictures.id(pictures, {:flat, floor_flat}),
      ceiling_picture: Pictures.id(pictures, {:flat, ceiling_flat}),
      light: light
    }
  end

  defp lines(lump) do
    for <<from::little-16, to::little-16, flags::little-16, special::little-16, tag::little-16, front::little-16,
          back::little-16 <- lump>> do
      %{
        from: from,
        to: to,
        front: front,
        back: if(back == 0xFFFF, do: nil, else: back),
        flags: for({bit, flag} <- @line_flags, Bitwise.band(flags, bit) != 0, into: MapSet.new(), do: flag),
        special: special,
        tag: tag
      }
    end
    |> List.to_tuple()
  end

  defp with_bsp(map, lumps) do
    segs =
      for <<from::little-16, to::little-16, _angle::little-signed-16, line::little-16, side::little-16, offset::little-signed-16 <-
              lumps["SEGS"]>>,
          do: %{from: elem(map.vertices, from), to: elem(map.vertices, to), line: line, side: side, offset: offset * 1.0}

    segs = List.to_tuple(segs)

    subsectors =
      for <<count::little-16, first::little-16 <- lumps["SSECTORS"]>> do
        seg = elem(segs, first)
        %{first: first, count: count, sector: SectorMap.side_sector(map, seg.line, seg.side)}
      end

    nodes =
      for <<x::little-signed-16, y::little-signed-16, dx::little-signed-16, dy::little-signed-16, box::binary-size(16),
            right::little-16, left::little-16 <- lumps["NODES"]>> do
        [rt, rb, rl, rr, lt, lb, ll, lr] = for <<value::little-signed-16 <- box>>, do: value * 1.0
        %{x: x * 1.0, y: y * 1.0, dx: dx * 1.0, dy: dy * 1.0, boxes: {{rt, rb, rl, rr}, {lt, lb, ll, lr}}, children: {child(right), child(left)}}
      end

    %{map | segs: segs, subsectors: List.to_tuple(subsectors), nodes: List.to_tuple(nodes)}
  end

  defp child(value) when value >= 0x8000, do: {:leaf, value - 0x8000}
  defp child(value), do: {:node, value}

  defp start(map, lump) do
    {x, y, angle} =
      Enum.find_value(
        for(<<x::little-signed-16, y::little-signed-16, angle::little-signed-16, type::little-signed-16, _flags::little-16 <- lump>>, do: {x, y, angle, type}),
        {0, 0, 0},
        fn {x, y, angle, type} -> if type == 1, do: {x, y, angle} end
      )

    floor = elem(map.sectors, SectorMap.sector_at(map, {x * 1.0, y * 1.0})).floor
    {{x * 1.0, y * 1.0, floor + 41.0}, angle * 1.0}
  end

  defp clean(name), do: name |> String.split(<<0>>, parts: 2) |> hd() |> String.upcase()
end

defmodule DoomMap do
  @moduledoc """
  Walks a Doom level drawn on the graphics card: its floors, ceilings, walls and sky,
  from the player 1 start. Fly with W A S D, Space and Left Shift, look with the mouse,
  Escape quits.

      mix run examples/doom_map.exs path/to/DOOM1.WAD E1M1 [seconds] [backend]

  With `seconds` the walk stops by itself; with `CAPTURE=path.png` set it saves the last
  frame before closing. `EFFECTS=rt` adds ray-traced ambient occlusion over the sector
  light.
  """

  alias CauldronGPU.{Camera, Environment, Quat, Sectors}

  @tick_ms 33

  def run([path, name | rest]) do
    {seconds, backend} = parse(rest)
    {micros, level} = :timer.tc(fn -> DoomLevel.load(DoomWad.open(Path.expand(path)), String.upcase(name)) end)
    IO.puts("read #{name}: #{tuple_size(level.map.lines)} lines, #{tuple_size(level.map.sectors)} sectors in #{div(micros, 1000)} ms")
    {:ok, gpu} = CauldronGPU.open(title: "#{name} — cauldron_gpu", width: 1280, height: 720, backend: backend)
    IO.inspect(gpu.info, label: "device")

    {micros, world} =
      :timer.tc(fn -> Sectors.upload(gpu, level.map, level.pictures, level.palette, sky: level.sky, sky_flats: level.sky_flats) end)

    IO.puts("uploaded in #{div(micros, 1000)} ms")
    environment = %Environment{ambient_intensity: 0.0, fog_density: 0.0, reflections: 0.0, ao_radius: 1.2}
    CauldronGPU.submit(gpu, [environment, effects(System.get_env("EFFECTS")) | Sectors.instances(world)])
    if seconds == nil, do: CauldronGPU.relative_mouse(gpu, true)
    {origin, angle} = level.start
    state = %{gpu: gpu, world: world, position: Sectors.point(world, origin), yaw: angle, pitch: 0.0, keys: MapSet.new()}
    loop(state, seconds && System.monotonic_time(:millisecond) + seconds * 1000)
    IO.puts("frames drawn: #{CauldronGPU.frames(gpu)}")
    save_capture(gpu, System.get_env("CAPTURE"))
    CauldronGPU.close(gpu)
  end

  defp effects(nil), do: {:effects, []}

  defp effects(names) do
    {:effects, names |> String.split(",") |> Enum.flat_map(&effect/1)}
  end

  defp effect("rt"), do: [:ray_traced_ambient_occlusion]
  defp effect("upscale"), do: [:upscaling]
  defp effect(_), do: []

  defp parse([]), do: {nil, nil}
  defp parse([seconds]), do: {String.to_integer(seconds), nil}
  defp parse([seconds, "metal"]), do: {String.to_integer(seconds), :metal}
  defp parse([seconds, "vulkan"]), do: {String.to_integer(seconds), :vulkan}

  defp save_capture(_gpu, nil), do: :ok

  defp save_capture(gpu, path) do
    {:ok, frame} = CauldronGPU.capture(gpu)
    File.write!(path, CauldronGPU.PNG.encode(frame))
    IO.puts("saved #{frame.width}x#{frame.height} to #{path}")
  end

  defp loop(state, deadline) do
    if deadline && System.monotonic_time(:millisecond) >= deadline do
      :done
    else
      state = state |> drain_events() |> fly()

      CauldronGPU.submit(state.gpu, [
        %Camera{position: state.position, rotation: rotation(state), fov_y: 1.2, near: 0.05, far: Sectors.far(state.world)}
      ])

      if state[:quit], do: :done, else: (Process.sleep(@tick_ms); loop(state, deadline))
    end
  end

  defp rotation(state), do: Sectors.facing(state.yaw, state.pitch)

  defp drain_events(state) do
    id = state.gpu.id

    receive do
      {:cauldron_gpu, ^id, {:key, :down, :escape, _}} -> Map.put(state, :quit, true)
      {:cauldron_gpu, ^id, :close_requested} -> Map.put(state, :quit, true)
      {:cauldron_gpu, ^id, {:key, :down, key, _}} -> drain_events(%{state | keys: MapSet.put(state.keys, key)})
      {:cauldron_gpu, ^id, {:key, :up, key, _}} -> drain_events(%{state | keys: MapSet.delete(state.keys, key)})
      {:cauldron_gpu, ^id, {:mouse_motion, _, _, dx, dy}} ->
        drain_events(%{state | yaw: state.yaw - dx * 0.15, pitch: max(min(state.pitch - dy * 0.003, 1.5), -1.5)})

      {:cauldron_gpu, ^id, {:error, message}} -> IO.puts("renderer: #{message}") && drain_events(state)
      {:cauldron_gpu, ^id, _} -> drain_events(state)
    after
      0 -> state
    end
  end

  defp fly(state) do
    turn = rotation(state)

    step =
      Enum.reduce([w: {0, 0, -1}, s: {0, 0, 1}, a: {-1, 0, 0}, d: {1, 0, 0}], {0.0, 0.0, 0.0}, fn {key, direction}, total ->
        if MapSet.member?(state.keys, key), do: add(total, Quat.rotate(turn, direction)), else: total
      end)

    rise = if(MapSet.member?(state.keys, :space), do: 1.0, else: 0.0) - if(MapSet.member?(state.keys, :left_shift), do: 1.0, else: 0.0)
    %{state | position: add(state.position, scale(add(step, {0.0, rise, 0.0}), 0.3))}
  end

  defp add({ax, ay, az}, {bx, by, bz}), do: {ax + bx, ay + by, az + bz}
  defp scale({x, y, z}, factor), do: {x * factor, y * factor, z * factor}
end

DoomMap.run(System.argv())
