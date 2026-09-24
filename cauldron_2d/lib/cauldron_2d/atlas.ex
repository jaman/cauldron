defmodule Cauldron2D.Atlas do
  @moduledoc """
  A named catalogue of tiles.

  Each entry holds a sprite — or a run of frames shown in turn — a glyph and a colour,
  which are what the pixel renderer and the text renderer respectively draw.

      Cauldron2D.Atlas.new(:my_game, tile: 16, void: {6, 7, 11})
      |> Cauldron2D.Atlas.put(:floor, floor_raster(), glyph: "· ", color: {60, 66, 88})
      |> Cauldron2D.Atlas.put(:player, player_raster(), glyph: "@ ", color: {245, 235, 200})
      |> Cauldron2D.Atlas.put(:torch, [flame_1(), flame_2(), flame_3()], fps: 8, glyph: "i ")
      |> Cauldron2D.Atlas.tint(:dim, fn {r, g, b, a} -> {div(r, 3), div(g, 3), div(b, 3), a} end)
      |> Cauldron2D.Atlas.install()

  Or from a directory of pictures:

      {:ok, atlas} = Cauldron2D.Atlas.load(:my_game, "priv/art", tile: 16, arts: [floor: [glyph: "· "]])
      Cauldron2D.Atlas.install(atlas)

  Rules a caller must respect:

    * Every base tile in one atlas is the atlas's tile size, as is every face; an overlay
      or a mover may be any size, all its frames alike, and stands on its tile. `put/4`
      raises on frames that disagree or a face that is not a tile.
    * `install/1` must be called before any renderer refers to the atlas by name. It publishes
      the atlas to `:persistent_term` and creates the ETS table named by `cache/1`.
    * Functions taking an atlas accept either the name or the struct; `fetch/1` resolves both.

  A tint is a named function over RGBA. It is applied when a tile is composited, and the
  result is cached under the tint's name.

  An animated art has `frames` and an `fps`; `frame_at/3` is the frame showing at a time
  in milliseconds, and `sprite` is its first frame. Every reader that does not take a
  time draws the first frame.

  An art may stand up: `height:` storeys tall with `faces:` for its top and sides, which
  the isometric and first-person projections draw as a block; and a mover may have
  `poses:`, pictures for the ways it can face the camera. `face/3` and `pose/4` read
  them, falling back to the art's own picture.

  `subscribe/1` delivers `{:cauldron_atlas, name, :changed}` to the calling process each
  time a different atlas is installed under `name`, including the first.
  """

  alias Cauldron2D.Atlas.{Manifest, Tables}
  alias FrenchCurve.{Raster, Sprite}

  @type name :: atom()
  @type art :: term()
  @type tint :: atom()
  @type rgb :: {0..255, 0..255, 0..255}
  @type rgba :: {0..255, 0..255, 0..255, 0..255}

  @type face :: :top | :side | :north | :east | :south | :west
  @type pose :: :front | :back | :side

  @type entry :: %{
          sprite: Sprite.t(),
          frames: [Sprite.t()],
          fps: pos_integer(),
          glyph: String.t(),
          color: rgb(),
          size: {pos_integer(), pos_integer()},
          height: non_neg_integer(),
          faces: %{face() => Sprite.t()},
          poses: %{pose() => [Sprite.t()]},
          stand: number() | nil,
          eye: number() | nil
        }

  @type t :: %__MODULE__{
          name: name(),
          tile: pos_integer(),
          void: rgb(),
          entries: %{art() => entry()},
          tints: %{tint() => (rgba() -> rgba())}
        }

  @enforce_keys [:name, :tile]
  defstruct [:name, :tile, void: {0, 0, 0}, entries: %{}, tints: %{}]

  @registry Cauldron2D.Atlas.Watch
  @default_fps 8
  @eye_height 0.9

  @doc false
  def child_spec(_opts), do: Registry.child_spec(keys: :duplicate, name: @registry)

  @doc """
  Start an empty atlas under `name`.

  ## Options

    * `:tile` — the pixel width and height of every tile, required
    * `:void` — the colour of a cell with nothing in it, default `{0, 0, 0}`

  Raises `ArgumentError` when `:tile` is missing or is not a positive integer.
  """
  @spec new(name(), keyword()) :: t()
  def new(name, opts) when is_atom(name) do
    tile = Keyword.fetch!(opts, :tile)

    unless is_integer(tile) and tile > 0 do
      raise ArgumentError, "tile size must be a positive integer, got: #{inspect(tile)}"
    end

    %__MODULE__{name: name, tile: tile, void: Keyword.get(opts, :void, {0, 0, 0})}
  end

  @doc """
  Add the tile `art`, drawn from `raster` — or from a list of rasters shown in turn —
  replacing any entry already under that name.

  A raster may be any size, every frame the same; a face must be the atlas's tile size.
  `put/4` raises `ArgumentError` otherwise, and on an empty list. An art larger than a
  tile can only be an overlay or a mover, never a cell's base.

  ## Options

    * `:glyph` — what a text renderer draws for this tile, two columns wide because a tile
      occupies two terminal cells across. Default `"??"`
    * `:color` — the glyph's `{r, g, b}` colour before tinting, default `{255, 0, 255}`
    * `:fps` — frames a second when `raster` is a list. Default `#{@default_fps}`
    * `:height` — how many storeys the art stands, `0` for something flat on the ground.
      Default `0`
    * `:faces` — `%{top: raster, side: raster}`, the pictures of a standing art's top and
      of each of its sides, either omitted, with `:north`, `:east`, `:south` or `:west`
      for one side that differs (`:north` faces `-y`); a face left out is the `:side`
      face, then the art's own picture. Default `%{}`
    * `:poses` — `%{front: raster | [raster], back: ..., side: ...}`, the pictures of a
      mover facing the camera, away from it, and across it (drawn mirrored for the other
      way); a pose left out is the art's own frames. Default `%{}`
    * `:stand` — how tall the art is in tiles when a projection draws it as a
      billboard, its width in proportion. Default `nil`: its picture's height over the
      tile size
    * `:eye` — how far above the ground the art looks from, in tiles, for a projection
      that puts the camera where it stands. Default `nil`: #{trunc(@eye_height * 100)}% of
      how tall it stands, so a taller art sees further over the world and a shorter one
      sees less
  """
  @spec put(t(), art(), Raster.t() | [Raster.t()], keyword()) :: t()
  def put(atlas, art, raster, opts \\ [])

  def put(%__MODULE__{} = atlas, art, %Raster{} = raster, opts),
    do: put(atlas, art, [raster], opts)

  def put(%__MODULE__{}, art, [], _opts),
    do: raise(ArgumentError, "#{inspect(art)} has no frames")

  def put(%__MODULE__{} = atlas, art, rasters, opts) when is_list(rasters) do
    frames = Enum.map(rasters, &frame(art, &1))
    size = Raster.dimensions(hd(rasters))
    Enum.each(frames, &same_size!(art, &1, size))

    entry = %{
      sprite: hd(frames),
      frames: frames,
      size: size,
      fps: Keyword.get(opts, :fps, @default_fps),
      glyph: Keyword.get(opts, :glyph, "??"),
      color: Keyword.get(opts, :color, {255, 0, 255}),
      height: height(art, Keyword.get(opts, :height, 0)),
      faces: faces(atlas, art, Keyword.get(opts, :faces, %{})),
      poses: poses(atlas, art, Keyword.get(opts, :poses, %{})),
      stand: stand(art, Keyword.get(opts, :stand)),
      eye: eye(art, Keyword.get(opts, :eye))
    }

    %{atlas | entries: Map.put(atlas.entries, art, entry)}
  end

  defp stand(_art, nil), do: nil
  defp stand(_art, tiles) when is_number(tiles) and tiles > 0, do: tiles

  defp stand(art, tiles) do
    raise ArgumentError, "#{inspect(art)} stand must be a height in tiles, got: #{inspect(tiles)}"
  end

  defp eye(_art, nil), do: nil
  defp eye(_art, tiles) when is_number(tiles) and tiles > 0, do: tiles

  defp eye(art, tiles) do
    raise ArgumentError, "#{inspect(art)} eye must be a height in tiles, got: #{inspect(tiles)}"
  end

  defp height(_art, storeys) when is_integer(storeys) and storeys >= 0, do: storeys

  defp height(art, storeys) do
    raise ArgumentError,
          "#{inspect(art)} height must be a whole number of storeys, got: #{inspect(storeys)}"
  end

  defp faces(atlas, art, faces),
    do: Map.new(faces, fn {face, raster} -> {face, tile_frame(atlas, art, raster)} end)

  defp poses(_atlas, art, poses),
    do: Map.new(poses, fn {pose, rasters} -> {pose, pose_frames(art, rasters)} end)

  defp pose_frames(art, %Raster{} = raster), do: [frame(art, raster)]
  defp pose_frames(art, rasters) when is_list(rasters), do: Enum.map(rasters, &frame(art, &1))

  defp same_size!(_art, %Sprite{width: width, height: height}, {width, height}), do: :ok

  defp same_size!(art, %Sprite{width: width, height: height}, {w, h}) do
    raise ArgumentError,
          "#{inspect(art)} has a frame of #{width}×#{height} among frames of #{w}×#{h}; " <>
            "every frame of an art is the same size"
  end

  @doc """
  The picture of `art`'s `face`: `:top`, `:side`, or a compass side, which falls back to
  `:side`; any face the art has no picture for is its own picture.
  """
  @spec face(t() | name(), art(), face()) :: Sprite.t()
  def face(atlas, art, face) do
    entry = entry(fetch(atlas), art)
    Map.get(entry.faces, face) || Map.get(entry.faces, :side) || entry.sprite
  end

  @doc """
  The frame of `art` showing at `at_ms` in `pose`, `:front`, `:back` or `:side`, or of
  its own frames when it has no such pose.
  """
  @spec pose(t() | name(), art(), pose(), integer()) :: Sprite.t()
  def pose(atlas, art, pose, at_ms) do
    entry = entry(fetch(atlas), art)
    frames = Map.get(entry.poses, pose, entry.frames)
    Enum.at(frames, Integer.mod(Integer.floor_div(at_ms * entry.fps, 1000), length(frames)))
  end

  defp frame(art, %Raster{} = raster) do
    {width, height} = Raster.dimensions(raster)

    if width < 1 or height < 1,
      do: raise(ArgumentError, "#{inspect(art)} has an empty picture")

    Sprite.new(raster)
  end

  defp tile_frame(atlas, art, %Raster{} = raster) do
    {width, height} = Raster.dimensions(raster)

    unless width == atlas.tile and height == atlas.tile do
      raise ArgumentError,
            "#{inspect(art)} has a face of #{width}×#{height}, but atlas " <>
              "#{inspect(atlas.name)} is #{atlas.tile}×#{atlas.tile}; a face is a tile"
    end

    Sprite.new(raster)
  end

  @doc """
  An atlas from every `.png` and `.pic` file in `dir`, each art named by its file.

  A `.pic` gives its frames as it draws them, at their own size; one smaller than a tile
  is centred in one. A `.png` exactly one tile square is that art; one wider than a
  tile, in whole tiles, is a strip of frames left to right; any other size is one art of
  that size. A file that will not read is `{:error, {:art, file, reason}}`.

  An `atlas.txt` in the directory (`Cauldron2D.Atlas.Manifest`) gives arts their glyph,
  colour and rate; `:arts` lays over it. The glyph of an art named nowhere is the first
  two characters of its name in capitals, and its colour the mean of its first frame's
  opaque pixels. An art the manifest derives from another (`Linocut.Derive`) is built
  after the pictures, from a `.pic` in the directory or another derived art; one that
  cannot be made is `{:error, {:art, name, message}}`.

  ## Options

    * `:tile` — as `new/2`, required
    * `:void` — as `new/2`
    * `:arts` — `[art: [glyph: "..", color: {r, g, b}, fps: n]]`, per-art options over
      the defaults. Default `[]`
    * `:fps` — the rate of every strip not given one in `:arts`. Default `#{@default_fps}`
  """
  @spec load(name(), Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def load(name, dir, opts) when is_atom(name) do
    atlas = new(name, Keyword.take(opts, [:tile, :void]))
    manifest = Manifest.read(dir)
    per_art = manifest |> Manifest.arts(Keyword.get(opts, :arts, [])) |> Map.new()
    fps = Keyword.get(opts, :fps, @default_fps)

    with {:ok, files} <- File.ls(dir),
         {:ok, loaded} <- load_files(atlas, dir, files, per_art, fps),
         {:ok, derived} <- load_derived(loaded, dir, Manifest.derived(manifest), per_art, fps) do
      load_solids(derived, per_art)
    end
  end

  defp load_solids(atlas, per_art) do
    Enum.reduce_while(per_art, {:ok, atlas}, fn {art, options}, {:ok, acc} ->
      case solid_options(acc, art, options) do
        {:ok, []} -> {:cont, {:ok, acc}}
        {:ok, solid} -> {:cont, {:ok, put_solid(acc, art, solid, per_art)}}
        {:error, message} -> {:halt, {:error, {:art, art, message}}}
      end
    end)
  end

  defp solid_options(atlas, art, options) do
    with {:ok, faces} <- named_sprites(atlas, Keyword.get(options, :faces, %{}), :sprite),
         {:ok, poses} <- named_sprites(atlas, Keyword.get(options, :poses, %{}), :frames) do
      solid =
        [
          height: Keyword.get(options, :height),
          faces: faces,
          poses: poses,
          stand: Keyword.get(options, :stand),
          eye: Keyword.get(options, :eye)
        ]
        |> Enum.reject(fn {_key, value} -> value in [nil, %{}] end)

      cond do
        solid == [] -> {:ok, []}
        Map.has_key?(atlas.entries, art) -> {:ok, solid}
        own_picture(faces, poses) != nil -> {:ok, solid}
        true -> {:error, "the manifest names an art the directory does not have"}
      end
    end
  end

  defp own_picture(faces, poses) do
    Map.get(faces, :side) || Map.get(faces, :top) || Map.get(poses, :front) ||
      poses |> Map.values() |> List.first()
  end

  defp named_sprites(atlas, names, what) do
    Enum.reduce_while(names, {:ok, %{}}, fn {key, named}, {:ok, acc} ->
      case Map.fetch(atlas.entries, named) do
        {:ok, %{sprite: sprite}} when what == :sprite ->
          {:cont, {:ok, Map.put(acc, key, sprite.raster)}}

        {:ok, %{frames: frames}} ->
          {:cont, {:ok, Map.put(acc, key, Enum.map(frames, & &1.raster))}}

        :error ->
          {:halt, {:error, "#{key} names #{inspect(named)}, which the directory does not have"}}
      end
    end)
  end

  defp put_solid(atlas, art, solid, per_art) do
    case Map.fetch(atlas.entries, art) do
      {:ok, entry} ->
        put(
          atlas,
          art,
          Enum.map(entry.frames, & &1.raster),
          [glyph: entry.glyph, color: entry.color, fps: entry.fps] ++ solid
        )

      :error ->
        picture = own_picture(Keyword.get(solid, :faces, %{}), Keyword.get(solid, :poses, %{}))
        first = if is_list(picture), do: hd(picture), else: picture
        options = Map.get(per_art, art, [])

        put(
          atlas,
          art,
          picture,
          [
            glyph: Keyword.get_lazy(options, :glyph, fn -> default_glyph(art) end),
            color: Keyword.get_lazy(options, :color, fn -> mean_colour(first) end),
            fps: Keyword.get(options, :fps, @default_fps)
          ] ++ solid
        )
    end
  end

  defp load_files(atlas, dir, files, per_art, fps) do
    files
    |> Enum.filter(&(Path.extname(&1) in [".png", ".pic"]))
    |> Enum.sort()
    |> Enum.reduce_while({:ok, atlas}, fn file, {:ok, acc} ->
      load_next(acc, dir, file, per_art, fps)
    end)
  end

  defp load_derived(atlas, dir, derived, per_art, fps) do
    lookup = derive_lookup(dir, Map.new(derived))

    Enum.reduce_while(derived, {:ok, atlas}, fn {art, _line}, {:ok, acc} ->
      with {:ok, text} <- lookup.(Atom.to_string(art), []) |> derived_text(),
           {:ok, frames} <-
             Linocut.Pic.frames(text) |> derived_frames(atlas.tile),
           {:ok, put} <- put_derived(acc, art, frames, per_art, fps) do
        {:cont, {:ok, put}}
      else
        {:error, message} -> {:halt, {:error, {:art, art, message}}}
      end
    end)
  end

  defp derive_lookup(dir, derived) do
    fn name, seen ->
      path = Path.join(dir, name <> ".pic")

      cond do
        name in seen ->
          {:error, "#{name} derives from itself by way of #{Enum.join(seen, ", ")}: a loop"}

        File.exists?(path) ->
          File.read(path)

        Map.has_key?(derived, String.to_atom(name)) ->
          derive(derived, name, [name | seen], dir)

        true ->
          :error
      end
    end
  end

  defp derive(derived, name, seen, dir) do
    lookup = derive_lookup(dir, derived)
    Linocut.Derive.derive(Map.fetch!(derived, String.to_atom(name)), &lookup.(&1, seen))
  end

  defp derived_text({:ok, text}), do: {:ok, text}
  defp derived_text({:error, message}) when is_binary(message), do: {:error, message}
  defp derived_text({:error, reason}), do: {:error, inspect(reason)}
  defp derived_text(:error), do: {:error, "no picture to derive from"}

  defp derived_frames({:ok, frames}, tile), do: {:ok, Enum.map(frames, &fitted(&1, tile))}

  defp derived_frames({:error, reason}, _tile),
    do: {:error, "the derived picture cannot be read: #{inspect(reason)}"}

  defp put_derived(atlas, art, frames, per_art, fps) do
    options = Map.get(per_art, art, [])
    colour = Keyword.get_lazy(options, :color, fn -> mean_colour(hd(frames)) end)
    glyph = Keyword.get_lazy(options, :glyph, fn -> default_glyph(art) end)

    {:ok,
     put(atlas, art, frames, glyph: glyph, color: colour, fps: Keyword.get(options, :fps, fps))}
  rescue
    error in ArgumentError -> {:error, Exception.message(error)}
  end

  defp load_next(atlas, dir, file, per_art, fps) do
    case load_art(atlas, Path.join(dir, file), per_art, fps) do
      {:ok, loaded} -> {:cont, {:ok, loaded}}
      {:error, reason} -> {:halt, {:error, {:art, file, reason}}}
    end
  end

  defp load_art(atlas, path, per_art, fps) do
    art = path |> Path.basename() |> Path.rootname() |> String.to_atom()
    options = Map.get(per_art, art, [])

    with {:ok, frames} <- picture_frames(path, atlas.tile) do
      colour = Keyword.get_lazy(options, :color, fn -> mean_colour(hd(frames)) end)
      glyph = Keyword.get_lazy(options, :glyph, fn -> default_glyph(art) end)

      {:ok,
       put(atlas, art, frames, glyph: glyph, color: colour, fps: Keyword.get(options, :fps, fps))}
    end
  end

  defp picture_frames(path, tile) do
    case Path.extname(path) do
      ".pic" ->
        with {:ok, text} <- File.read(path),
             {:ok, frames} <- Linocut.Pic.frames(text),
             do: {:ok, Enum.map(frames, &fitted(&1, tile))}

      _png ->
        with {:ok, raster} <- Linocut.load(path), do: frames_of(raster, tile)
    end
  end

  defp frames_of(raster, tile) do
    case Raster.dimensions(raster) do
      {^tile, ^tile} -> {:ok, [raster]}
      {width, ^tile} when rem(width, tile) == 0 -> {:ok, Linocut.frames(raster, {tile, tile})}
      _other -> {:ok, [fitted(raster, tile)]}
    end
  end

  defp fitted(%Raster{width: width, height: height} = raster, tile)
       when width <= tile and height <= tile and {width, height} != {tile, tile} do
    left = div(tile - width, 2)
    top = div(tile - height, 2)

    for y <- 0..(height - 1)//1, x <- 0..(width - 1)//1, reduce: Raster.new(tile, tile) do
      acc -> Raster.put_pixel(acc, left + x, top + y, Raster.get_pixel(raster, x, y))
    end
  end

  defp fitted(raster, _tile), do: raster

  defp default_glyph(art) do
    art |> Atom.to_string() |> String.upcase() |> String.pad_trailing(2) |> String.slice(0, 2)
  end

  defp mean_colour(raster) do
    opaque = for {_r, _g, _b, a} = pixel <- List.flatten(Raster.rows(raster)), a > 0, do: pixel

    case opaque do
      [] ->
        {0, 0, 0}

      pixels ->
        count = length(pixels)

        {r, g, b} =
          Enum.reduce(pixels, {0, 0, 0}, fn {r, g, b, _a}, {ar, ag, ab} ->
            {ar + r, ag + g, ab + b}
          end)

        {div(r, count), div(g, count), div(b, count)}
    end
  end

  @doc "Register `fun`, a function from an RGBA tuple to an RGBA tuple, under `name`."
  @spec tint(t(), tint(), (rgba() -> rgba())) :: t()
  def tint(%__MODULE__{} = atlas, name, fun) when is_atom(name) and is_function(fun, 1) do
    %{atlas | tints: Map.put(atlas.tints, name, fun)}
  end

  @doc """
  Publish the atlas to `:persistent_term` and create its composited-tile cache table.

  Idempotent, and safe to call again with a changed atlas. Installing the same atlas twice
  keeps every tile already composited. Installing a *different* one under the same name empties
  the cache first, so art or a tint that has been redefined is composited again rather than
  served as it used to look, and tells every subscriber of the name.

  The table itself is created once, owned by `Cauldron2D.Atlas.Tables` rather than the
  caller, and kept, so a reference taken from `cache/1` stays valid across re-installs and
  after the installing process has gone.

  Returns the atlas name.
  """
  @spec install(t()) :: name()
  def install(%__MODULE__{} = atlas) do
    previous = :persistent_term.get(key(atlas.name), nil)
    :persistent_term.put(key(atlas.name), atlas)

    table = Tables.ensure(cache(atlas.name))
    if previous != nil and previous != atlas, do: :ets.delete_all_objects(table)
    if previous != atlas, do: changed(atlas.name)
    atlas.name
  end

  @doc "Receive `{:cauldron_atlas, name, :changed}` in the calling process whenever a different atlas is installed under `name`."
  @spec subscribe(name()) :: :ok
  def subscribe(name) when is_atom(name) do
    Registry.register(@registry, name, nil)
    :ok
  end

  @doc "Stop receiving changes to `name`."
  @spec unsubscribe(name()) :: :ok
  def unsubscribe(name) when is_atom(name), do: Registry.unregister(@registry, name)

  defp changed(name) do
    Registry.dispatch(@registry, name, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:cauldron_atlas, name, :changed})
    end)
  end

  @doc """
  The atlas struct for `name`, or the struct itself when given one.

  Raises `ArgumentError` when nothing is installed under `name`.
  """
  @spec fetch(name() | t()) :: t()
  def fetch(%__MODULE__{} = atlas), do: atlas

  def fetch(name) when is_atom(name) do
    case :persistent_term.get(key(name), nil) do
      nil -> raise ArgumentError, "no atlas installed under #{inspect(name)}"
      atlas -> atlas
    end
  end

  @doc "Whether an atlas has been installed under this name."
  @spec installed?(name()) :: boolean()
  def installed?(name) when is_atom(name), do: :persistent_term.get(key(name), nil) != nil

  @doc """
  The `t:entry/0` stored under `art`.

  Raises `ArgumentError` when the atlas has no such art.
  """
  @spec entry(t(), art()) :: entry()
  def entry(%__MODULE__{} = atlas, art) do
    case Map.fetch(atlas.entries, art) do
      {:ok, entry} -> entry
      :error -> raise ArgumentError, "atlas #{inspect(atlas.name)} has no art #{inspect(art)}"
    end
  end

  @doc """
  How tall `art` stands, in tiles: its `:stand` where it has one, else its picture height
  over the tile size.
  """
  @spec standing(t(), art()) :: float()
  def standing(%__MODULE__{} = atlas, art) do
    entry = entry(atlas, art)
    entry.stand || elem(entry.size, 1) / atlas.tile
  end

  @doc """
  How far above the ground `art` looks from, in tiles: its `:eye` where it has one, else a
  fixed fraction of how tall it stands.
  """
  @spec eye_height(t(), art()) :: float()
  def eye_height(%__MODULE__{} = atlas, art) do
    entry(atlas, art).eye || standing(atlas, art) * @eye_height
  end

  @doc "Whether `art` has more than one frame."
  @spec animated?(t() | name(), art()) :: boolean()
  def animated?(atlas, art), do: match?(%{frames: [_, _ | _]}, entry(fetch(atlas), art))

  @doc "Which of `art`'s frames shows at `at_ms`; `0` for an art with one frame."
  @spec frame_index(t() | name(), art(), integer()) :: non_neg_integer()
  def frame_index(atlas, art, at_ms) do
    case entry(fetch(atlas), art) do
      %{frames: [_]} ->
        0

      %{frames: frames, fps: fps} ->
        Integer.mod(Integer.floor_div(at_ms * fps, 1000), length(frames))
    end
  end

  @doc "The sprite of `art` showing at `at_ms`."
  @spec frame_at(t() | name(), art(), integer()) :: Sprite.t()
  def frame_at(atlas, art, at_ms) do
    atlas = fetch(atlas)
    Enum.at(entry(atlas, art).frames, frame_index(atlas, art, at_ms))
  end

  @doc "Every art name in the atlas."
  @spec arts(t()) :: [art()]
  def arts(%__MODULE__{entries: entries}), do: Map.keys(entries)

  @doc """
  How tall the tallest art of the atlas stands, in pixels.

  Counts an art's own picture and its poses, so a mover drawn taller than a tile is
  included. A caller sizing a picture uses it to keep the tallest thing in view.
  """
  @spec tallest(t() | name()) :: pos_integer()
  def tallest(atlas) do
    atlas = fetch(atlas)
    table = cache(atlas.name)

    case :ets.lookup(table, {:tallest, atlas.name}) do
      [{_key, height}] -> height
      [] -> kept(table, atlas)
    end
  rescue
    ArgumentError -> measured(atlas)
  end

  defp kept(table, atlas) do
    height = measured(atlas)
    :ets.insert(table, {{:tallest, atlas.name}, height})
    height
  end

  defp measured(atlas) do
    atlas.entries
    |> Map.values()
    |> Enum.flat_map(
      &[elem(&1.size, 1) | Enum.map(Map.values(&1.poses), fn [first | _] -> first.height end)]
    )
    |> Enum.max(fn -> atlas.tile end)
  end

  @doc """
  The name of the ETS table holding composited tiles for the atlas `name`.

  The table exists only after `install/1`.
  """
  @spec cache(name()) :: atom()
  def cache(name), do: :"cauldron_tiles_#{name}"

  defp key(name), do: {__MODULE__, name}
end
