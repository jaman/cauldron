defmodule Cauldron.Client.Menus do
  @moduledoc """
  A game's own menu (`c:Cauldron.Client.Game.open_menu/1` and
  `c:Cauldron.Client.Game.menu_event/3`) as every front end runs it: opened on the
  `menu` key, on a controller's `Start`, or when the world asks; fed every key press,
  mouse press and wheel notch while it is open; its frame counted up every
  `frame_ms/0` milliseconds so the scene draws its animations.

      menu = Cauldron.Client.Menus.open(MyGame.Client, settings)
      reply = Cauldron.Client.Menus.event(MyGame.Client, menu, {:key, :down}, settings)

  `event/4` answers the game's reply with `:menu` and `:settings` always present and
  `:sounds` (`[]` without), `:request` (`nil` without) and `:leave` (`false` without).
  """

  @frame_ms 100

  @doc "How often an open menu's frame counts up, in milliseconds."
  @spec frame_ms() :: pos_integer()
  def frame_ms, do: @frame_ms

  @doc "Whether `game` has a menu of its own."
  @spec menu?(module()) :: boolean()
  def menu?(game), do: Code.ensure_loaded?(game) and function_exported?(game, :open_menu, 1)

  @doc "Whether `game` can open its menu given an argument from the world."
  @spec menu_with_arg?(module()) :: boolean()
  def menu_with_arg?(game),
    do: menu?(game) or (Code.ensure_loaded?(game) and function_exported?(game, :open_menu, 2))

  @doc "`game`'s menu opened with the player's `settings`."
  @spec open(module(), map()) :: term()
  def open(game, settings), do: game.open_menu(settings)

  @doc "`game`'s menu opened with `settings` because the world asked with `arg`; `open_menu/1` for a game without `open_menu/2`."
  @spec open(module(), map(), term()) :: term()
  def open(game, settings, arg) do
    if function_exported?(game, :open_menu, 2),
      do: game.open_menu(settings, arg),
      else: game.open_menu(settings)
  end

  @doc "The game's reply to one event while `menu` is open."
  @spec event(module(), term(), term(), map()) :: %{
          menu: term(),
          settings: map(),
          sounds: [term()],
          request: term(),
          leave: boolean()
        }
  def event(game, menu, event, settings) do
    reply = game.menu_event(menu, event, settings)

    %{
      menu: Map.get(reply, :menu),
      settings: Map.fetch!(reply, :settings),
      sounds: Map.get(reply, :sounds, []),
      request: Map.get(reply, :request),
      leave: Map.get(reply, :leave, false)
    }
  end

  @doc "Whether `event` goes to an open menu or a front: a key press, a mouse press or a wheel notch."
  @spec input?(term()) :: boolean()
  def input?({:key, _key}), do: true
  def input?({:key, _key, _mods}), do: true
  def input?({:mouse, %{type: type}}), do: type in [:mouse_down, :scroll]
  def input?(_event), do: false

  @doc "The key a controller button is to a menu or a front: the d-pad its arrows, `A` Enter, `B` and `Start` Escape; `nil` for the rest."
  @spec pad_key(atom()) :: atom() | nil
  def pad_key(:dpad_up), do: :up
  def pad_key(:dpad_down), do: :down
  def pad_key(:dpad_left), do: :left
  def pad_key(:dpad_right), do: :right
  def pad_key(:a), do: :enter
  def pad_key(button) when button in [:b, :start], do: :escape
  def pad_key(_button), do: nil
end
