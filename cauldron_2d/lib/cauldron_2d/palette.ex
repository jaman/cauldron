defmodule Cauldron2D.Palette do
  @moduledoc """
  Colour names as the 2D front ends draw them, as `{r, g, b}`: the names `names/0`
  lists. The lookup `Cauldron.Client.Hud.colour/2` takes for a hud's named colours, and
  the names a picture's palette (`Cauldron2D.Picture.sprite/3`) may use.

      Cauldron.Client.Hud.colour({"Score", %{fg: :yellow}}, &Cauldron2D.Palette.rgb/1)
      #=> {255, 255, 0}
  """

  @doc "Every colour name, such as `:white`, `:yellow` and `:sky`."
  @spec names() :: [atom()]
  def names, do: Linocut.Palette.names()

  @doc "The colour `name` as `{r, g, b}`."
  @spec rgb(atom()) :: {byte(), byte(), byte()}
  def rgb(name) do
    {r, g, b, _alpha} = Linocut.Palette.color(name)
    {r, g, b}
  end
end
