defmodule Cauldron2D.Easel do
  @moduledoc """
  A picture being edited: a palette, frames of palette keys, the frame in hand, and a
  history to undo through. Every function is pure; a front end holds the easel and
  draws it.

      easel = Cauldron2D.Easel.new(16, 16, palette: [{"R", "#c33"}, {"W", :white}])
      easel = easel |> Cauldron2D.Easel.paint({3, 4}, "R") |> Cauldron2D.Easel.fill({0, 0}, "W")
      easel = Cauldron2D.Easel.undo(easel)
      :ok = Cauldron2D.Easel.save(easel, "priv/art/ship.pic")

  A key is one character; `.` is transparent and cannot be a colour. Frames are all the
  same size. A change that changes nothing — painting outside the picture, an unknown
  key — leaves the easel as it was, with nothing to undo.

  The document is what `.pic` holds (`Linocut.Pic`): palette lines, a blank line, the
  frames separated by `---`. A `.png` is the frames side by side as a strip; reading one
  gives every distinct colour a key of its own, and refuses a picture with more colours
  than there are keys.
  """

  alias FrenchCurve.{Png, Raster}
  alias Linocut.{Derive, Palette, Pic}

  @type key :: String.t()
  @type rgba :: {byte(), byte(), byte(), byte()}
  @type point :: {integer(), integer()}
  @type frame :: tuple()
  @type t :: %__MODULE__{
          palette: [{key(), rgba()}],
          width: pos_integer(),
          height: pos_integer(),
          frames: [frame()],
          frame: non_neg_integer(),
          fps: pos_integer(),
          undo: [term()],
          redo: [term()]
        }

  @enforce_keys [:width, :height, :frames]
  defstruct [:width, :height, :frames, palette: [], frame: 0, fps: 8, undo: [], redo: []]

  @transparent "."
  @keys String.graphemes(
          "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789#@%&*+=?!$^~<>[]{}()|/:;,'\"`"
        )

  @doc """
  A transparent picture `width` by `height` with one frame.

  ## Options

    * `:palette` — `[{key, colour}]`, colours as `Linocut.Palette` reads them. Default `[]`
    * `:fps` — frames a second. Default `8`
  """
  @spec new(pos_integer(), pos_integer(), keyword()) :: t()
  def new(width, height, opts \\ []) when width > 0 and height > 0 do
    palette =
      for {key, colour} <- Keyword.get(opts, :palette, []),
          do: {to_string(key), Palette.color(colour)}

    %__MODULE__{
      width: width,
      height: height,
      frames: [blank(width, height)],
      palette: palette,
      fps: Keyword.get(opts, :fps, 8)
    }
  end

  defp blank(width, height),
    do:
      List.duplicate(@transparent, width)
      |> List.to_tuple()
      |> List.duplicate(height)
      |> List.to_tuple()

  @doc "The picture's `{width, height}`."
  @spec size(t()) :: {pos_integer(), pos_integer()}
  def size(%__MODULE__{width: width, height: height}), do: {width, height}

  @doc "The palette's keys, in order."
  @spec keys(t()) :: [key()]
  def keys(%__MODULE__{palette: palette}), do: Enum.map(palette, &elem(&1, 0))

  @doc "The colour under `key`, or `nil`."
  @spec colour(t(), key()) :: rgba() | nil
  def colour(%__MODULE__{palette: palette}, key),
    do: List.keyfind(palette, key, 0, {nil, nil}) |> elem(1)

  @doc "The key at `{x, y}` of frame `index`; `.` for transparent, `nil` outside the picture or the frames."
  @spec key_at(t(), point(), non_neg_integer()) :: key() | nil
  def key_at(%__MODULE__{} = easel, {x, y}, index) do
    case Enum.at(easel.frames, index) do
      nil -> nil
      frame -> if inside?(easel, {x, y}), do: elem(elem(frame, y), x)
    end
  end

  defp inside?(%{width: width, height: height}, {x, y}),
    do: x >= 0 and y >= 0 and x < width and y < height

  @doc "Paint one pixel of the frame in hand."
  @spec paint(t(), point(), key()) :: t()
  def paint(%__MODULE__{} = easel, point, key), do: commit(easel, put_pixels(easel, [point], key))

  @doc "Make one pixel of the frame in hand transparent."
  @spec erase(t(), point()) :: t()
  def erase(%__MODULE__{} = easel, point),
    do: commit(easel, put_pixels(easel, [point], @transparent))

  @doc "Paint a line from `from` to `to`."
  @spec line(t(), point(), point(), key()) :: t()
  def line(%__MODULE__{} = easel, from, to, key),
    do: commit(easel, put_pixels(easel, line_points(from, to), key))

  @doc "Paint a rectangle with corners `from` and `to`, its edges only unless `fill: true`."
  @spec rect(t(), point(), point(), key(), keyword()) :: t()
  def rect(%__MODULE__{} = easel, {x1, y1}, {x2, y2}, key, opts \\ []) do
    {left, right} = Enum.min_max([x1, x2])
    {top, bottom} = Enum.min_max([y1, y2])
    fill? = Keyword.get(opts, :fill, false)

    points =
      for x <- left..right,
          y <- top..bottom,
          fill? or x in [left, right] or y in [top, bottom],
          do: {x, y}

    commit(easel, put_pixels(easel, points, key))
  end

  @doc "Flood the area of one key around `point` with `key`."
  @spec fill(t(), point(), key()) :: t()
  def fill(%__MODULE__{} = easel, point, key) do
    case key_at(easel, point, easel.frame) do
      nil -> easel
      ^key -> easel
      target -> commit(easel, put_pixels(easel, flood(easel, point, target), key))
    end
  end

  defp flood(easel, start, target) do
    frame = Enum.at(easel.frames, easel.frame)
    walk(easel, frame, target, [start], MapSet.new([start])) |> MapSet.to_list()
  end

  defp walk(_easel, _frame, _target, [], seen), do: seen

  defp walk(easel, frame, target, [{x, y} | rest], seen) do
    next =
      for point <- [{x + 1, y}, {x - 1, y}, {x, y + 1}, {x, y - 1}],
          inside?(easel, point),
          not MapSet.member?(seen, point),
          elem(elem(frame, elem(point, 1)), elem(point, 0)) == target,
          do: point

    walk(easel, frame, target, next ++ rest, Enum.reduce(next, seen, &MapSet.put(&2, &1)))
  end

  defp put_pixels(easel, points, key) do
    if key == @transparent or List.keymember?(easel.palette, key, 0) do
      inside = Enum.filter(points, &inside?(easel, &1))
      update_frame(easel, fn frame -> Enum.reduce(inside, frame, &put_key(&2, &1, key)) end)
    else
      easel
    end
  end

  defp put_key(frame, {x, y}, key), do: put_elem(frame, y, put_elem(elem(frame, y), x, key))

  defp update_frame(easel, fun),
    do: %{easel | frames: List.update_at(easel.frames, easel.frame, fun)}

  defp line_points({x1, y1}, {x2, y2}) do
    steps = max(abs(x2 - x1), abs(y2 - y1))

    for step <- 0..steps do
      share = if steps == 0, do: 0, else: step / steps
      {round(x1 + (x2 - x1) * share), round(y1 + (y2 - y1) * share)}
    end
  end

  @doc "Add `key` with `colour` to the palette; a key already there, or `.`, changes nothing."
  @spec add_colour(t(), key(), Palette.spec()) :: t()
  def add_colour(%__MODULE__{} = easel, key, colour) do
    if valid_key?(easel, key),
      do: commit(easel, %{easel | palette: easel.palette ++ [{key, Palette.color(colour)}]}),
      else: easel
  end

  defp valid_key?(easel, key),
    do:
      is_binary(key) and String.length(key) == 1 and key != @transparent and key != " " and
        not List.keymember?(easel.palette, key, 0)

  @doc "Change the colour under `key`."
  @spec set_colour(t(), key(), Palette.spec()) :: t()
  def set_colour(%__MODULE__{} = easel, key, colour) do
    if List.keymember?(easel.palette, key, 0),
      do:
        commit(easel, %{
          easel
          | palette: List.keyreplace(easel.palette, key, 0, {key, Palette.color(colour)})
        }),
      else: easel
  end

  @doc "Call the colour under `from` `to`, in the palette and in every frame."
  @spec rename_key(t(), key(), key()) :: t()
  def rename_key(%__MODULE__{} = easel, from, to) do
    if List.keymember?(easel.palette, from, 0) and valid_key?(easel, to) do
      {_, colour} = List.keyfind(easel.palette, from, 0)
      palette = List.keyreplace(easel.palette, from, 0, {to, colour})

      commit(easel, %{
        easel
        | palette: palette,
          frames: Enum.map(easel.frames, &replace_key(&1, from, to))
      })
    else
      easel
    end
  end

  @doc "Drop `key` from the palette; its pixels go transparent."
  @spec remove_colour(t(), key()) :: t()
  def remove_colour(%__MODULE__{} = easel, key) do
    if List.keymember?(easel.palette, key, 0),
      do:
        commit(easel, %{
          easel
          | palette: List.keydelete(easel.palette, key, 0),
            frames: Enum.map(easel.frames, &replace_key(&1, key, @transparent))
        }),
      else: easel
  end

  defp replace_key(frame, from, to) do
    frame
    |> Tuple.to_list()
    |> Enum.map(fn row ->
      row |> Tuple.to_list() |> Enum.map(&if(&1 == from, do: to, else: &1)) |> List.to_tuple()
    end)
    |> List.to_tuple()
  end

  @doc "Mirror the frame in hand left to right (`:horizontal`) or top to bottom (`:vertical`)."
  @spec flip(t(), :horizontal | :vertical) :: t()
  def flip(%__MODULE__{} = easel, :horizontal),
    do:
      commit(
        easel,
        update_frame(
          easel,
          &map_frame(&1, easel.width, easel.height, fn {x, y} -> {easel.width - 1 - x, y} end)
        )
      )

  def flip(%__MODULE__{} = easel, :vertical),
    do:
      commit(
        easel,
        update_frame(
          easel,
          &map_frame(&1, easel.width, easel.height, fn {x, y} -> {x, easel.height - 1 - y} end)
        )
      )

  @doc """
  The easel with `line`'s operations applied — `Linocut.Derive`'s, without its `from`:
  `colour`, `swap`, `flip`, `turn`, `shift`, `frame`, `reverse`, `over`. `lookup` gives
  the pictures `over` names. The result is a new easel with no history, at this one's
  rate.

      {:ok, red} = Cauldron2D.Easel.derive(knight, "colour C #c02020; flip h")
  """
  @spec derive(t(), String.t(), Derive.lookup()) :: {:ok, t()} | {:error, term()}
  def derive(%__MODULE__{} = easel, line, lookup \\ fn _name -> :error end) do
    text = to_pic(easel)

    source = fn
      "easel" -> {:ok, text}
      name -> lookup.(name)
    end

    with {:ok, ops} <- Derive.parse("from easel; " <> line),
         {:ok, derived} <- Derive.run(ops, source),
         {:ok, made} <- from_pic(derived) do
      {:ok, %{made | fps: easel.fps}}
    end
  end

  @doc "Turn every frame `degrees` counter-clockwise, a multiple of 90; the picture's size turns with it."
  @spec rotate(t(), integer()) :: t()
  def rotate(%__MODULE__{width: width, height: height} = easel, degrees)
      when rem(degrees, 90) == 0 do
    case Integer.mod(div(degrees, 90), 4) do
      0 ->
        easel

      1 ->
        commit(
          easel,
          resize(
            easel,
            height,
            width,
            &map_frame(&1, height, width, fn {x, y} -> {width - 1 - y, x} end)
          )
        )

      2 ->
        commit(
          easel,
          update_frames(
            easel,
            &map_frame(&1, width, height, fn {x, y} -> {width - 1 - x, height - 1 - y} end)
          )
        )

      3 ->
        commit(
          easel,
          resize(
            easel,
            height,
            width,
            &map_frame(&1, height, width, fn {x, y} -> {y, height - 1 - x} end)
          )
        )
    end
  end

  defp resize(easel, width, height, fun),
    do: %{easel | width: width, height: height, frames: Enum.map(easel.frames, fun)}

  defp update_frames(easel, fun), do: %{easel | frames: Enum.map(easel.frames, fun)}

  defp map_frame(frame, new_width, new_height, source_of) do
    build(new_width, new_height, fn point ->
      {sx, sy} = source_of.(point)
      elem(elem(frame, sy), sx)
    end)
  end

  defp build(width, height, key_at) do
    for y <- 0..(height - 1)//1 do
      for x <- 0..(width - 1)//1, do: key_at.({x, y})
    end
    |> Enum.map(&List.to_tuple/1)
    |> List.to_tuple()
  end

  @doc "Move the frame in hand `dx` right and `dy` down, what leaves the picture lost and what comes in transparent."
  @spec shift(t(), integer(), integer()) :: t()
  def shift(%__MODULE__{} = easel, dx, dy) do
    commit(easel, update_frame(easel, &shifted(easel, &1, {dx, dy})))
  end

  defp shifted(easel, frame, {dx, dy}) do
    build(easel.width, easel.height, fn {x, y} ->
      key_or_transparent(easel, frame, {x - dx, y - dy})
    end)
  end

  defp key_or_transparent(easel, frame, {x, y}) do
    if inside?(easel, {x, y}), do: elem(elem(frame, y), x), else: @transparent
  end

  @doc "Add a transparent frame after the one in hand and take it in hand."
  @spec add_frame(t()) :: t()
  def add_frame(%__MODULE__{} = easel), do: insert_frame(easel, blank(easel.width, easel.height))

  @doc "Add a copy of the frame in hand after it and take it in hand."
  @spec duplicate_frame(t()) :: t()
  def duplicate_frame(%__MODULE__{} = easel),
    do: insert_frame(easel, Enum.at(easel.frames, easel.frame))

  defp insert_frame(easel, frame) do
    commit(easel, %{
      easel
      | frames: List.insert_at(easel.frames, easel.frame + 1, frame),
        frame: easel.frame + 1
    })
  end

  @doc "Drop the frame in hand; the last frame stays."
  @spec delete_frame(t()) :: t()
  def delete_frame(%__MODULE__{frames: [_only]} = easel), do: easel

  def delete_frame(%__MODULE__{} = easel) do
    frames = List.delete_at(easel.frames, easel.frame)
    commit(easel, %{easel | frames: frames, frame: min(easel.frame, length(frames) - 1)})
  end

  @doc "Move the frame at `from` to `to` and take it in hand."
  @spec move_frame(t(), non_neg_integer(), non_neg_integer()) :: t()
  def move_frame(%__MODULE__{} = easel, from, to) do
    count = length(easel.frames)

    if from < count and to < count and from != to do
      {frame, rest} = List.pop_at(easel.frames, from)
      commit(easel, %{easel | frames: List.insert_at(rest, to, frame), frame: to})
    else
      easel
    end
  end

  @doc "Take frame `index` in hand; an index the frames lack changes nothing. Not undone."
  @spec select_frame(t(), non_neg_integer()) :: t()
  def select_frame(%__MODULE__{} = easel, index) do
    if index >= 0 and index < length(easel.frames), do: %{easel | frame: index}, else: easel
  end

  @doc "Set the frames a second."
  @spec set_fps(t(), pos_integer()) :: t()
  def set_fps(%__MODULE__{} = easel, fps) when fps > 0, do: commit(easel, %{easel | fps: fps})

  @doc "Back one change; nothing when there is none."
  @spec undo(t()) :: t()
  def undo(%__MODULE__{undo: []} = easel), do: easel

  def undo(%__MODULE__{undo: [previous | rest]} = easel) do
    %{restore(easel, previous) | undo: rest, redo: [snapshot(easel) | easel.redo]}
  end

  @doc "Forward one undone change; nothing when there is none."
  @spec redo(t()) :: t()
  def redo(%__MODULE__{redo: []} = easel), do: easel

  def redo(%__MODULE__{redo: [next | rest]} = easel) do
    %{restore(easel, next) | redo: rest, undo: [snapshot(easel) | easel.undo]}
  end

  defp snapshot(easel), do: Map.take(easel, [:palette, :width, :height, :frames, :frame, :fps])
  defp restore(easel, saved), do: Map.merge(easel, saved)

  defp commit(easel, changed) do
    if snapshot(%{changed | frame: easel.frame}) == snapshot(easel) and
         changed.frame == easel.frame do
      easel
    else
      %{changed | undo: [snapshot(easel) | easel.undo], redo: []}
    end
  end

  @doc "Frame `index` as a raster."
  @spec raster(t(), non_neg_integer()) :: Raster.t()
  def raster(%__MODULE__{} = easel, index) do
    Linocut.sprite(picture_text(Enum.at(easel.frames, index)), easel.palette)
  end

  @doc "Every frame as a raster."
  @spec rasters(t()) :: [Raster.t()]
  def rasters(%__MODULE__{} = easel),
    do: for(index <- 0..(length(easel.frames) - 1), do: raster(easel, index))

  @doc "The frames side by side as one raster."
  @spec strip(t()) :: Raster.t()
  def strip(%__MODULE__{} = easel) do
    {:ok, raster} = easel |> to_pic() |> Pic.parse()
    raster
  end

  @doc "The document as `.pic` text."
  @spec to_pic(t()) :: String.t()
  def to_pic(%__MODULE__{} = easel) do
    header = Enum.map_join(easel.palette, "\n", fn {key, colour} -> key <> " " <> hex(colour) end)

    header <>
      "\n\n" <>
      Enum.map_join(easel.frames, "\n" <> Pic.separator() <> "\n", &picture_text/1) <> "\n"
  end

  defp picture_text(frame),
    do: frame |> Tuple.to_list() |> Enum.map_join("\n", &Enum.join(Tuple.to_list(&1)))

  defp hex({r, g, b, 255}), do: "#" <> Base.encode16(<<r, g, b>>, case: :lower)
  defp hex({r, g, b, a}), do: "#" <> Base.encode16(<<r, g, b, a>>, case: :lower)

  @doc "A document from `.pic` text."
  @spec from_pic(String.t()) :: {:ok, t()} | {:error, term()}
  def from_pic(text) do
    case String.split(text, ~r/\r?\n\s*\r?\n/, parts: 2) do
      [header, pictures] ->
        with {:ok, palette} <- header_palette(header),
             {:ok, frames} <- frames_from_text(pictures) do
          {width, height} = {tuple_size(elem(hd(frames), 0)), tuple_size(hd(frames))}
          {:ok, %__MODULE__{width: width, height: height, frames: frames, palette: palette}}
        end

      _no_blank_line ->
        {:error, :no_picture}
    end
  end

  defp header_palette(header) do
    header
    |> String.split("\n")
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.reduce_while({:ok, []}, fn line, {:ok, acc} ->
      case String.split(String.trim(line), " ", parts: 2, trim: true) do
        [key, spec] -> {:cont, {:ok, acc ++ [{key, Palette.color(spec_term(spec))}]}}
        _other -> {:halt, {:error, {:palette_line, line}}}
      end
    end)
  rescue
    ArgumentError -> {:error, :colour}
  end

  defp spec_term("#" <> _ = hex), do: hex
  defp spec_term(name), do: Enum.find(Palette.names(), name, &(Atom.to_string(&1) == name))

  defp frames_from_text(pictures) do
    frames =
      pictures
      |> String.split(~r/\r?\n#{Pic.separator()}\r?\n/)
      |> Enum.map(fn picture ->
        picture |> String.split("\n") |> Enum.reject(&(&1 == "")) |> Enum.map(&String.graphemes/1)
      end)

    width = frames |> Enum.concat() |> Enum.map(&length/1) |> Enum.max(fn -> 0 end)
    height = frames |> Enum.map(&length/1) |> Enum.max(fn -> 0 end)

    if width == 0 or height == 0 do
      {:error, :empty}
    else
      {:ok, Enum.map(frames, &fit(&1, width, height))}
    end
  end

  defp fit(rows, width, height) do
    rows
    |> Enum.map(fn row ->
      (row ++ List.duplicate(@transparent, width - length(row))) |> List.to_tuple()
    end)
    |> Kernel.++(
      List.duplicate(
        List.duplicate(@transparent, width) |> List.to_tuple(),
        height - length(rows)
      )
    )
    |> List.to_tuple()
  end

  @doc "The document as a PNG of its frames side by side."
  @spec to_png(t()) :: binary()
  def to_png(%__MODULE__{} = easel) do
    raster = strip(easel)
    Png.encode(raster.width, raster.height, Raster.to_rgba_binary(raster))
  end

  @doc """
  A document from a PNG, every distinct opaque colour given a key.

  `frame: {width, height}` cuts the picture into frames of that size, left to right;
  without it the picture is one frame. More colours than there are keys is
  `{:error, {:too_many_colours, count}}`.
  """
  @spec from_png(binary(), keyword()) :: {:ok, t()} | {:error, term()}
  def from_png(bytes, opts \\ []) do
    with {:ok, raster} <- Linocut.Png.decode(bytes) do
      rasters = frames_of(raster, Keyword.get(opts, :frame))

      colours =
        rasters
        |> Enum.flat_map(&List.flatten(Raster.rows(&1)))
        |> Enum.reject(&(elem(&1, 3) == 0))
        |> Enum.uniq()

      if length(colours) > length(@keys),
        do: {:error, {:too_many_colours, length(colours)}},
        else: {:ok, keyed_document(rasters, colours)}
    end
  end

  defp keyed_document(rasters, colours) do
    palette = Enum.zip(@keys, colours)
    by_colour = Map.new(palette, fn {key, colour} -> {colour, key} end)
    {width, height} = Raster.dimensions(hd(rasters))

    %__MODULE__{
      width: width,
      height: height,
      frames: Enum.map(rasters, &keyed(&1, by_colour)),
      palette: palette
    }
  end

  defp frames_of(raster, nil), do: [raster]
  defp frames_of(raster, {width, height}), do: Linocut.frames(raster, {width, height})

  defp keyed(raster, by_colour) do
    raster
    |> Raster.rows()
    |> Enum.map(fn row -> row |> Enum.map(&key_of(&1, by_colour)) |> List.to_tuple() end)
    |> List.to_tuple()
  end

  defp key_of({_r, _g, _b, 0}, _by_colour), do: @transparent
  defp key_of(colour, by_colour), do: Map.fetch!(by_colour, colour)

  @doc "A document from a `.pic` or `.png` file; `from_png/2`'s options apply to a png."
  @spec load(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def load(path, opts \\ []) do
    case Path.extname(path) do
      ".pic" -> with {:ok, text} <- File.read(path), do: from_pic(text)
      ".png" -> with {:ok, bytes} <- File.read(path), do: from_png(bytes, opts)
      other -> {:error, {:unknown_format, other}}
    end
  end

  @doc "Write the document as `.pic` or `.png`, by the path's extension."
  @spec save(t(), Path.t()) :: :ok | {:error, term()}
  def save(%__MODULE__{} = easel, path) do
    case Path.extname(path) do
      ".pic" -> File.write(path, to_pic(easel))
      ".png" -> File.write(path, to_png(easel))
      other -> {:error, {:unknown_format, other}}
    end
  end
end
