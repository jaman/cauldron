defmodule Cauldron2D.Client.View do
  @moduledoc """
  The `Cauldron.Client.View` of a 2D game: the look is a `Cauldron2D.Client.Look` (top
  down, oblique, isometric, mode 7 or first person), the zoom steps are
  `Cauldron2D.Draw.zoom_levels/3`'s for the game's atlas in the look's projection, and a
  scene is drawn with `Cauldron2D.Draw.props/4`. A game that `use`s
  `Cauldron2D.Client.Game` names it.
  """

  @behaviour Cauldron.Client.View

  alias Cauldron2D.Client.Look
  alias Cauldron2D.Draw

  @impl true
  defdelegate look(game), to: Look, as: :of

  @impl true
  defdelegate zoom(game), to: Look

  @impl true
  def zoom_levels(game, look), do: Draw.zoom_levels(game.atlas(), :kitty, look.projection)

  @impl true
  defdelegate props(game, scene, look, zoom), to: Draw

  @impl true
  defdelegate cycle(look), to: Look

  @impl true
  defdelegate turn(look, amount), to: Look

  @impl true
  defdelegate tilt(look, amount), to: Look

  @impl true
  defdelegate dragged(look, direction), to: Look

  @impl true
  defdelegate turns_with_pointer?(look), to: Look

  @impl true
  defdelegate steered(read, look), to: Look

  @impl true
  defdelegate world_direction(look, direction), to: Look

  @impl true
  def stick_turns?(%{projection: :first_person}), do: true
  def stick_turns?(_look), do: false
end
