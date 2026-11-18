defmodule Cauldron.Palette do
  @moduledoc """
  The colours a hud may name (`Cauldron.Client.Hud`), such as `%{fg: :yellow}`, as RGB.
  They are the names 2D pictures take too (`Cauldron2D.Palette`), so a hud reads the same
  over any drawer.

      Cauldron.Client.Hud.colour({"Score", %{fg: :yellow}}, &Cauldron.Palette.rgb/1)
  """

  @names %{
    black: {0, 0, 0},
    white: {255, 255, 255},
    red: {255, 0, 0},
    green: {0, 255, 0},
    blue: {0, 0, 255},
    yellow: {255, 255, 0},
    cyan: {0, 255, 255},
    magenta: {255, 0, 255},
    orange: {255, 165, 0},
    purple: {128, 0, 128},
    pink: {255, 105, 180},
    brown: {139, 69, 19},
    gray: {128, 128, 128},
    grey: {128, 128, 128},
    silver: {192, 192, 192},
    gold: {255, 215, 0},
    navy: {0, 0, 128},
    teal: {0, 128, 128},
    olive: {128, 128, 0},
    maroon: {128, 0, 0},
    lime: {50, 205, 50},
    sky: {135, 206, 235}
  }

  @doc "Every colour name."
  @spec names() :: [atom()]
  def names, do: Map.keys(@names)

  @doc "The colour `name` as `{r, g, b}`, or `nil` for a name the palette does not have."
  @spec rgb(atom()) :: {byte(), byte(), byte()} | nil
  def rgb(name), do: Map.get(@names, name)
end
