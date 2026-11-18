defmodule Cauldron.Client.Controls do
  @moduledoc """
  What a player holds, read from raw events the way every front end reads them: keys
  and mouse through `Cauldron.Input` with the player's bindings and the game's
  toggles, holds, steering and input options; controllers through
  `Cauldron.Input.Pad` with the game's padmap; and actions held directly — a touch
  screen's buttons — by name.

      controls = Cauldron.Client.Controls.new(MyGame.Client, settings, props)
      controls = Cauldron.Client.Controls.event(controls, {:key_down, :left, []}, now)
      Cauldron.Client.Controls.state(controls)
      #=> %{held: MapSet.new([:left]), aim: nil}

  `settings` carries `:bindings` (a keymap) or `:preset` (one of the game's `keymaps/0`),
  and `:options` for `c:Cauldron.Client.Game.input_options/1`.

  Keys are read with their releases by default, so a key is held from its press to its
  release. A front end whose keys may come without releases (a terminal) starts with
  `releases?: false`: a press then holds its action for a moment, the game's `holds/0`
  for longer (`Cauldron.Input`), and a `{:key_release_support, supported?}` event
  says from then on whether releases come.

  Mouse positions are in whatever units the caller gives — they become the mouse's aim,
  and their moves the pointer gestures. The aim placed with `aim/2`, or moved a tile by
  the right stick (`nudge/4`), is kept apart from the mouse's and read over it;
  `stick_aim/3` is where the padmap's aim stick points.
  """

  alias Cauldron.Client.{Game, Keys, View}
  alias Cauldron.Input
  alias Cauldron.Input.Pad

  @type t :: %__MODULE__{
          input: Input.t(),
          pad: Pad.t(),
          touch: %{atom() => float() | nil},
          aim: {number(), number()} | nil,
          options: keyword(),
          view: module()
        }

  @type focus :: (-> {number(), number()} | nil)

  defstruct [:input, :pad, :options, :view, touch: %{}, aim: nil]

  @stick_reach 8.0

  @doc """
  Nothing held, for `game` with the player's `settings` and the client's `props` (for
  `padmap/2`).

  ## Options

    * `:releases?` — whether keys come with their releases. Default `true`
  """
  @spec new(module(), map(), map(), keyword()) :: t()
  def new(game, settings, props \\ %{}, opts \\ []) do
    options = input_options(game, settings, Keyword.get(opts, :releases?, true))

    %__MODULE__{
      input: Input.new(bindings(game, settings), options),
      pad: Pad.new(padmap(game, props)),
      options: options,
      view: View.of(game)
    }
  end

  @doc """
  The padmap a player of `game` plays with: the game's `padmap/1` for `props`, else the
  default one passing over the buttons the client keeps for itself
  (`Cauldron.Client.Keys.pad_buttons/1` in the game's starting look).
  """
  @spec padmap(module(), map()) :: Pad.padmap()
  def padmap(game, props),
    do: Game.padmap(game, props, Keys.pad_buttons(Keys.pad(game, View.of(game).look(game))))

  @doc "The keymap `settings` play with: its `:bindings`, else its `:preset` of the game's keymaps, else the first."
  @spec bindings(module(), map()) :: Input.keymap()
  def bindings(game, settings) do
    keymaps = game.keymaps()

    Map.get(settings, :bindings) ||
      Enum.find_value(keymaps, fn {name, keymap} ->
        if name == Map.get(settings, :preset), do: keymap
      end) ||
      keymaps |> List.first({nil, %{}}) |> elem(1)
  end

  @doc "The controls with every key, button and hold let go: what a game's menu opening does."
  @spec let_go(t()) :: t()
  def let_go(%__MODULE__{} = controls) do
    keymap = Input.keymap(controls.input)

    %{
      controls
      | input: Input.new(keymap, controls.options),
        pad: Pad.release(controls.pad),
        touch: %{}
    }
  end

  @doc """
  The controls playing `game` with new `settings`: their keymap, and the game's input
  options for their `:options`; everything held is let go.
  """
  @spec settings(t(), module(), map()) :: t()
  def settings(%__MODULE__{} = controls, game, settings) do
    options = input_options(game, settings, Keyword.fetch!(controls.options, :releases?))

    %{
      controls
      | input: Input.new(bindings(game, settings), options),
        pad: Pad.release(controls.pad),
        touch: %{},
        options: options
    }
  end

  @doc """
  A raw event as `Cauldron.Input` takes it, at `now` milliseconds: `{:key, key}`,
  `{:key, key, mods}`, `{:key_down, key, mods}`, `{:key_up, key, mods}` or `{:mouse,
  event}`. `{:key_release_support, supported?}` says whether keys come with their
  releases from now on; with `true` everything held by a key is let go.
  """
  @spec event(t(), term(), integer()) :: t()
  def event(%__MODULE__{} = controls, {:key_release_support, supported?} = event, now) do
    %{
      controls
      | input: Input.handle(controls.input, event, now),
        options: Keyword.put(controls.options, :releases?, supported?)
    }
  end

  def event(%__MODULE__{} = controls, event, now),
    do: %{controls | input: Input.handle(controls.input, event, now)}

  @doc """
  A mouse event as `Cauldron.Input` takes it: `%{type: :mouse_down | :mouse_up, button,
  x, y}`, `%{type: :scroll, direction}` or `%{type: :move, x, y}`.
  """
  @spec mouse(t(), map(), integer()) :: t()
  def mouse(%__MODULE__{} = controls, event, now), do: event(controls, {:mouse, event}, now)

  @doc "A controller event as `Gamepad.Wire` describes it."
  @spec pad(t(), map()) :: t()
  def pad(%__MODULE__{} = controls, event), do: %{controls | pad: Pad.handle(controls.pad, event)}

  @doc "An action held (`strength` `nil` for in full) or let go by name, as a touch screen's button holds it."
  @spec hold(t(), atom(), boolean(), number() | nil) :: t()
  def hold(%__MODULE__{} = controls, action, true, strength),
    do: %{controls | touch: Map.put(controls.touch, action, strength)}

  def hold(%__MODULE__{} = controls, action, false, _strength),
    do: %{controls | touch: Map.delete(controls.touch, action)}

  @doc "The aim placed from outside — a pointer the caller placed in the world, or `nil`."
  @spec aim(t(), {number(), number()} | nil) :: t()
  def aim(%__MODULE__{} = controls, aim), do: %{controls | aim: aim}

  @doc "The aim placed with `aim/2` or moved by `nudge/4`, or `nil`."
  @spec aim(t()) :: {number(), number()} | nil
  def aim(%__MODULE__{aim: aim}), do: aim

  @doc """
  The world point the padmap's aim stick points at: eight tiles from `focus` the way it
  is pushed, turned for `look` (`c:Cauldron.Client.View.world_direction/2`), or `nil`
  with no aim stick pushed or nothing in view. `focus` gives the point the view is drawn
  around, or `nil`, and is called only while the stick is pushed.
  """
  @spec stick_aim(t(), map(), focus()) :: {float(), float()} | nil
  def stick_aim(%__MODULE__{pad: pad, view: view}, look, focus) do
    with {dx, dy} <- Pad.aim(pad),
         {fx, fy} <- focus.() do
      {tx, ty} = view.world_direction(look, {dx, dy})
      {fx + tx * @stick_reach, fy + ty * @stick_reach}
    end
  end

  @doc """
  The controls after a controller event, with the placed aim moved a tile the way the
  right stick is pushed past half way, turned for `look`, starting from `focus` when no
  aim is placed. The right stick nudges only when the padmap neither aims with it nor
  binds its axes, while the right stick does not turn the view
  (`c:Cauldron.Client.View.stick_turns?/1`), and with something in view: `focus` gives the
  point the view is drawn around, or `nil`, and is called only for a nudge.
  """
  @spec nudge(t(), map(), map(), focus()) :: t()
  def nudge(
        %__MODULE__{} = controls,
        %{type: :axis, axis: axis, value: value},
        look,
        focus
      )
      when axis in [:right_x, :right_y] and abs(value) >= 0.5 do
    with true <- nudges?(controls, axis, look),
         {_x, _y} = centre <- focus.() do
      {ax, ay} = controls.aim || centre
      {dx, dy} = controls.view.world_direction(look, nudge_step(axis, value))
      %{controls | aim: {ax + dx, ay + dy}}
    else
      _no_nudge -> controls
    end
  end

  def nudge(%__MODULE__{} = controls, _event, _look, _focus), do: controls

  @doc "Taps and gestures whose time is up by `now` let go."
  @spec expire(t(), integer()) :: t()
  def expire(%__MODULE__{} = controls, now),
    do: %{controls | input: Input.expire(controls.input, now)}

  @doc "Whether a key is bound to any of the game's actions."
  @spec binds?(t(), atom(), [atom()]) :: boolean()
  def binds?(%__MODULE__{} = controls, key, mods),
    do: Input.actions(controls.input, {:key_down, key, mods}) != []

  @doc """
  What the player holds now: `%{held, aim}` and `strength` where an action is held only
  part way, the keyboard's, the controllers' and the touch screen's together; the aim
  placed with `aim/2` over the mouse's.
  """
  @spec state(t()) :: Input.state()
  def state(%__MODULE__{} = controls) do
    touch_held = MapSet.new(Map.keys(controls.touch))

    touch_strength =
      for {action, strength} <- controls.touch,
          strength != nil,
          into: %{},
          do: {action, strength / 1}

    external = MapSet.union(Pad.held(controls.pad), touch_held)
    strength = Map.merge(Pad.strength(controls.pad), touch_strength)
    read = Input.state(Input.merge(controls.input, external, strength))
    if controls.aim, do: %{read | aim: controls.aim}, else: read
  end

  defp input_options(game, settings, releases?) do
    [
      releases?: releases?,
      toggles: game.toggles(),
      holds: Game.optional(game, :holds, [], []),
      steering: Game.optional(game, :steering, [], [])
    ] ++ Game.optional(game, :input_options, [Map.get(settings, :options, %{})], [])
  end

  defp nudges?(%{pad: pad, view: view}, axis, look),
    do:
      not view.stick_turns?(look) and Pad.aim_stick(pad) != :right and
        not Pad.binds_axis?(pad, axis)

  defp nudge_step(:right_x, value) when value > 0, do: {1, 0}
  defp nudge_step(:right_x, _value), do: {-1, 0}
  defp nudge_step(:right_y, value) when value > 0, do: {0, 1}
  defp nudge_step(:right_y, _value), do: {0, -1}
end
