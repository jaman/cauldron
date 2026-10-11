defmodule Cauldron2D.GameMaker.General do
  @moduledoc """
  The `GEN8` chunk: what the game is called, the window it opens, the order of its rooms,
  and which generation of GameMaker built it.

  `format` is what every other reader branches on:

    * `:gms1` — GameMaker: Studio 1, whose rooms have backgrounds and tiles
    * `:gms2` — GameMaker Studio 2 before 2.3, whose rooms have layers
    * `:gms2_3` — 2.3 and after, which adds sequences to rooms and scripts as functions

  `bytecode` is the version of the compiled code the file was written for, and
  `steam_app_id` is `0` for a game not on Steam.
  """

  alias Cauldron2D.GameMaker.Bytes
  alias Cauldron2D.GameMaker.Chunks

  @enforce_keys [:format, :bytecode, :name, :display_name, :version, :window, :room_order]
  defstruct [
    :format,
    :bytecode,
    :name,
    :display_name,
    :file_name,
    :config,
    :version,
    :window,
    :room_order,
    :steam_app_id,
    :fps
  ]

  @type format :: :gms1 | :gms2 | :gms2_3
  @type t :: %__MODULE__{
          format: format(),
          bytecode: non_neg_integer(),
          name: String.t(),
          display_name: String.t(),
          file_name: String.t() | nil,
          config: String.t() | nil,
          version: {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()},
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

    %__MODULE__{
      format: format,
      bytecode: bytecode,
      file_name: Bytes.string_at(data, at + 4),
      config: Bytes.string_at(data, at + 8),
      name: Bytes.string_at(data, at + 40),
      display_name: Bytes.string_at(data, at + 100),
      version: {major, minor, release, build},
      window: {width, height},
      steam_app_id: Bytes.u32(data, at + 120),
      room_order: Bytes.u32s(data, at + 132, rooms),
      fps: fps(format, data, at + 132 + rooms * 4)
    }
  end

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
