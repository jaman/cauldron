defmodule Cauldron.Client.View do
  @moduledoc """
  How a kind of game is drawn and looked at, for the client code every front end shares
  (`Cauldron.Client.Stage`, `Cauldron.Client.Party`, `Cauldron.Client.Controls`): the
  player's look (which projection, which way it faces, how it is tilted), how the look
  turns the player's input, the zoom steps, and the props a scene is drawn with.

  A game names its view with `c:Cauldron.Client.Game.view/0`; `cauldron_2d` implements
  one for tile worlds and 2D projections.

  A look is a map. Every view's look has `:mouse_look?`; the rest is the view's own, with
  any key of the game's own over it (`c:Cauldron.Client.Game.look/0`).

      view = Cauldron.Client.View.of(MyGame.Client)
      look = view.look(MyGame.Client)
      look = view.turn(look, 1)
      scene = MyGame.Client.scene(world_view, Cauldron.Client.View.given(look, menu, frame, options))
  """

  @type look :: %{required(:mouse_look?) => boolean(), optional(atom()) => term()}
  @type direction :: {number(), number()}

  @doc "The look `game` starts in: the view's defaults with the game's `look/0` over them."
  @callback look(game :: module()) :: look()

  @doc "The zoom a world opens at for `game`."
  @callback zoom(game :: module()) :: number()

  @doc "The zoom steps the player's zoom keys move through, for `game` seen with `look`."
  @callback zoom_levels(game :: module(), look()) :: [number()]

  @doc "The props `scene` is drawn with, seen with `look` at `zoom`; the view's own keyword list."
  @callback props(game :: module(), scene :: map(), look(), zoom :: number()) :: keyword()

  @doc "The look at its next projection."
  @callback cycle(look()) :: look()

  @doc "The look turned by `amount` steps."
  @callback turn(look(), amount :: number()) :: look()

  @doc "The look tilted by `amount` steps."
  @callback tilt(look(), amount :: number()) :: look()

  @doc "The look after the pointer moved `{dx, dy}` while turning it, in fractions of the picture's width and height."
  @callback dragged(look(), direction()) :: look()

  @doc "Whether a drag with the left button turns the view."
  @callback turns_with_pointer?(look()) :: boolean()

  @doc "The player's input (`Cauldron.Input.state/1`) as the world should see it for the look."
  @callback steered(read :: map(), look()) :: map()

  @doc "A direction on screen as a direction in the world."
  @callback world_direction(look(), direction()) :: direction()

  @doc "Whether a controller's right stick turns the view, rather than nudging the player's aim."
  @callback stick_turns?(look()) :: boolean()

  @doc "The view `game` names (`c:Cauldron.Client.Game.view/0`)."
  @spec of(module()) :: module()
  def of(game), do: game.view()

  @doc """
  The look as a scene is given it: with the game's open menu (`nil` for none), the menu's
  frame count and the player's game options.
  """
  @spec given(look(), term(), non_neg_integer(), map()) :: map()
  def given(look, menu, menu_frame, options),
    do: Map.merge(look, %{menu: menu, menu_frame: menu_frame, options: options})
end
