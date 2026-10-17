defmodule Cauldron2D.GameMaker.Sound do
  @moduledoc """
  A sound (a `SOND` entry).

  `audio` is the index of the sound's bytes in the `AUDO` chunk of its audio group's
  file, `nil` when the sound is a file of its own beside the game, named `file`. Group
  `0` is the main data file; group `n` is `audiogroupn.dat` beside it. `volume` is
  `0.0`–`1.0`. `length` is the sound's duration in seconds in files written by
  GameMaker 2024.6 or later, `nil` in older ones.
  """

  alias Cauldron2D.GameMaker.Bytes
  alias Cauldron2D.GameMaker.General

  @enforce_keys [:name, :file, :audio]
  defstruct [:name, :file, :kind, :volume, :pitch, :group, :audio, :flags, :length]

  @type t :: %__MODULE__{
          name: String.t(),
          file: String.t() | nil,
          kind: String.t() | nil,
          volume: number(),
          pitch: number(),
          group: non_neg_integer(),
          audio: non_neg_integer() | nil,
          flags: non_neg_integer(),
          length: number() | nil
        }

  @embedded 0x1

  @doc "The sound at `at`."
  @spec read(binary(), non_neg_integer(), General.t()) :: t()
  def read(data, at, %General{} = general) do
    <<_name::little-32, flags::little-32, _kind::little-32, _file::little-32, _effects::little-32,
      volume::binary-4, pitch::binary-4, group::little-signed-32, audio::little-signed-32>> =
      binary_part(data, at, 36)

    %__MODULE__{
      name: Bytes.string_at(data, at),
      kind: Bytes.string_at(data, at + 8),
      file: Bytes.string_at(data, at + 12),
      flags: flags,
      volume: Bytes.float(volume),
      pitch: Bytes.float(pitch),
      group: max(group, 0),
      audio: if(Bitwise.band(flags, @embedded) != 0 and audio >= 0, do: audio),
      length: audio_length(data, at, general)
    }
  end

  @doc "Every stored sound in the `AUDO` chunk at `at`, as the bytes of a WAVE or Ogg file."
  @spec audio(binary(), non_neg_integer()) :: [binary()]
  def audio(data, at) do
    for pointer <- Bytes.pointers(data, at),
        do: binary_part(data, pointer + 4, Bytes.u32(data, pointer))
  end

  defp audio_length(data, at, general) do
    if General.at_least?(general, 2024, 6), do: Bytes.f32(data, at + 36)
  end
end
