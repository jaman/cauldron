background = 24

palette = [
  {"K", 0x0A, 0x0A, 0x10}, {"D", 0x1B, 0x1B, 0x22}, {"S", 0x3B, 0x3F, 0x4A},
  {"s", 0x5E, 0x6B, 0x7A}, {"l", 0x9C, 0xA3, 0xAF}, {"L", 0xD4, 0xD8, 0xE1},
  {"W", 0xFF, 0xFF, 0xFF}, {"Y", 0xF4, 0xC4, 0x30}, {"O", 0xB8, 0x5C, 0x1A},
  {"M", 0x6B, 0x1F, 0x2D}, {"R", 0xA0, 0x2A, 0x3A}, {"r", 0xC0, 0x39, 0x4B},
  {"p", 0xE0, 0x7B, 0x91}, {"F", 0xF6, 0xC6, 0xA2}, {"f", 0x8A, 0x66, 0x4E},
  {"h", 0x5A, 0x3A, 0x22}
]

{:ok, raster} = Linocut.load(Path.join(__DIR__, "knight_sheet.png"))
{iw, _} = FrenchCurve.Raster.dimensions(raster)
rgba = FrenchCurve.Raster.to_rgba_binary(raster)

pixel = fn x, y ->
  <<r, g, b, _>> = binary_part(rgba, (round(y) * iw + round(x)) * 4, 4)
  {r, g, b}
end

near = fn {r, g, b}, {pr, pg, pb} ->
  2 * (r - pr) * (r - pr) + 4 * (g - pg) * (g - pg) + 3 * (b - pb) * (b - pb)
end

extract = fn {x0, x1, y0, y1}, inset ->
  k = (y1 - y0 + 1) / 48
  wide = round((x1 - x0 + 1) / k)
  left = div(32 - wide, 2)
  span = max(1, round(k))
  edge = min(inset, div(span - 1, 2))

  grid =
    for ty <- 0..47, into: %{} do
      {ty,
       for tx <- 0..31, into: %{} do
         art = tx - left

         if art < 0 or art >= wide do
           {tx, :clear}
         else
           points =
             for dx <- edge..(span - 1 - edge), dy <- edge..(span - 1 - edge),
                 do: pixel.(x0 + art * k + dx, y0 + ty * k + dy)

           {r, g, b} = Enum.reduce(points, {0, 0, 0}, fn {r, g, b}, {ar, ag, ab} -> {ar + r, ag + g, ab + b} end)
           n = length(points)
           {tx, {div(r, n), div(g, n), div(b, n)}}
         end
       end}
    end

  dim? = fn
    :clear -> true
    {r, g, b} -> r + g + b < background
  end

  flood = fn flood, queue, seen ->
    case queue do
      [] -> seen
      [{x, y} | rest] ->
        if x < 0 or y < 0 or x > 31 or y > 47 or MapSet.member?(seen, {x, y}) or not dim?.(grid[y][x]) do
          flood.(flood, rest, seen)
        else
          flood.(flood, [{x - 1, y}, {x + 1, y}, {x, y - 1}, {x, y + 1} | rest], MapSet.put(seen, {x, y}))
        end
    end
  end

  border = for(x <- 0..31, y <- [0, 47], do: {x, y}) ++ for(y <- 0..47, x <- [0, 31], do: {x, y})
  clear = flood.(flood, border, MapSet.new())

  for ty <- 0..47 do
    for tx <- 0..31, into: "" do
      cond do
        MapSet.member?(clear, {tx, ty}) -> "."
        grid[ty][tx] == :clear -> "."
        true ->
          {key, _, _, _} = Enum.min_by(palette, fn {_k, r, g, b} -> near.(grid[ty][tx], {r, g, b}) end)
          key
      end
    end
  end
end

poses = [
  front: {{30, 400, 137, 813}, 2},
  side: {{757, 829, 104, 233}, 0},
  back: {{893, 969, 103, 233}, 0}
]

swing = fn rows, by ->
  for {row, index} <- Enum.with_index(rows) do
    if index < 38 do
      row
    else
      shifted =
        cond do
          by > 0 -> String.duplicate(".", by) <> String.slice(row, 0, 32 - by)
          by < 0 -> String.slice(row, -by, 32 + by) <> String.duplicate(".", -by)
          true -> row
        end

      shifted
    end
  end
end

header = Enum.map_join(palette, "", fn {key, r, g, b} -> "#{key} ##{Base.encode16(<<r, g, b>>, case: :lower)}\n" end)

write = fn name, frames ->
  File.write!("priv/art/knight_#{name}.pic", header <> "\n" <> Enum.map_join(frames, "\n---\n", &Enum.join(&1, "\n")) <> "\n")
end

for {name, {box, inset}} <- poses do
  rows = extract.(box, inset)
  write.(name, [rows])
  write.("#{name}_walk", [rows, swing.(rows, 1), rows, swing.(rows, -1)])
  filled = rows |> Enum.join() |> String.graphemes() |> Enum.count(&(&1 != "."))
  IO.puts("knight_#{name}: #{filled} of 1536 pixels drawn")
end
