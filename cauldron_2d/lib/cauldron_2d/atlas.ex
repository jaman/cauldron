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

    * Every tile in one atlas is the same pixel size. `put/4` raises otherwise.
    * `install/1` must be called before any renderer refers to the atlas by name. It publishes
      the atlas to `:persistent_term` and creates the ETS table named by `cache/1`.
    * Functions taking an atlas accept either the name or the struct; `fetch/1` resolves both.

  A tint is a named function over RGBA. It is applied when a tile is composited, and the
  result is cached under the tint's name.

  An animated art has `frames` and an `fps`; `frame_at/3` is the frame showing at a time
  in milliseconds, and `sprite` is its first frame. Every reader that does not take a
  time draws the first frame.

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

  @type entry :: %{
          sprite: Sprite.t(),
          frames: [Sprite.t()],
          fps: pos_integer(),
          glyph: String.t(),
          color: rgb()
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

  Every raster must be exactly the atlas's tile size in both dimensions; `put/4` raises
  `ArgumentError` otherwise, and on an empty list.

  ## Options

    * `:glyph` — what a text renderer draws for this tile, two columns wide because a tile
      occupies two terminal cells across. Default `"??"`
    * `:color` — the glyph's `{r, g, b}` colour before tinting, default `{255, 0, 255}`
    * `:fps` — frames a second when `raster` is a list. Default `#{@default_fps}`
  """
  @spec put(t(), art(), Raster.t() | [Raster.t()], keyword()) :: t()
  def put(atlas, art, raster, opts \\ [])

  def put(%__MODULE__{} = atlas, art, %Raster{} = raster, opts),
    do: put(atlas, art, [raster], opts)

  def put(%__MODULE__{}, art, [], _opts),
    do: raise(ArgumentError, "#{inspect(art)} has no frames")

  def put(%__MODULE__{} = atlas, art, rasters, opts) when is_list(rasters) do
    frames = Enum.map(rasters, &frame(atlas, art, &1))

    entry = %{
      sprite: hd(frames),
      frames: frames,
      fps: Keyword.get(opts, :fps, @default_fps),
      glyph: Keyword.get(opts, :glyph, "??"),
      color: Keyword.get(opts, :color, {255, 0, 255})
    }

    %{atlas | entries: Map.put(atlas.entries, art, entry)}
  end

  defp frame(atlas, art, %Raster{} = raster) do
    {width, height} = Raster.dimensions(raster)

    unless width == atlas.tile and height == atlas.tile do
      raise ArgumentError,
            "#{inspect(art)} is #{width}×#{height}, but atlas #{inspect(atlas.name)} is " <>
              "#{atlas.tile}×#{atlas.tile}. One tile size per atlas; see the moduledoc."
    end

    Sprite.new(raster)
  end

  @doc """
  An atlas from every `.png` and `.pic` file in `dir`, each art named by its file.

  A picture exactly one tile square is that art. One wider than a tile, in whole tiles,
  is a strip of frames left to right. A `.pic` smaller than a tile is centred in one.
  Any other size is `{:error, {:art, file, :size}}`; a file that will not read is
  `{:error, {:art, file, reason}}`.

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
         {:ok, loaded} <- load_files(atlas, dir, files, per_art, fps) do
      load_derived(loaded, dir, Manifest.derived(manifest), per_art, fps)
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
             Linocut.Pic.frames(text, size: {atlas.tile, atlas.tile}) |> derived_frames(),
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

  defp derived_frames({:ok, frames}), do: {:ok, frames}

  defp derived_frames({:error, reason}),
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

    with {:ok, raster} <- Linocut.load(path, size: {atlas.tile, atlas.tile}),
         {:ok, frames} <- frames_of(raster, atlas.tile) do
      colour = Keyword.get_lazy(options, :color, fn -> mean_colour(hd(frames)) end)
      glyph = Keyword.get_lazy(options, :glyph, fn -> default_glyph(art) end)

      {:ok,
       put(atlas, art, frames, glyph: glyph, color: colour, fps: Keyword.get(options, :fps, fps))}
    end
  end

  defp frames_of(raster, tile) do
    case Raster.dimensions(raster) do
      {^tile, ^tile} -> {:ok, [raster]}
      {width, ^tile} when rem(width, tile) == 0 -> {:ok, Linocut.frames(raster, {tile, tile})}
      _other -> {:error, :size}
    end
  end

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

  @doc "Whether `art` has more than one frame."
  @spec animated?(t() | name(), art()) :: boolean()
  def animated?(atlas, art), do: match?(%{frames: [_, _ | _]}, entry(fetch(atlas), art))

  @doc "Which of `art`'s frames shows at `at_ms`; `0` for an art with one frame."
  @spec frame_index(t() | name(), art(), integer()) :: non_neg_integer()
  def frame_index(atlas, art, at_ms) do
    case entry(fetch(atlas), art) do
      %{frames: [_]} -> 0
      %{frames: frames, fps: fps} -> rem(div(max(at_ms, 0) * fps, 1000), length(frames))
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
  The name of the ETS table holding composited tiles for the atlas `name`.

  The table exists only after `install/1`.
  """
  @spec cache(name()) :: atom()
  def cache(name), do: :"cauldron_tiles_#{name}"

  defp key(name), do: {__MODULE__, name}
end
