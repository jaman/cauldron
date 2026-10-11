defmodule Cauldron2D.Easel.Sectors do
  @moduledoc """
  A sector map being edited: rooms drawn as polygons on a grid, joined where they share
  an edge, with heights, pictures and light set per room and per wall, and a history to
  undo through. Every function is pure; a front end holds the document and draws it.

      doc =
        Cauldron2D.Easel.Sectors.new(grid: 32)
        |> Cauldron2D.Easel.Sectors.draw_room([{0, 0}, {0, 256}, {256, 256}, {256, 0}])
        |> Cauldron2D.Easel.Sectors.draw_room([{256, 64}, {256, 192}, {384, 192}, {384, 64}])

      {:ok, map} = Cauldron2D.Easel.Sectors.to_map(doc, &MyGame.picture_id/1)
      :ok = Cauldron2D.Easel.Sectors.save(doc, "priv/maps/hall.json")

  `draw_room/3` snaps the points to the grid and takes them in either order. Where an
  edge runs along a wall of a room already drawn, the wall becomes an opening between
  the two rooms — its middle picture taken away and upper and lower pictures given to
  both sides — and a wall that only partly overlaps is split first. A room drawn over
  the inside of another is refused and the document returned unchanged.

  Ids are integers and stay with what they name through edits. Pictures are named by
  the game's own names; `to_map/2` turns the document into a
  `Cauldron2D.Sectors.Map` with its BSP, looking each name up with the function given.

  ## Room options

    * `:floor`, `:ceiling` — heights. Default `0` and `128`
    * `:floor_picture`, `:ceiling_picture`, `:wall` — picture names. Default `"floor"`,
      `"ceiling"` and `"wall"`
    * `:light` — `0..255`. Default `160`
  """

  @enforce_keys [:grid]
  defstruct grid: 32, vertices: %{}, lines: %{}, sectors: %{}, next: 1, past: [], future: []

  @type point :: {number(), number()}
  @type side :: %{
          sector: pos_integer(),
          upper: String.t() | nil,
          middle: String.t() | nil,
          lower: String.t() | nil,
          x_offset: number(),
          y_offset: number()
        }
  @type t :: %__MODULE__{
          grid: pos_integer(),
          vertices: %{pos_integer() => point()},
          lines: %{pos_integer() => map()},
          sectors: %{pos_integer() => map()},
          next: pos_integer(),
          past: list(),
          future: list()
        }

  @history 100

  @doc "An empty document. Option `:grid`, the snap in world units, default `32`."
  @spec new(keyword()) :: t()
  def new(opts \\ []), do: %__MODULE__{grid: Keyword.get(opts, :grid, 32)}

  @doc "`point` moved to the nearest grid point."
  @spec snap(t(), point()) :: point()
  def snap(%__MODULE__{grid: grid}, {x, y}),
    do: {round(x / grid) * grid * 1.0, round(y / grid) * grid * 1.0}

  @doc "Draw a room through `points`. See the moduledoc."
  @spec draw_room(t(), [point()], keyword()) :: t()
  def draw_room(%__MODULE__{} = doc, points, opts \\ []) do
    points = points |> Enum.map(&snap(doc, &1)) |> Enum.dedup() |> drop_closing()

    if length(points) < 3 or area(points) == 0 do
      doc
    else
      points = if area(points) > 0, do: Enum.reverse(points), else: points

      case add_room(doc, points, opts) do
        {:ok, changed} -> remember(doc, changed)
        :overlap -> doc
      end
    end
  end

  defp drop_closing([first | _rest] = points),
    do: if(List.last(points) == first, do: Enum.drop(points, -1), else: points)

  defp area(points) do
    points
    |> Enum.zip(tl(points) ++ [hd(points)])
    |> Enum.reduce(0.0, fn {{x1, y1}, {x2, y2}}, acc -> acc + (x1 * y2 - x2 * y1) end)
    |> Kernel./(2)
  end

  defp add_room(doc, points, opts) do
    sector_id = doc.next
    doc = %{doc | next: doc.next + 1, sectors: Map.put(doc.sectors, sector_id, sector(opts))}
    wall = Keyword.get(opts, :wall, "wall")
    {ids, doc} = Enum.map_reduce(points, doc, fn point, acc -> acc |> vertex(point) |> swap() end)
    doc = Enum.reduce(ids, doc, &split_at_vertex(&2, &1))
    ids = through_vertices(doc, ids)
    edges = Enum.zip(ids, tl(ids) ++ [hd(ids)])

    Enum.reduce_while(edges, {:ok, doc}, fn edge, {:ok, acc} ->
      case add_edge(acc, edge, sector_id, wall) do
        {:ok, acc} -> {:cont, {:ok, acc}}
        :overlap -> {:halt, :overlap}
      end
    end)
  end

  defp swap({a, b}), do: {b, a}

  defp through_vertices(doc, ids) do
    ids
    |> Enum.zip(tl(ids) ++ [hd(ids)])
    |> Enum.flat_map(fn {from, to} -> [from | between(doc, from, to)] end)
  end

  defp between(doc, from, to) do
    a = Map.fetch!(doc.vertices, from)
    b = Map.fetch!(doc.vertices, to)

    doc.vertices
    |> Enum.filter(fn {_id, point} -> point != a and point != b and on_segment?(a, b, point) end)
    |> Enum.sort_by(fn {_id, {x, y}} ->
      (x - elem(a, 0)) * (x - elem(a, 0)) + (y - elem(a, 1)) * (y - elem(a, 1))
    end)
    |> Enum.map(&elem(&1, 0))
  end

  defp sector(opts) do
    %{
      floor: Keyword.get(opts, :floor, 0) * 1.0,
      ceiling: Keyword.get(opts, :ceiling, 128) * 1.0,
      floor_picture: Keyword.get(opts, :floor_picture, "floor"),
      ceiling_picture: Keyword.get(opts, :ceiling_picture, "ceiling"),
      light: Keyword.get(opts, :light, 160),
      special: 0,
      tag: 0
    }
  end

  defp vertex(doc, point) do
    case Enum.find(doc.vertices, fn {_id, at} -> at == point end) do
      {id, _at} ->
        {doc, id}

      nil ->
        {%{doc | vertices: Map.put(doc.vertices, doc.next, point), next: doc.next + 1}, doc.next}
    end
  end

  defp split_at_vertex(doc, vertex_id) do
    point = Map.fetch!(doc.vertices, vertex_id)

    case Enum.find(doc.lines, fn {_id, line} -> inside?(doc, line, point) end) do
      nil -> doc
      {line_id, line} -> split(doc, line_id, line, vertex_id)
    end
  end

  defp inside?(doc, line, point) do
    a = Map.fetch!(doc.vertices, line.from)
    b = Map.fetch!(doc.vertices, line.to)
    point != a and point != b and on_segment?(a, b, point)
  end

  defp on_segment?({ax, ay}, {bx, by}, {px, py}) do
    cross = (bx - ax) * (py - ay) - (by - ay) * (px - ax)
    dot = (px - ax) * (bx - ax) + (py - ay) * (by - ay)
    abs(cross) < 1.0e-6 and dot > 0 and dot < (bx - ax) * (bx - ax) + (by - ay) * (by - ay)
  end

  defp split(doc, line_id, line, vertex_id) do
    second = %{line | from: vertex_id}
    lines = doc.lines |> Map.put(line_id, %{line | to: vertex_id}) |> Map.put(doc.next, second)
    %{doc | lines: lines, next: doc.next + 1}
  end

  defp add_edge(doc, {from, to}, sector_id, wall) do
    case Enum.find(doc.lines, fn {_id, line} ->
           {line.from, line.to} in [{from, to}, {to, from}]
         end) do
      nil -> {:ok, new_line(doc, {from, to}, sector_id, wall)}
      {_id, %{from: ^from}} -> :overlap
      {_id, %{back: back}} when back != nil -> :overlap
      {id, line} -> {:ok, open(doc, id, line, sector_id, wall)}
    end
  end

  defp new_line(doc, {from, to}, sector_id, wall) do
    line = %{
      from: from,
      to: to,
      front: side(sector_id, wall),
      back: nil,
      flags: [],
      special: 0,
      tag: 0
    }

    %{doc | lines: Map.put(doc.lines, doc.next, line), next: doc.next + 1}
  end

  defp side(sector_id, middle),
    do: %{sector: sector_id, upper: nil, middle: middle, lower: nil, x_offset: 0.0, y_offset: 0.0}

  defp open(doc, id, line, sector_id, wall) do
    front = %{
      line.front
      | middle: nil,
        upper: line.front.middle || wall,
        lower: line.front.middle || wall
    }

    back = %{side(sector_id, nil) | upper: wall, lower: wall}
    %{doc | lines: Map.put(doc.lines, id, %{line | front: front, back: back})}
  end

  @doc "Change sector `id`'s fields — `:floor`, `:ceiling`, the pictures, `:light`, `:special`, `:tag`."
  @spec set_sector(t(), pos_integer(), map() | keyword()) :: t()
  def set_sector(doc, id, changes), do: edit(doc, :sectors, id, &Map.merge(&1, Map.new(changes)))

  @doc "Change line `id`'s `:flags`, `:special` or `:tag`."
  @spec set_line(t(), pos_integer(), map() | keyword()) :: t()
  def set_line(doc, id, changes), do: edit(doc, :lines, id, &Map.merge(&1, Map.new(changes)))

  @doc "Change one side (`:front` or `:back`) of line `id`: its pictures and offsets."
  @spec set_side(t(), pos_integer(), :front | :back, map() | keyword()) :: t()
  def set_side(doc, id, which, changes) do
    edit(doc, :lines, id, fn line ->
      case Map.fetch!(line, which) do
        nil -> line
        side -> Map.put(line, which, Map.merge(side, Map.new(changes)))
      end
    end)
  end

  @doc "Move vertex `id` to `point`, snapped to the grid."
  @spec move_vertex(t(), pos_integer(), point()) :: t()
  def move_vertex(doc, id, point), do: edit(doc, :vertices, id, fn _at -> snap(doc, point) end)

  defp edit(doc, key, id, fun) do
    items = Map.fetch!(doc, key)

    case Map.fetch(items, id) do
      {:ok, item} ->
        changed = fun.(item)

        if changed == item,
          do: doc,
          else: remember(doc, Map.put(doc, key, Map.put(items, id, changed)))

      :error ->
        doc
    end
  end

  @doc """
  Remove sector `id`. Its walls go; an opening it shared becomes a wall of the room on
  the other side, facing into that room.
  """
  @spec delete_sector(t(), pos_integer()) :: t()
  def delete_sector(doc, id) do
    if Map.has_key?(doc.sectors, id) do
      lines =
        doc.lines
        |> Enum.flat_map(fn {line_id, line} -> without_sector(line_id, line, id) end)
        |> Map.new()

      changed = %{doc | sectors: Map.delete(doc.sectors, id), lines: lines}
      remember(doc, prune_vertices(changed))
    else
      doc
    end
  end

  defp without_sector(_line_id, %{front: %{sector: id}, back: nil}, id), do: []

  defp without_sector(line_id, %{front: %{sector: id}, back: back} = line, id),
    do: [
      {line_id,
       %{line | from: line.to, to: line.from, front: walled(back, line.front.upper), back: nil}}
    ]

  defp without_sector(line_id, %{back: %{sector: id}} = line, id),
    do: [{line_id, %{line | front: walled(line.front, line.front.upper), back: nil}}]

  defp without_sector(line_id, line, _id), do: [{line_id, line}]

  defp walled(side, picture),
    do: %{side | middle: side.upper || picture || "wall", upper: nil, lower: nil}

  defp prune_vertices(doc) do
    used = doc.lines |> Map.values() |> Enum.flat_map(&[&1.from, &1.to]) |> MapSet.new()
    %{doc | vertices: Map.filter(doc.vertices, fn {id, _at} -> MapSet.member?(used, id) end)}
  end

  defp remember(previous, changed) do
    snapshot = Map.take(previous, [:vertices, :lines, :sectors, :next])
    %{changed | past: Enum.take([snapshot | previous.past], @history), future: []}
  end

  @doc "Undo the last change, if there is one."
  @spec undo(t()) :: t()
  def undo(%__MODULE__{past: []} = doc), do: doc

  def undo(%__MODULE__{past: [snapshot | rest]} = doc) do
    current = Map.take(doc, [:vertices, :lines, :sectors, :next])
    doc |> Map.merge(snapshot) |> Map.merge(%{past: rest, future: [current | doc.future]})
  end

  @doc "Redo the change last undone, if there is one."
  @spec redo(t()) :: t()
  def redo(%__MODULE__{future: []} = doc), do: doc

  def redo(%__MODULE__{future: [snapshot | rest]} = doc) do
    current = Map.take(doc, [:vertices, :lines, :sectors, :next])
    doc |> Map.merge(snapshot) |> Map.merge(%{future: rest, past: [current | doc.past]})
  end

  @doc "The sector `point` is in, or `nil`."
  @spec sector_at(t(), point()) :: pos_integer() | nil
  def sector_at(doc, {px, py}) do
    Enum.find_value(doc.sectors, fn {id, _sector} ->
      crossings =
        doc.lines
        |> Map.values()
        |> Enum.filter(&(&1.front.sector == id or (&1.back && &1.back.sector == id)))
        |> Enum.count(fn line ->
          {x1, y1} = Map.fetch!(doc.vertices, line.from)
          {x2, y2} = Map.fetch!(doc.vertices, line.to)
          y1 > py != y2 > py and px < x1 + (py - y1) * (x2 - x1) / (y2 - y1)
        end)

      if rem(crossings, 2) == 1, do: id
    end)
  end

  @doc "The vertex within `reach` of `point` nearest it, or `nil`."
  @spec vertex_near(t(), point(), number()) :: pos_integer() | nil
  def vertex_near(doc, {px, py}, reach) do
    doc.vertices
    |> Enum.map(fn {id, {x, y}} ->
      {id, :math.sqrt((x - px) * (x - px) + (y - py) * (y - py))}
    end)
    |> Enum.filter(fn {_id, distance} -> distance <= reach end)
    |> Enum.min_by(&elem(&1, 1), fn -> nil end)
    |> then(&(&1 && elem(&1, 0)))
  end

  @doc "The line within `reach` of `point` nearest it, or `nil`."
  @spec line_near(t(), point(), number()) :: pos_integer() | nil
  def line_near(doc, point, reach) do
    doc.lines
    |> Enum.map(fn {id, line} ->
      {id,
       distance_to(point, Map.fetch!(doc.vertices, line.from), Map.fetch!(doc.vertices, line.to))}
    end)
    |> Enum.filter(fn {_id, distance} -> distance <= reach end)
    |> Enum.min_by(&elem(&1, 1), fn -> nil end)
    |> then(&(&1 && elem(&1, 0)))
  end

  defp distance_to({px, py}, {ax, ay}, {bx, by}) do
    {dx, dy} = {bx - ax, by - ay}
    length = dx * dx + dy * dy

    t =
      if length == 0,
        do: 0.0,
        else: max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / length))

    {cx, cy} = {ax + t * dx, ay + t * dy}
    :math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy))
  end

  @doc """
  The document as a `Cauldron2D.Sectors.Map` with its BSP: `{:ok, map}`, or
  `{:error, :empty}` with no rooms. `picture` turns a picture name into the id the
  map's pictures give it; a name it answers `nil` for is drawn as no picture.
  """
  @spec to_map(t(), (String.t() -> non_neg_integer() | nil)) ::
          {:ok, Cauldron2D.Sectors.Map.t()} | {:error, :empty}
  def to_map(%__MODULE__{sectors: sectors}, _picture) when map_size(sectors) == 0,
    do: {:error, :empty}

  def to_map(doc, picture) do
    vertex_index = index_of(doc.vertices)
    sector_index = index_of(doc.sectors)
    line_list = doc.lines |> Enum.sort() |> Enum.map(&elem(&1, 1))

    {lines, sides} =
      Enum.reduce(line_list, {[], []}, fn line, {lines, sides} ->
        front = length(sides)
        back = if line.back, do: front + 1

        new_sides = [
          map_side(line.front, sector_index, picture)
          | if(line.back, do: [map_side(line.back, sector_index, picture)], else: [])
        ]

        map_line = %{
          from: vertex_index[line.from],
          to: vertex_index[line.to],
          front: front,
          back: back,
          flags: MapSet.new(line.flags),
          special: line.special,
          tag: line.tag
        }

        {[map_line | lines], sides ++ new_sides}
      end)

    map = %Cauldron2D.Sectors.Map{
      vertices: doc.vertices |> Enum.sort() |> Enum.map(&elem(&1, 1)) |> List.to_tuple(),
      lines: lines |> Enum.reverse() |> List.to_tuple(),
      sides: List.to_tuple(sides),
      sectors:
        doc.sectors
        |> Enum.sort()
        |> Enum.map(fn {_id, sector} -> map_sector(sector, picture) end)
        |> List.to_tuple()
    }

    {:ok, Cauldron2D.Sectors.Map.with_bsp(map)}
  end

  defp index_of(items), do: items |> Map.keys() |> Enum.sort() |> Enum.with_index() |> Map.new()

  defp map_side(side, sector_index, picture) do
    %{
      sector: Map.fetch!(sector_index, side.sector),
      x_offset: side.x_offset,
      y_offset: side.y_offset,
      upper: name_to(picture, side.upper),
      middle: name_to(picture, side.middle),
      lower: name_to(picture, side.lower)
    }
  end

  defp map_sector(sector, picture) do
    %{
      sector
      | floor_picture: name_to(picture, sector.floor_picture) || 0,
        ceiling_picture: name_to(picture, sector.ceiling_picture) || 0
    }
  end

  defp name_to(_picture, nil), do: nil
  defp name_to(picture, name), do: picture.(name)

  @doc "Write the document to `path` as JSON."
  @spec save(t(), Path.t()) :: :ok | {:error, File.posix()}
  def save(doc, path) do
    data = %{
      "grid" => doc.grid,
      "next" => doc.next,
      "vertices" => Map.new(doc.vertices, fn {id, {x, y}} -> {Integer.to_string(id), [x, y]} end),
      "sectors" => Map.new(doc.sectors, fn {id, sector} -> {Integer.to_string(id), sector} end),
      "lines" =>
        Map.new(doc.lines, fn {id, line} ->
          {Integer.to_string(id), %{line | flags: Enum.map(line.flags, &Atom.to_string/1)}}
        end)
    }

    File.write(path, JSON.encode!(data))
  end

  @doc "Read a document written by `save/2`."
  @spec load(Path.t()) :: {:ok, t()} | {:error, term()}
  def load(path) do
    with {:ok, text} <- File.read(path),
         {:ok, data} <- JSON.decode(text) do
      {:ok,
       %__MODULE__{
         grid: data["grid"],
         next: data["next"],
         vertices:
           Map.new(data["vertices"], fn {id, [x, y]} ->
             {String.to_integer(id), {x * 1.0, y * 1.0}}
           end),
         sectors:
           Map.new(data["sectors"], fn {id, sector} ->
             {String.to_integer(id), atomize(sector)}
           end),
         lines:
           Map.new(data["lines"], fn {id, line} -> {String.to_integer(id), read_line(line)} end)
       }}
    end
  end

  defp read_line(line) do
    line = atomize(line)

    %{
      line
      | front: atomize(line.front),
        back: line.back && atomize(line.back),
        flags: Enum.map(line.flags, &String.to_existing_atom/1)
    }
  end

  defp atomize(map),
    do: Map.new(map, fn {key, value} -> {String.to_existing_atom(key), value} end)
end
