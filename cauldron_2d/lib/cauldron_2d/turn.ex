defmodule Cauldron2D.Turn do
  @moduledoc """
  The cosine and sine of an angle in degrees, exact for whole quarter turns so a
  picture or shape turned by 90, 180 or 270 degrees lands on the same pixels as one
  mirrored by hand.

      Cauldron2D.Turn.cos_sin(90)
      #=> {0, 1}
  """

  @doc "`{cos, sin}` of `degrees`."
  @spec cos_sin(number()) :: {number(), number()}
  def cos_sin(degrees) do
    quarters = degrees / 90

    if quarters == Float.round(quarters * 1.0),
      do: elem({{1, 0}, {0, 1}, {-1, 0}, {0, -1}}, Integer.mod(round(quarters), 4)),
      else: {:math.cos(degrees * :math.pi() / 180), :math.sin(degrees * :math.pi() / 180)}
  end
end
