defmodule Cauldron2D.GameMaker.General do
  @moduledoc """
  The `GEN8` chunk: what the game is called, the window it opens, the order of its rooms,
  and which generation of GameMaker built it.

  `format` is what every other reader branches on:

    * `:gms1` — GameMaker: Studio 1, whose rooms have backgrounds and tiles
    * `:gms2` — GameMaker Studio 2 before 2.3, whose rooms have layers
    * `:gms2_3` — 2.3 and after, which adds sequences to rooms and scripts as functions

  `runtime` is the GameMaker version that wrote the file, `{major, minor, release,
  build}`, so `{2024, 13, 0, 0}` is 2024.13. `Cauldron2D.GameMaker.Runtime` finds it
  from the shape of the file's chunks. It compares with the ordinary tuple operators,
  and `at_least?/5` asks it. `branch` is the release line: `:early`, `:lts` or
  `:current`. `version` is the version `GEN8` itself stores; files written by GameMaker 2 and later
  store `{2, 0, 0, 0}`.

  `bytecode` is the version of the compiled code the file was written for, and
  `steam_app_id` is `0` for a game not on Steam.
  """

  alias Cauldron2D.GameMaker.Bytes
  alias Cauldron2D.GameMaker.Chunks
  alias Cauldron2D.GameMaker.Runtime

  @enforce_keys [
    :format,
    :bytecode,
    :name,
    :display_name,
    :version,
    :runtime,
    :window,
    :room_order
  ]
  defstruct [
    :format,
    :bytecode,
    :name,
    :display_name,
    :file_name,
    :config,
    :version,
    :runtime,
    :window,
    :room_order,
    :steam_app_id,
    :fps,
    branch: :early
  ]

  @type format :: :gms1 | :gms2 | :gms2_3
  @type t :: %__MODULE__{
          format: format(),
          bytecode: non_neg_integer(),
          name: String.t(),
          display_name: String.t(),
          file_name: String.t() | nil,
          config: String.t() | nil,
          version: Runtime.version(),
          runtime: Runtime.version(),
          branch: Runtime.branch(),
          window: {non_neg_integer(), non_neg_integer()},
          room_order: [non_neg_integer()],
          steam_app_id: non_neg_integer(),
          fps: number() | nil
        }

  @doc "The `GEN8` chunk at `at`, its format told apart with the help of the file's chunks."
  @spec read(binary(), non_neg_integer(), Chunks.t()) :: t()
  def read(data, at, chunks) do
    <<_debugger, bytecode, _::binary-2>> = binary_part(data, at, 4)
    [major, minor, release, build, width, height] = Bytes.u32s(data, at + 44, 6)
    rooms = Bytes.u32(data, at + 128)
    format = format(major, chunks)
    runtime = Runtime.detect(data, chunks, bytecode, {major, minor, release, build})

    %__MODULE__{
      format: format,
      bytecode: bytecode,
      file_name: Bytes.string_at(data, at + 4),
      config: Bytes.string_at(data, at + 8),
      name: Bytes.string_at(data, at + 40),
      display_name: Bytes.string_at(data, at + 100),
      version: {major, minor, release, build},
      runtime: runtime.version,
      branch: runtime.branch,
      window: {width, height},
      steam_app_id: Bytes.u32(data, at + 120),
      room_order: Bytes.u32s(data, at + 132, rooms),
      fps: fps(format, data, at + 132 + rooms * 4)
    }
  end

  @doc "Whether the file was written by the given GameMaker version or a later one."
  @spec at_least?(
          t(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: boolean()
  def at_least?(%__MODULE__{} = general, major, minor \\ 0, release \\ 0, build \\ 0),
    do: Runtime.at_least?(as_runtime(general), major, minor, release, build)

  @doc """
  Whether the file was written by the given GameMaker version or a later one, on the
  `:current` release line.
  """
  @spec current_at_least?(
          t(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: boolean()
  def current_at_least?(%__MODULE__{} = general, major, minor \\ 0, release \\ 0, build \\ 0),
    do: Runtime.current_at_least?(as_runtime(general), major, minor, release, build)

  defp as_runtime(%__MODULE__{runtime: version, branch: branch}),
    do: %Runtime{version: version, branch: branch}

  defp format(major, _chunks) when major < 2, do: :gms1

  defp format(_major, chunks) do
    if Chunks.filled?(chunks, "SEQN") or Map.has_key?(chunks, "FEDS") or
         Map.has_key?(chunks, "TAGS"),
       do: :gms2_3,
       else: :gms2
  end

  defp fps(:gms1, _data, _at), do: nil
  defp fps(_format, data, at), do: Bytes.f32(data, at + 40)
end
