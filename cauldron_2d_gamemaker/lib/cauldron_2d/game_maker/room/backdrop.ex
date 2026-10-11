defmodule Cauldron2D.GameMaker.Room.Backdrop do
  @moduledoc """
  One of a GameMaker Studio 1 room's eight backgrounds: background `background` drawn
  at `{x, y}`, behind everything or, with `foreground`, in front. `tiled` is
  `{across, down}`, repeating the picture across the room in each direction; `speed`
  `{x, y}` moves it by that many pixels a step; `stretch` scales it to the room.
  `background` is `-1` for an empty slot.
  """

  @enforce_keys [:enabled, :background, :position]
  defstruct [:enabled, :foreground, :background, :position, :tiled, :speed, :stretch]

  @type t :: %__MODULE__{
          enabled: boolean(),
          foreground: boolean(),
          background: integer(),
          position: {integer(), integer()},
          tiled: {boolean(), boolean()},
          speed: {integer(), integer()},
          stretch: boolean()
        }

  @doc "The backdrop at `at`."
  @spec read(binary(), non_neg_integer()) :: t()
  def read(data, at) do
    [enabled, foreground, background, x, y, across, down, speed_x, speed_y, stretch] =
      for <<value::little-signed-32 <- binary_part(data, at, 40)>>, do: value

    %__MODULE__{
      enabled: enabled != 0,
      foreground: foreground != 0,
      background: background,
      position: {x, y},
      tiled: {across != 0, down != 0},
      speed: {speed_x, speed_y},
      stretch: stretch != 0
    }
  end
end
