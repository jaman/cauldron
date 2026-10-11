defmodule Cauldron2D.GameMaker.Room.View do
  @moduledoc """
  A room's view: the rectangle `view` `{x, y, width, height}` of the room shown in the
  rectangle `port` `{x, y, width, height}` of the window. With `follow` set to an
  object index, the view keeps that object's instance at least `border` `{x, y}` pixels
  from its edges, moving at most `speed` `{x, y}` pixels a step, `-1` for no limit.
  """

  @enforce_keys [:enabled, :view, :port]
  defstruct [:enabled, :view, :port, :border, :speed, :follow]

  @type rectangle :: {integer(), integer(), integer(), integer()}
  @type t :: %__MODULE__{
          enabled: boolean(),
          view: rectangle(),
          port: rectangle(),
          border: {integer(), integer()},
          speed: {integer(), integer()},
          follow: non_neg_integer() | nil
        }

  @doc "The view at `at`."
  @spec read(binary(), non_neg_integer()) :: t()
  def read(data, at) do
    [enabled, vx, vy, vw, vh, px, py, pw, ph, bx, by, sx, sy, follow] =
      for <<value::little-signed-32 <- binary_part(data, at, 56)>>, do: value

    %__MODULE__{
      enabled: enabled != 0,
      view: {vx, vy, vw, vh},
      port: {px, py, pw, ph},
      border: {bx, by},
      speed: {sx, sy},
      follow: if(follow >= 0, do: follow)
    }
  end
end
