defmodule Cauldron2D.GameMaker.Options do
  @moduledoc """
  The game's options (the `OPTN` chunk): window and display settings and the
  constants the game was built with.

  `flags` is GameMaker's bit set of options (full screen, interpolate pixels, borderless
  window, show cursor, sizeable, …); `scale` is `-1` to keep the aspect ratio and `0` to
  stretch to the window. `constants` maps each constant's name to its text.

  `read/2` takes the layout whose first word is `0x80000000`, which both GameMaker
  Studio 1 and 2 write, and returns `{:error, :old_layout}` for the older layout.
  """

  alias Cauldron2D.GameMaker.Bytes

  @enforce_keys [:flags, :scale, :constants]
  defstruct [:flags, :scale, :window_colour, constants: %{}]

  @type t :: %__MODULE__{
          flags: non_neg_integer(),
          scale: integer(),
          window_colour: {byte(), byte(), byte(), byte()},
          constants: %{String.t() => String.t()}
        }

  @doc "The options at `at`."
  @spec read(binary(), non_neg_integer()) :: {:ok, t()} | {:error, :old_layout}
  def read(data, at) do
    case binary_part(data, at, 24) do
      <<0, 0, 0, 128, _::binary-4, flags::little-64, scale::little-signed-32, colour::little-32>> ->
        {:ok,
         %__MODULE__{
           flags: flags,
           scale: scale,
           window_colour: Bytes.colour(colour),
           constants: constants(data, at + 60)
         }}

      _ ->
        {:error, :old_layout}
    end
  end

  defp constants(data, at) do
    count = Bytes.u32(data, at)

    for index <- 0..(count - 1)//1, into: %{} do
      entry = at + 4 + index * 8
      {Bytes.string_at(data, entry), Bytes.string_at(data, entry + 4)}
    end
  end
end
