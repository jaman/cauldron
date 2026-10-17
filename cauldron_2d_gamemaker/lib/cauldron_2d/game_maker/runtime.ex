defmodule Cauldron2D.GameMaker.Runtime do
  @moduledoc """
  The GameMaker version that wrote a data file, and the release line it was built on.

  `detect/4` starts from the chunks a file has, then inspects the contents of its chunks
  in the order the chunks appear in the file. Each inspection looks for a layout that
  exists only from one version on, and raises the version when it finds it.

  A version is `{major, minor, release, build}`. Version 2.3.6 is `{2, 3, 6, 0}` and
  2024.13 is `{2024, 13, 0, 0}`. Game Maker Studio 1 files keep the `GEN8` version.

  `branch` is `:early` for files built before the 2022 line, `:lts` for the 2022
  long-term support line, and `:current` for the line that carries every later
  feature. A long-term support file lacks some features its version number would
  suggest, so `current_at_least?/5` is false for it.

  An inspection that points outside the file finds nothing and leaves the version as it
  was.
  """

  alias Cauldron2D.GameMaker.Bytes
  alias Cauldron2D.GameMaker.Chunks
  alias Cauldron2D.GameMaker.Runtime.Audio
  alias Cauldron2D.GameMaker.Runtime.Curves
  alias Cauldron2D.GameMaker.Runtime.Extensions
  alias Cauldron2D.GameMaker.Runtime.Fonts
  alias Cauldron2D.GameMaker.Runtime.Functions
  alias Cauldron2D.GameMaker.Runtime.Objects
  alias Cauldron2D.GameMaker.Runtime.Particles
  alias Cauldron2D.GameMaker.Runtime.Pictures
  alias Cauldron2D.GameMaker.Runtime.Rooms

  @enforce_keys [:version]
  defstruct [:version, branch: :early]

  @type version :: {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}
  @type branch :: :early | :lts | :current
  @type t :: %__MODULE__{version: version(), branch: branch()}
  @type context :: %{
          data: binary(),
          at: non_neg_integer(),
          size: non_neg_integer(),
          bytecode: non_neg_integer(),
          chunks: Chunks.t()
        }

  @markers [
    {"UILR", {2024, 13, 0, 0}, :current},
    {"PSEM", {2023, 2, 0, 0}, :current},
    {"FEAT", {2022, 8, 0, 0}, :early},
    {"FEDS", {2, 3, 6, 0}, :early},
    {"SEQN", {2, 3, 0, 0}, :early},
    {"TGIN", {2, 2, 1, 0}, :early}
  ]

  @pointer_lists ~w(EXTN SOND AGRP SPRT BGND PATH SCPT SHDR FONT TMLN OBJT ROOM UILR TPAG CODE)

  @doc """
  The runtime of the file in `data` whose chunks are `chunks`. `bytecode` and `version`
  are the file's `GEN8` bytecode version and version.
  """
  @spec detect(binary(), Chunks.t(), non_neg_integer(), version()) :: t()
  def detect(data, chunks, bytecode, version) do
    ordered = Enum.sort_by(chunks, fn {_name, {at, _size}} -> at end)
    names = Enum.map(ordered, fn {name, _place} -> name end)

    ordered
    |> Enum.reject(fn {_name, {_at, size}} -> size == 0 end)
    |> Enum.reduce(initial(version, names), fn {name, {at, size}}, runtime ->
      context = %{data: data, at: at, size: size, bytecode: bytecode, chunks: chunks}

      runtime
      |> guarded(&probe(&1, name, context))
      |> guarded(&removed_assets(&1, name, context))
    end)
    |> long_term_support()
  end

  @doc "Whether the runtime is the given version or a later one."
  @spec at_least?(t(), non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          boolean()
  def at_least?(%__MODULE__{version: version}, major, minor \\ 0, release \\ 0, build \\ 0),
    do: version >= {major, minor, release, build}

  @doc """
  Whether the runtime is the given version or a later one and is not on the long-term
  support line.
  """
  @spec current_at_least?(
          t(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: boolean()
  def current_at_least?(runtime, major, minor \\ 0, release \\ 0, build \\ 0)

  def current_at_least?(%__MODULE__{branch: :current} = runtime, major, minor, release, build),
    do: at_least?(runtime, major, minor, release, build)

  def current_at_least?(%__MODULE__{}, _major, _minor, _release, _build), do: false

  @doc "The runtime with its version replaced."
  @spec set(t(), non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          t()
  def set(%__MODULE__{} = runtime, major, minor \\ 0, release \\ 0, build \\ 0),
    do: %{runtime | version: {major, minor, release, build}}

  @doc "The runtime at the given version, unless it is already at or past it."
  @spec raise_to(
          t(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: t()
  def raise_to(%__MODULE__{} = runtime, major, minor \\ 0, release \\ 0, build \\ 0) do
    if at_least?(runtime, major, minor, release, build),
      do: runtime,
      else: set(runtime, major, minor, release, build)
  end

  @doc "Every offset in the pointer list at `at` that is not null."
  @spec live_pointers(binary(), non_neg_integer()) :: [pos_integer()]
  def live_pointers(data, at), do: data |> Bytes.pointers(at) |> Enum.reject(&(&1 == 0))

  @doc """
  Each non-null offset in `pointers` paired with the next non-null offset after it, `0`
  for the last.
  """
  @spec with_next([non_neg_integer()]) :: [{pos_integer(), non_neg_integer()}]
  def with_next(pointers) do
    live = Enum.reject(pointers, &(&1 == 0))
    Enum.zip(live, Enum.drop(live, 1) ++ [0])
  end

  defp initial(version, names) do
    case Enum.find(@markers, fn {name, _version, _branch} -> name in names end) do
      {_name, found, branch} -> %__MODULE__{version: found, branch: branch}
      nil -> %__MODULE__{version: version, branch: :early}
    end
  end

  defp long_term_support(%__MODULE__{branch: :early} = runtime) do
    if at_least?(runtime, 2023, 1), do: %{runtime | branch: :lts}, else: runtime
  end

  defp long_term_support(%__MODULE__{} = runtime), do: runtime

  defp guarded(runtime, inspect) do
    inspect.(runtime)
  rescue
    ArgumentError -> runtime
    MatchError -> runtime
  end

  defp probe(runtime, "EXTN", context), do: Extensions.probe(runtime, context)
  defp probe(runtime, "SOND", context), do: Audio.probe_sounds(runtime, context)
  defp probe(runtime, "AGRP", context), do: Audio.probe_groups(runtime, context)
  defp probe(runtime, "SPRT", context), do: Pictures.probe_sprites(runtime, context)
  defp probe(runtime, "BGND", context), do: Pictures.probe_backgrounds(runtime, context)
  defp probe(runtime, "FONT", context), do: Fonts.probe(runtime, context)
  defp probe(runtime, "OBJT", context), do: Objects.probe(runtime, context)
  defp probe(runtime, "ROOM", context), do: Rooms.probe(runtime, context)
  defp probe(runtime, "TXTR", context), do: Pictures.probe_textures(runtime, context)
  defp probe(runtime, "TGIN", context), do: Pictures.probe_groups(runtime, context)
  defp probe(runtime, "ACRV", context), do: Curves.probe(runtime, context)
  defp probe(runtime, "PSEM", context), do: Particles.probe(runtime, context)
  defp probe(runtime, "FUNC", context), do: Functions.probe(runtime, context)
  defp probe(runtime, _name, _context), do: runtime

  defp removed_assets(runtime, name, %{data: data, at: at}) when name in @pointer_lists do
    if at_least?(runtime, 2) and Enum.any?(Bytes.pointers(data, at), &(&1 == 0)),
      do: raise_to(runtime, 2024, 11),
      else: runtime
  end

  defp removed_assets(runtime, _name, _context), do: runtime
end
