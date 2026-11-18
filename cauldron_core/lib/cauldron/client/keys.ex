defmodule Cauldron.Client.Keys do
  @moduledoc """
  The client's own keys — back, settings, zoom, the view, the game's menu — by action,
  each a key or a list of keys as `Cauldron.Input` names them, the game's
  `c:Cauldron.Client.Game.client_keys/0` over the defaults. Every front end reads
  its keys from here, so a game rebinds them once.

      keys = Cauldron.Client.Keys.of(MyGame.Client)
      Cauldron.Client.Keys.action(keys, :v, [:projection, :zoom_in])
      #=> :projection

  `title` leaves the lobby for the title screen and quits from the title; `leave_world` leaves
  a world for the lobby. A game that must not lose its world to a stray key binds `leave_world`
  to `nil` (`back` still leaves it).

  An action whose key is `nil` is unbound. `{:look, key}` actions flip the boolean
  `key` of the look.
  """

  alias Cauldron.Client.Game
  alias Cauldron.Client.Menus

  @turning [:iso, :oblique, :mode7, :first_person]

  @defaults %{
    back: :escape,
    title: :q,
    leave_world: :q,
    settings: :tab,
    menu: nil,
    settings_menu: :s,
    talk: :t,
    watch: :w,
    team: :t,
    chat: :c,
    guide: :h,
    hints: :"?",
    fps: nil,
    pause: :p,
    zoom_in: [:=, :+],
    zoom_out: [:-, :_],
    zoom_reset: :"0",
    projection: :v,
    turn_left: :"[",
    turn_right: :"]",
    tilt_up: :"'",
    tilt_down: :";",
    display: nil,
    glyphs: nil,
    mouse_look: nil
  }

  @doc "The client's keys by action before a game's `client_keys/0` is applied."
  @spec defaults() :: %{term() => atom() | [atom()] | nil}
  def defaults, do: @defaults

  @doc "`game`'s client keys: the defaults with its `client_keys/0` over them."
  @spec of(module()) :: %{term() => atom() | [atom()] | nil}
  def of(game), do: Map.merge(@defaults, Game.optional(game, :client_keys, [], %{}))

  @doc """
  The first action of `order` that `key` is bound to in `keys`, or `nil`.

  A binding is a key, or a key and the modifiers it needs (`{:q, [:ctrl]}`). A binding
  without modifiers never matches a key pressed with one, so `:q` and `{:q, [:ctrl]}`
  can both be bound and stay apart.
  """
  @spec action(map(), atom() | nil, [atom()], [term()]) :: term() | nil
  def action(keys, key, mods \\ [], order)
  def action(_keys, nil, _mods, _order), do: nil

  def action(keys, key, mods, order),
    do:
      Enum.find(
        order,
        &Enum.any?(List.wrap(Map.get(keys, &1)), fn spec -> matches?(spec, key, mods) end)
      )

  defp matches?({key, needed}, key, mods), do: Enum.all?(needed, &(&1 in mods))
  defp matches?(key, key, mods), do: mods == []
  defp matches?(_spec, _key, _mods), do: false

  @doc """
  The client's own actions on controller buttons for `game` starting in `look`: `Start`
  opens the game's menu where it has one; the projection is cycled by `Back` in a game
  with a menu and by `Start` in one without, where the look has more than one; the
  bumpers turn where a projection in the look turns; the game's `client_pad/0` over
  these.
  """
  @spec pad(module(), map()) :: %{term() => atom() | nil}
  def pad(game, look) do
    menu? = Menus.menu?(game)
    turns? = Enum.any?(look.projections, &(&1 in @turning))

    %{
      menu: if(menu?, do: :start),
      projection: projection_button(menu?, look.projections),
      turn_left: if(turns?, do: :left_bumper),
      turn_right: if(turns?, do: :right_bumper)
    }
    |> Map.merge(Game.optional(game, :client_pad, [], %{}))
  end

  @doc "The buttons `pad/2` keeps for the client, a button or a list of buttons per action, which a default padmap passes over."
  @spec pad_buttons(map()) :: [atom()]
  def pad_buttons(pad), do: pad |> Map.values() |> Enum.flat_map(&List.wrap/1)

  defp projection_button(_menu?, [_only]), do: nil
  defp projection_button(true, _projections), do: :back
  defp projection_button(false, _projections), do: :start

  @doc "The `{:look, key}` actions bound in `keys`."
  @spec look_actions(map()) :: [{:look, atom()}]
  def look_actions(keys), do: for({:look, _key} = action <- Map.keys(keys), do: action)
end
