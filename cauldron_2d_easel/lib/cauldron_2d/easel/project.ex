defmodule Cauldron2D.Easel.Project do
  @moduledoc """
  An art directory as an editor sees it: the pictures in it, the manifest beside them
  (`Cauldron2D.Atlas.Manifest`), and the atlas they make.

      project = Cauldron2D.Easel.Project.open("priv/art", tile: 16)
      Cauldron2D.Easel.Project.arts(project)
      {:ok, easel} = Cauldron2D.Easel.Project.load(project, :ship)
      {:ok, project} = Cauldron2D.Easel.Project.save(project, :ship, easel)
      {:ok, :my_game} = Cauldron2D.Easel.Project.install(project, :my_game)

  Every art is a `.pic` or `.png` file named for it, or a line in the manifest deriving
  it from another (`derive/3`, as `Linocut.Derive` reads the line); `save/3` writes
  `.pic`, keeping a `.png` that was there. `install/2` builds the atlas with
  `Cauldron2D.Atlas.load/3` and installs it, so a running game that subscribed to the
  atlas sees the change.
  """

  alias Cauldron2D.{Atlas, Easel}
  alias Cauldron2D.Atlas.Manifest
  alias Linocut.Derive

  @type t :: %__MODULE__{
          dir: Path.t(),
          tile: pos_integer(),
          void: Atlas.rgb(),
          manifest: Manifest.t()
        }

  @enforce_keys [:dir, :tile]
  defstruct [:dir, :tile, void: {0, 0, 0}, manifest: %{}]

  @doc "The project in `dir`; `:tile` (required) and `:void` as `Cauldron2D.Atlas.new/2` takes them."
  @spec open(Path.t(), keyword()) :: t()
  def open(dir, opts) do
    %__MODULE__{
      dir: dir,
      tile: Keyword.fetch!(opts, :tile),
      void: Keyword.get(opts, :void, {0, 0, 0}),
      manifest: Manifest.read(dir)
    }
  end

  @doc """
  Every art, by name, with how many frames it has: those drawn, each with its `:file`,
  then those derived, each with its `:derived` line, in name order.
  """
  @spec arts(t()) :: [
          %{
            required(:name) => atom(),
            required(:frames) => non_neg_integer(),
            optional(:file) => String.t(),
            optional(:derived) => String.t()
          }
        ]
  def arts(%__MODULE__{} = project), do: drawn(project) ++ derived(project)

  defp drawn(%__MODULE__{dir: dir} = project) do
    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&(Path.extname(&1) in [".pic", ".png"]))
        |> Enum.sort()
        |> Enum.map(fn file ->
          %{
            name: file |> Path.rootname() |> String.to_atom(),
            file: file,
            frames: frames_in(project, file)
          }
        end)

      {:error, _} ->
        []
    end
  end

  defp derived(%__MODULE__{manifest: manifest} = project) do
    for {name, line} <- Manifest.derived(manifest) do
      frames =
        case derived_easel(project, name) do
          {:ok, easel} -> length(easel.frames)
          {:error, _} -> 0
        end

      %{name: name, derived: line, frames: frames}
    end
  end

  defp frames_in(project, file) do
    case Easel.load(Path.join(project.dir, file), frame: {project.tile, project.tile}) do
      {:ok, easel} -> length(easel.frames)
      {:error, _} -> 0
    end
  end

  @doc "The art `name` as an easel, a derived one built from its line."
  @spec load(t(), atom()) :: {:ok, Easel.t()} | {:error, term()}
  def load(%__MODULE__{} = project, name) do
    case Enum.find(arts(project), &(&1.name == name)) do
      nil ->
        {:error, :enoent}

      %{file: file} ->
        with {:ok, easel} <-
               Easel.load(Path.join(project.dir, file), frame: {project.tile, project.tile}),
             do: {:ok, %{easel | fps: Map.get(entry(project, name), :fps, easel.fps)}}

      %{derived: _line} ->
        with {:ok, easel} <- derived_easel(project, name),
             do: {:ok, %{easel | fps: Map.get(entry(project, name), :fps, easel.fps)}}
    end
  end

  defp derived_easel(%__MODULE__{manifest: manifest} = project, name) do
    with {:ok, text} <- Derive.derive(Map.fetch!(manifest, name).derive, lookup(project, [name])),
         do: Easel.from_pic(text)
  end

  defp lookup(%__MODULE__{dir: dir, manifest: manifest} = project, seen) do
    fn name ->
      path = Path.join(dir, name <> ".pic")
      art = String.to_atom(name)

      cond do
        art in seen ->
          {:error, "#{name} derives from itself by way of #{Enum.join(seen, ", ")}: a loop"}

        File.exists?(path) ->
          File.read(path)

        match?(%{derive: _}, Map.get(manifest, art)) ->
          Derive.derive(manifest[art].derive, lookup(project, [art | seen]))

        true ->
          :error
      end
    end
  end

  @doc """
  Make `name` a derived art: `line` as `Linocut.Derive` reads it, built once to prove it
  can be, then kept in the manifest. A name a drawn picture already has is refused.
  """
  @spec derive(t(), atom(), String.t()) :: {:ok, t()} | {:error, String.t() | term()}
  def derive(%__MODULE__{} = project, name, line) do
    if Enum.any?(drawn(project), &(&1.name == name)) do
      {:error, "#{name} is a picture already; a derived art needs a name of its own"}
    else
      with {:ok, _text} <- Derive.derive(line, lookup(project, [name])),
           manifest =
             Map.update(project.manifest, name, %{derive: line}, &Map.put(&1, :derive, line)),
           :ok <- Manifest.write(project.dir, manifest),
           do: {:ok, %{project | manifest: manifest}}
    end
  end

  @doc "Write `from` — drawn or derived — as the picture `to.pic`, a picture of its own."
  @spec clone(t(), atom(), atom()) :: {:ok, t()} | {:error, term()}
  def clone(%__MODULE__{} = project, from, to) do
    with {:ok, easel} <- load(project, from), do: save(project, to, easel)
  end

  @doc "A transparent easel at the project's tile size; `:palette` as `Cauldron2D.Easel.new/3` takes it."
  @spec new_art(t(), keyword()) :: Easel.t()
  def new_art(%__MODULE__{tile: tile}, opts \\ []), do: Easel.new(tile, tile, opts)

  @doc "Write `easel` as `<name>.pic`, keeping its rate in the manifest."
  @spec save(t(), atom(), Easel.t()) :: {:ok, t()} | {:error, term()}
  def save(%__MODULE__{} = project, name, %Easel{} = easel) do
    with :ok <- Easel.save(easel, Path.join(project.dir, "#{name}.pic")) do
      put_entry(project, name, fps: easel.fps)
    end
  end

  @doc "The manifest's entry for `name`, `%{}` when it has none."
  @spec entry(t(), atom()) :: Manifest.entry()
  def entry(%__MODULE__{manifest: manifest}, name), do: Map.get(manifest, name, %{})

  @doc "Set `name`'s `:glyph`, `:color` and `:fps` in the manifest and write it."
  @spec put_entry(t(), atom(), keyword()) :: {:ok, t()} | {:error, term()}
  def put_entry(%__MODULE__{} = project, name, fields) do
    entry =
      Map.merge(entry(project, name), fields |> Keyword.take([:glyph, :color, :fps]) |> Map.new())

    manifest = Map.put(project.manifest, name, entry)

    with :ok <- Manifest.write(project.dir, manifest), do: {:ok, %{project | manifest: manifest}}
  end

  @doc "Build the atlas from the directory and install it under `name`."
  @spec install(t(), Atlas.name()) :: {:ok, Atlas.name()} | {:error, term()}
  def install(%__MODULE__{} = project, name) do
    with {:ok, atlas} <- Atlas.load(name, project.dir, tile: project.tile, void: project.void) do
      {:ok, Atlas.install(atlas)}
    end
  end
end
