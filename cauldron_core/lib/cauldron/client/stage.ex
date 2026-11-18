defmodule Cauldron.Client.Stage do
  @moduledoc """
  A player's client-side state in a world, for any client whose game runs in Elixir
  — a browser's session on the server, a desktop window: the look, the client's keys,
  the game's open menu, its options and the requests the menu sends the world. The
  host feeds it keys and the world's views and carries out the effects it answers.

      stage = Cauldron.Client.Stage.new(MyGame.Client, settings)
      {stage, effects} = Cauldron.Client.Stage.key(stage, :v)
      stage = Cauldron.Client.Stage.view(stage, view)
      scene = Cauldron.Client.Stage.scene(stage)

  `settings` is a map with at least `:sfx`, `:music` and `:options` (the game's own,
  `c:Cauldron.Client.Game.options/0` filling what is missing); a game's menu may
  change any of it.

  ## Effects

  `key/3`, `pad/2` and `asked/1` answer a list of effects for the host, in order:

    * `{:sounds, events}` — sound events to play, as the game's `sounds/0` knows them
    * `{:settings, settings}` — the player's settings changed; save them and apply the levels
    * `:pause` — the game's menu opened over a world of the player's own: pause it
    * `:resume` — the menu closed: resume the world if `:pause` paused it
    * `:toggle_pause` — the player's pause key
    * `:leave` — leave the world: the menu said so, or the player's back key
    * `{:go, screen}` — the client's `:settings` or `:title` screen
    * `:quit` — the world asked the client to end
    * `{:clipboard, text}` — the world asked for `text` on the player's clipboard
    * `{:travel, move}` — the world asked the client to move the player: `{:enter,
      props}`, `{:return, props}` or `{:on_return, props}`, as `c:Cauldron.Client.Game.ask/1`
      describes them; the host leaves and joins worlds as they say
    * `:talk` — the player's talk key, in a game with a chat (`c:Cauldron.Client.Game.chat?/0`): open a line to say something in the world's room
    * `:redraw` — nothing else changed, but the scene must be drawn again

  The look and its zoom steps are the game's view's (`Cauldron.Client.View`).
  """

  alias Cauldron.Client.{Game, Keys, Menus, View}

  @type effect ::
          {:sounds, [term()]}
          | {:settings, map()}
          | :pause
          | :resume
          | :toggle_pause
          | :leave
          | {:go, :settings | :title}
          | :quit
          | {:clipboard, String.t()}
          | {:travel, {:enter | :return | :on_return, map()}}
          | :talk
          | :redraw

  @type t :: %__MODULE__{
          game: module(),
          look: map(),
          keys: map(),
          zoom: number(),
          settings: map(),
          menu: term(),
          menu_frame: non_neg_integer(),
          request: {pos_integer(), term()} | nil,
          requests: non_neg_integer(),
          asked: term(),
          view: term(),
          pan: {float(), float()},
          subject: term(),
          pointer: {float(), float()} | nil,
          turning?: boolean()
        }

  @enforce_keys [:game, :look, :keys, :zoom, :settings]
  defstruct [
    :game,
    :look,
    :keys,
    :zoom,
    :settings,
    menu: nil,
    menu_frame: 0,
    request: nil,
    requests: 0,
    asked: nil,
    view: nil,
    pan: {0.0, 0.0},
    subject: nil,
    pointer: nil,
    turning?: false
  ]

  @play_actions [
    :menu,
    :pause,
    :projection,
    :turn_left,
    :turn_right,
    :tilt_up,
    :tilt_down,
    :zoom_in,
    :zoom_out,
    :zoom_reset,
    :settings,
    :back,
    :title,
    :talk,
    :mouse_look
  ]

  @doc "The stage for `game` with the player's `settings`."
  @spec new(module(), map()) :: t()
  def new(game, settings) do
    %__MODULE__{
      game: game,
      look: View.of(game).look(game),
      keys: Keys.of(game),
      zoom: View.of(game).zoom(game),
      settings: with_options(game, settings)
    }
  end

  @doc "`settings` with the game's `options/0` filling the options it lacks."
  @spec with_options(module(), map()) :: map()
  def with_options(game, settings) do
    defaults = Game.optional(game, :options, [], %{})
    Map.put(settings, :options, Map.merge(defaults, Map.get(settings, :options) || %{}))
  end

  @doc "The stage holding the world's latest view."
  @spec view(t(), term()) :: t()
  def view(stage, view) do
    stage = %{stage | view: view}

    case scene(stage) do
      %{subject: subject} when subject != stage.subject ->
        %{stage | subject: subject, pan: {0.0, 0.0}}

      _same ->
        stage
    end
  end

  @doc "The look `scene/2` is given: the client's look with the open menu, its frame and the options."
  @spec look(t()) :: map()
  def look(stage),
    do: View.given(stage.look, stage.menu, stage.menu_frame, stage.settings.options)

  @doc "The scene for the latest view, or `nil` before the first; `scene/2` when the game has it."
  @spec scene(t()) :: map() | nil
  def scene(%{view: nil}), do: nil

  def scene(%{game: game, view: view} = stage) do
    if function_exported?(game, :scene, 2),
      do: game.scene(view, look(stage)),
      else: game.scene(view)
  end

  @doc "The props `scene` is drawn with at the stage's zoom and pan (`c:Cauldron.Client.View.props/4`)."
  @spec draw_props(t(), map()) :: keyword()
  def draw_props(stage, scene) do
    props = view(stage).props(stage.game, scene, stage.look, stage.zoom)

    case {props[:focus], stage.pan} do
      {{fx, fy}, {px, py}} -> Keyword.put(props, :focus, {fx + px, fy + py})
      _no_focus -> props
    end
  end

  @doc """
  The view moved by `{dx, dy}` tiles, for a player watching a world: the focus drawn
  from then on is the scene's moved that far, until `recentre/1` or the scene's
  `:subject` changes.
  """
  @spec pan_by(t(), {number(), number()}) :: t()
  def pan_by(%{pan: {px, py}} = stage, {dx, dy}), do: %{stage | pan: {px + dx, py + dy}}

  @doc "The view back on the scene's focus."
  @spec recentre(t()) :: t()
  def recentre(stage), do: %{stage | pan: {0.0, 0.0}}

  @doc """
  What the player's input to the world carries besides what they hold and aim at:
  `:options` when the game has any, and the menu's latest `:request`.
  """
  @spec input_extras(t()) :: map()
  def input_extras(stage) do
    %{}
    |> put_unless_empty(:options, stage.settings.options)
    |> put_unless_nil(:request, stage.request)
  end

  @doc "Whether the game's menu is open."
  @spec menu_open?(t()) :: boolean()
  def menu_open?(stage), do: stage.menu != nil

  @doc """
  The player stepped away from the client (an app sent to the background): the game's
  menu opened over the world, as its menu key opens it, so a world of the player's own
  pauses; `:pause` alone for a game without a menu; nothing when the menu is open.
  """
  @spec rest(t()) :: {t(), [effect()]}
  def rest(%{menu: menu} = stage) when menu != nil, do: {stage, []}

  def rest(stage) do
    if Menus.menu?(stage.game),
      do: opened(stage, Menus.open(stage.game, stage.settings)),
      else: {stage, [:pause]}
  end

  @doc """
  The player came back after `rest/1`: `:resume` for a game without a menu; nothing for
  a game with one, whose menu stays open until the player closes it.
  """
  @spec wake(t()) :: {t(), [effect()]}
  def wake(stage),
    do: if(Menus.menu?(stage.game), do: {stage, []}, else: {stage, [:resume]})

  @doc "The open menu's frame counted on, for its animations; nothing when no menu is open."
  @spec menu_tick(t()) :: t()
  def menu_tick(%{menu: nil} = stage), do: stage
  def menu_tick(stage), do: %{stage | menu_frame: stage.menu_frame + 1}

  @doc """
  A key pressed during play, `key` as `Cauldron.Input` names keys and `mods` its
  modifiers: to the open menu as `{:key, key, mods}`, else the client's own action
  bound to it. A key that is neither answers no effects; the game's own actions reach
  the world through the held keys, not here.
  """
  @spec key(t(), atom(), [atom()]) :: {t(), [effect()]}
  def key(stage, key, mods \\ [])

  def key(%{menu: menu} = stage, key, mods) when menu != nil,
    do: menu_event(stage, {:key, key, mods})

  def key(stage, key, mods) do
    case Keys.action(stage.keys, key, mods, @play_actions ++ Keys.look_actions(stage.keys)) do
      nil -> {stage, []}
      action -> act(stage, action)
    end
  end

  @doc "Whether a key pressed now goes to the stage — the game's open menu, or one of the client's own keys — rather than to the game's actions."
  @spec takes_key?(t(), atom()) :: boolean()
  def takes_key?(%{menu: menu}, _key) when menu != nil, do: true

  def takes_key?(stage, key),
    do: Keys.action(stage.keys, key, @play_actions ++ Keys.look_actions(stage.keys)) != nil

  @doc "A mouse press or wheel notch, as `Cauldron.Input` events carry it: to the open menu; otherwise a wheel notch zooms, unless the game binds the wheel."
  @spec mouse(t(), map()) :: {t(), [effect()]}
  def mouse(%{menu: nil} = stage, %{type: :scroll, direction: direction}) do
    if wheel_bound?(stage.game),
      do: {stage, []},
      else: act(stage, if(direction == :up, do: :zoom_in, else: :zoom_out))
  end

  def mouse(%{menu: nil} = stage, _mouse), do: {stage, []}
  def mouse(stage, mouse), do: menu_event(stage, {:mouse, mouse})

  @doc """
  The pointer at `at`, fractions of the picture's width and height, as a mouse event
  carries it: a press, a release or a move. While the left button is held where the look
  turns with the pointer (`c:Cauldron.Client.View.turns_with_pointer?/1`), and on any
  move once the player's `mouse_look` key has switched mouse look on, a move turns the
  view by how far the pointer went (`c:Cauldron.Client.View.dragged/2`); the event
  reaches the game as well.
  """
  @spec pointer(t(), map()) :: {t(), [effect()]}
  def pointer(%{menu: nil} = stage, %{type: :mouse_down, button: :left, at: at}),
    do: {%{stage | pointer: at, turning?: view(stage).turns_with_pointer?(stage.look)}, []}

  def pointer(stage, %{type: :mouse_up, button: :left}), do: {%{stage | turning?: false}, []}

  def pointer(%{menu: nil, pointer: {px, py}} = stage, %{type: :move, at: {x, y}}) do
    if view(stage).turns_with_pointer?(stage.look) and (stage.turning? or stage.look.mouse_look?),
      do:
        redrawn(%{
          stage
          | look: view(stage).dragged(stage.look, {x - px, y - py}),
            pointer: {x, y}
        }),
      else: {%{stage | pointer: {x, y}}, []}
  end

  def pointer(stage, %{at: at}), do: {%{stage | pointer: at}, []}
  def pointer(stage, _mouse), do: {stage, []}

  @doc """
  A controller button pressed: while the menu is open, the d-pad, `A`, `B` and `Start`
  work it as keys; otherwise the client's own action on that button
  (`Cauldron.Client.Keys.pad/2`): the menu, the projection, turning.
  """
  @spec pad(t(), atom()) :: {t(), [effect()]}
  def pad(%{menu: menu} = stage, button) when menu != nil do
    case Menus.pad_key(button) do
      nil -> {stage, []}
      key -> menu_event(stage, {:key, key, [:pad]})
    end
  end

  def pad(stage, button) do
    case Enum.find(Keys.pad(stage.game, stage.look), fn {_action, pressed} ->
           pressed == button
         end) do
      {action, _button} -> act(stage, action)
      nil -> {stage, []}
    end
  end

  @doc "What the world asks of the client in the latest view (`c:Cauldron.Client.Game.ask/1`), acted on once per number."
  @spec asked(t()) :: {t(), [effect()]}
  def asked(%{view: nil} = stage), do: {stage, []}

  def asked(stage) do
    case Game.optional(stage.game, :ask, [stage.view], nil) do
      nil -> {stage, []}
      {number, _ask} when number == stage.asked -> {stage, []}
      {number, ask} -> answer(%{stage | asked: number}, ask)
    end
  end

  defp answer(stage, :quit), do: {stage, [:quit]}

  defp answer(%{menu: nil} = stage, :menu),
    do:
      if(Menus.menu?(stage.game),
        do: opened(stage, Menus.open(stage.game, stage.settings)),
        else: {stage, []}
      )

  defp answer(%{menu: nil} = stage, {:menu, arg}),
    do:
      if(Menus.menu_with_arg?(stage.game),
        do: opened(stage, Menus.open(stage.game, stage.settings, arg)),
        else: {stage, []}
      )

  defp answer(stage, {:options, changes}) when is_map(changes) do
    settings = %{stage.settings | options: Map.merge(stage.settings.options, changes)}
    {%{stage | settings: settings}, [{:settings, settings}]}
  end

  defp answer(stage, {:clipboard, text}) when is_binary(text), do: {stage, [{:clipboard, text}]}

  defp answer(stage, {:enter, props}) when is_map(props),
    do: {stage, [{:travel, {:enter, props}}]}

  defp answer(stage, {:return, extra}) when is_map(extra),
    do: {stage, [{:travel, {:return, extra}}]}

  defp answer(stage, {:on_return, extra}) when is_map(extra),
    do: {stage, [{:travel, {:on_return, extra}}]}

  defp answer(stage, _ask), do: {stage, []}

  defp act(stage, :menu) do
    if Menus.menu?(stage.game),
      do: opened(stage, Menus.open(stage.game, stage.settings)),
      else: {stage, []}
  end

  defp act(stage, :pause), do: {stage, [:toggle_pause]}
  defp act(stage, :talk), do: if(chat?(stage.game), do: {stage, [:talk]}, else: {stage, []})
  defp act(stage, :projection), do: redrawn(%{stage | look: view(stage).cycle(stage.look)})
  defp act(stage, :turn_left), do: redrawn(%{stage | look: view(stage).turn(stage.look, -1)})
  defp act(stage, :turn_right), do: redrawn(%{stage | look: view(stage).turn(stage.look, 1)})
  defp act(stage, :tilt_up), do: redrawn(%{stage | look: view(stage).tilt(stage.look, 1)})
  defp act(stage, :tilt_down), do: redrawn(%{stage | look: view(stage).tilt(stage.look, -1)})
  defp act(stage, :zoom_in), do: redrawn(zoom_step(stage, 1))
  defp act(stage, :zoom_out), do: redrawn(zoom_step(stage, -1))
  defp act(stage, :zoom_reset), do: redrawn(%{stage | zoom: 1, pan: {0.0, 0.0}})
  defp act(stage, :settings), do: {stage, [{:go, :settings}]}

  defp act(stage, :mouse_look),
    do: {%{stage | look: %{stage.look | mouse_look?: not stage.look.mouse_look?}}, []}

  defp act(stage, leave) when leave in [:back, :title], do: {stage, [:leave]}

  defp act(stage, {:look, key}),
    do: redrawn(%{stage | look: Map.update(stage.look, key, true, &(not &1))})

  defp redrawn(stage), do: {stage, [:redraw]}

  @doc "Whether `game` carries a chat: its `chat?/0`, `true` without one."
  @spec chat?(module()) :: boolean()
  def chat?(game), do: Game.optional(game, :chat?, [], true)

  defp wheel_bound?(game) do
    Enum.any?(game.keymaps(), fn {_name, keymap} ->
      Enum.any?(keymap, fn {_action, keys} ->
        Enum.any?(keys, &(&1 in [{:mouse, :wheel_up}, {:mouse, :wheel_down}]))
      end)
    end)
  end

  defp zoom_step(stage, step) do
    levels = view(stage).zoom_levels(stage.game, stage.look)

    index =
      Enum.find_index(levels, &(&1 == stage.zoom)) || Enum.find_index(levels, &(&1 == 1)) || 0

    %{stage | zoom: Enum.at(levels, min(max(index - step, 0), length(levels) - 1))}
  end

  defp view(stage), do: View.of(stage.game)

  defp opened(stage, menu), do: {%{stage | menu: menu, menu_frame: 0}, [:pause, :redraw]}

  defp menu_event(stage, event) do
    reply = Menus.event(stage.game, stage.menu, event, stage.settings)
    changed? = reply.settings != stage.settings
    stage = %{stage | menu: reply.menu, settings: reply.settings} |> requested(reply.request)

    effects =
      [{:sounds, reply.sounds}] ++
        if(changed?, do: [{:settings, reply.settings}], else: []) ++
        if(reply.menu == nil, do: [:resume], else: []) ++
        if(reply.leave, do: [:leave], else: []) ++ [:redraw]

    {stage, effects}
  end

  defp requested(stage, nil), do: stage

  defp requested(stage, request) do
    count = stage.requests + 1
    %{stage | requests: count, request: {count, request}}
  end

  defp put_unless_empty(map, _key, value) when map_size(value) == 0, do: map
  defp put_unless_empty(map, key, value), do: Map.put(map, key, value)

  defp put_unless_nil(map, _key, nil), do: map
  defp put_unless_nil(map, key, value), do: Map.put(map, key, value)
end
