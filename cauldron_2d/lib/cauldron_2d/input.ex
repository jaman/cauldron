defmodule Cauldron2D.Input do
  @moduledoc """
  Turns terminal events into the set of actions a player is holding.

  A game declares its actions and a keymap from action to keys:

      keymap = %{left: [:left, :a], right: [:right, :d], jump: [:up, {:w, []}, :left_shift], act: [:" ", {:f, [:ctrl]}]}
      input = Cauldron2D.Input.new(keymap, releases?: true, toggles: [:jump])

  Feed it every event with `handle/3` and call `expire/2` once a tick; `state/1` is what
  the player is doing now: `%{held: MapSet.t(), aim: {column, row} | nil}`. A state
  from an analog control may add `strength: %{action => 0.0..1.0}`, how hard each such
  action is held; an action without an entry is held in full. Keys give none.

  ## Two ways to hold a key

  With `releases?: true` the terminal reports key releases, and an action is held from
  `{:key_down, ...}` to `{:key_up, ...}`. Legacy `{:key, ...}` events are ignored.

  With `releases?: false` a `{:key, ...}` press holds the action for `:tap_ms`
  milliseconds; the terminal's key repeat keeps it held while the key is down, and a tap
  holds it for one window. An action listed in `:holds` is held for its own, longer,
  window on a first press — long enough to cover the terminal's delay before it starts
  repeating — and each repeat then extends it by `:repeat_ms`, so it stays held while
  the key is down and lets go soon after. Actions listed in `:toggles` flip on each
  press instead and stay until pressed again. A `{:key_release_support, true}` event
  switches to the first way and drops every hold.

  Keys are matched by their unshifted name: `:A` and `{:a, [:shift]}` both press what
  `:a` is bound to. A key given with modifiers in the keymap, `{:f, [:ctrl]}`, matches
  only with them; a bare key matches with any.

  ## Keys against the pointer

  Actions listed in `:steering` are the ones the pointer also drives. Pressing a key
  bound to one drops the aim, so the keys take over, until the pointer moves again.

  ## Mouse buttons

  A key spec `{:mouse, :left | :middle | :right}` binds a mouse button. A button is
  held from its `:mouse_down` to its `:mouse_up`, through any drag, whichever way keys
  are being held; the pointer position of every mouse event becomes the aim.

  The wheel and the pointer's movement are bound like keys that are tapped:
  `{:mouse, :wheel_up | :wheel_down}` is pressed by each notch of the wheel, and
  `{:mouse, :move_left | :move_right | :move_up | :move_down}` by each move or drag that
  takes the pointer that way from where it last was. Each press holds its actions for
  `:gesture_ms`, and another press before that has passed holds them on, so a wheel
  turned or a pointer moved steadily holds them until it stops. These holds are kept
  apart from the keys', so letting go of a key never drops what the mouse holds.

  `merge/3` adds actions held by another source, such as a `Cauldron2D.Input.Pad`,
  with how hard each is held.
  """

  @type action :: atom()
  @type gesture :: :wheel_up | :wheel_down | :move_left | :move_right | :move_up | :move_down
  @type key_spec :: atom() | {atom(), [atom()]} | {:mouse, :left | :middle | :right | gesture()}
  @type keymap :: %{action() => [key_spec()]}
  @type state :: %{
          required(:held) => MapSet.t(action()),
          required(:aim) => {number(), number()} | nil,
          optional(:strength) => %{action() => float()}
        }
  @type t :: %__MODULE__{
          bindings: [{key_spec(), action()}],
          releases?: boolean(),
          toggles: MapSet.t(action()),
          steering: MapSet.t(action()),
          tap_ms: pos_integer(),
          holds: %{action() => pos_integer()},
          repeat_ms: pos_integer(),
          held: MapSet.t(action()),
          expiries: %{action() => integer()},
          gesture_ms: pos_integer(),
          gestured: %{action() => integer()},
          toggled: MapSet.t(action()),
          external: MapSet.t(action()),
          strength: %{action() => float()},
          aim: {number(), number()} | nil
        }

  defstruct bindings: [],
            releases?: false,
            toggles: MapSet.new(),
            steering: MapSet.new(),
            tap_ms: 120,
            holds: %{},
            repeat_ms: 150,
            held: MapSet.new(),
            expiries: %{},
            gesture_ms: 100,
            gestured: %{},
            toggled: MapSet.new(),
            external: MapSet.new(),
            strength: %{},
            aim: nil

  @doc """
  An input reading `keymap`.

  ## Options

    * `:releases?` — whether the terminal reports key releases. Default `false`
    * `:toggles` — actions that flip on each press when releases are not reported.
      Default `[]`
    * `:tap_ms` — how long a press holds an action when releases are not reported.
      Default `120`
    * `:holds` — `[action: milliseconds]`, actions a first press holds for that long
      instead, when releases are not reported. Default `[]`
    * `:repeat_ms` — how long a repeat of a held action extends it, when releases are
      not reported. Default `150`
    * `:steering` — actions whose key press drops the pointer's aim. Default `[]`
    * `:gesture_ms` — how long a wheel notch or a pointer move holds what it is bound
      to. Default `100`
  """
  @spec new(keymap(), keyword()) :: t()
  def new(keymap, opts \\ []) do
    %__MODULE__{
      bindings: for({action, keys} <- keymap, key <- keys, do: {normalise_spec(key), action}),
      releases?: Keyword.get(opts, :releases?, false),
      toggles: MapSet.new(Keyword.get(opts, :toggles, [])),
      steering: MapSet.new(Keyword.get(opts, :steering, [])),
      tap_ms: Keyword.get(opts, :tap_ms, 120),
      holds: Map.new(Keyword.get(opts, :holds, [])),
      repeat_ms: Keyword.get(opts, :repeat_ms, 150),
      gesture_ms: Keyword.get(opts, :gesture_ms, 100)
    }
  end

  @doc "Whether releases are being reported."
  @spec releases?(t()) :: boolean()
  def releases?(%__MODULE__{releases?: releases?}), do: releases?

  @doc "Apply one terminal event at millisecond time `now`."
  @spec handle(t(), term(), integer()) :: t()
  def handle(%__MODULE__{} = input, {:key_release_support, true}, _now) do
    %{input | releases?: true, held: MapSet.new(), expiries: %{}, toggled: MapSet.new()}
  end

  def handle(%__MODULE__{releases?: true} = input, {:key_down, key, mods}, _now) do
    actions = actions_for(input, key, mods)
    Enum.reduce(actions, drop_aim_for(input, actions), &press_held/2)
  end

  def handle(%__MODULE__{releases?: true} = input, {:key_up, key, mods}, _now) do
    Enum.reduce(actions_for(input, key, mods), input, &release_held/2)
  end

  def handle(%__MODULE__{releases?: false} = input, {:key, key}, now) do
    actions = actions_for(input, key, [])
    Enum.reduce(actions, drop_aim_for(input, actions), &tap(&2, &1, now))
  end

  def handle(%__MODULE__{releases?: false} = input, {:key, key, mods}, now) do
    actions = actions_for(input, key, mods)
    Enum.reduce(actions, drop_aim_for(input, actions), &tap(&2, &1, now))
  end

  def handle(
        %__MODULE__{} = input,
        {:mouse, %{type: :mouse_down, button: button, x: x, y: y}},
        _now
      ) do
    Enum.reduce(button_actions(input, button), %{input | aim: {x, y}}, &press_held/2)
  end

  def handle(
        %__MODULE__{} = input,
        {:mouse, %{type: :mouse_up, button: button, x: x, y: y}},
        _now
      ) do
    Enum.reduce(button_actions(input, button), %{input | aim: {x, y}}, &release_held/2)
  end

  def handle(%__MODULE__{} = input, {:mouse, %{type: :scroll, direction: direction}}, now)
      when direction in [:up, :down] do
    gesture(input, [wheel(direction)], now)
  end

  def handle(%__MODULE__{} = input, {:mouse, %{type: type, x: x, y: y}}, now)
      when type in [:move, :drag] do
    %{gesture(input, moved(input.aim, {x, y}), now) | aim: {x, y}}
  end

  def handle(%__MODULE__{} = input, _event, _now), do: input

  @doc "Drop every tapped hold whose window has passed by millisecond time `now`."
  @spec expire(t(), integer()) :: t()
  def expire(%__MODULE__{} = input, now) do
    {gone, kept} = Enum.split_with(input.expiries, fn {_action, until} -> until <= now end)
    held = Enum.reduce(gone, input.held, fn {action, _}, set -> MapSet.delete(set, action) end)
    gestured = Map.reject(input.gestured, fn {_action, until} -> until <= now end)
    %{input | expiries: Map.new(kept), held: held, gestured: gestured}
  end

  @doc """
  Replace the actions held by an outside source, and how hard each is held.

  `strength` maps an action in `external` to `0.0..1.0`; an action without an entry is
  held in full.
  """
  @spec merge(t(), MapSet.t(action()), %{action() => float()}) :: t()
  def merge(%__MODULE__{} = input, external, strength \\ %{}),
    do: %{input | external: external, strength: strength}

  @doc "What the player is doing now."
  @spec state(t()) :: state()
  def state(%__MODULE__{} = input) do
    held =
      input.held
      |> MapSet.union(input.toggled)
      |> MapSet.union(input.external)
      |> MapSet.union(MapSet.new(Map.keys(input.gestured)))

    strength =
      Map.reject(input.strength, fn {action, _} -> MapSet.member?(input.held, action) end)

    read = %{held: held, aim: input.aim}

    if strength == %{}, do: read, else: Map.put(read, :strength, strength)
  end

  @doc """
  The key spec a terminal event presses, for binding it: a key (`:a`, or `{:f, [:ctrl]}`
  with modifiers other than shift), a mouse button `{:mouse, :left | :middle | :right}`
  or a wheel notch `{:mouse, :wheel_up | :wheel_down}`; `nil` for an event that presses
  nothing, such as a release or a pointer move.
  """
  @spec spec_of(term()) :: key_spec() | nil
  def spec_of({:key, key}) when is_atom(key), do: key
  def spec_of({:key, key, mods}) when is_atom(key), do: spec_with(key, mods -- [:shift])
  def spec_of({:key_down, key, mods}) when is_atom(key), do: spec_with(key, mods -- [:shift])

  def spec_of({:mouse, %{type: :mouse_down, button: button}})
      when button in [:left, :middle, :right],
      do: {:mouse, button}

  def spec_of({:mouse, %{type: :scroll, direction: :up}}), do: {:mouse, :wheel_up}
  def spec_of({:mouse, %{type: :scroll, direction: :down}}), do: {:mouse, :wheel_down}
  def spec_of(_event), do: nil

  defp spec_with(key, []), do: key
  defp spec_with(key, mods), do: {key, mods}

  @doc "Whether `spec` is bound to any action."
  @spec binds?(t(), key_spec()) :: boolean()
  def binds?(%__MODULE__{bindings: bindings}, spec) do
    normalised = normalise_spec(spec)
    Enum.any?(bindings, &(elem(&1, 0) == normalised))
  end

  @doc "Whether pressing a key for any of `actions` drops the aim."
  @spec steers?(t(), [action()]) :: boolean()
  def steers?(%__MODULE__{steering: steering}, actions),
    do: Enum.any?(actions, &MapSet.member?(steering, &1))

  @doc "The actions a key event presses or releases, whichever way keys are held."
  @spec actions(t(), term()) :: [action()]
  def actions(%__MODULE__{} = input, {:key_down, key, mods}), do: actions_for(input, key, mods)
  def actions(%__MODULE__{} = input, {:key_up, key, mods}), do: actions_for(input, key, mods)
  def actions(%__MODULE__{} = input, {:key, key}), do: actions_for(input, key, [])
  def actions(%__MODULE__{} = input, {:key, key, mods}), do: actions_for(input, key, mods)

  def actions(%__MODULE__{} = input, {:mouse, %{button: button}}),
    do: button_actions(input, button)

  def actions(%__MODULE__{}, _event), do: []

  defp drop_aim_for(input, actions) do
    if steers?(input, actions), do: %{input | aim: nil}, else: input
  end

  defp press_held(action, input), do: %{input | held: MapSet.put(input.held, action)}
  defp release_held(action, input), do: %{input | held: MapSet.delete(input.held, action)}

  defp tap(input, action, now) do
    if MapSet.member?(input.toggles, action) do
      %{input | toggled: flip(input.toggled, action)}
    else
      until = now + window(input, action)

      %{
        input
        | held: MapSet.put(input.held, action),
          expiries: Map.update(input.expiries, action, until, &max(&1, until))
      }
    end
  end

  defp window(input, action) do
    case Map.fetch(input.holds, action) do
      {:ok, first} ->
        if MapSet.member?(input.held, action), do: max(input.repeat_ms, input.tap_ms), else: first

      :error ->
        input.tap_ms
    end
  end

  defp flip(set, action) do
    if MapSet.member?(set, action), do: MapSet.delete(set, action), else: MapSet.put(set, action)
  end

  defp actions_for(input, key, mods) do
    base = base_key(key)
    held_mods = mods -- [:shift]

    for {{bound_key, bound_mods}, action} <- input.bindings,
        bound_key == base,
        bound_mods == :any or bound_mods == held_mods,
        do: action
  end

  defp gesture(input, gestures, now) do
    until = now + input.gesture_ms

    gestured =
      for gesture <- gestures,
          action <- button_actions(input, gesture),
          reduce: input.gestured,
          do: (acc -> Map.put(acc, action, until))

    %{input | gestured: gestured}
  end

  defp wheel(:up), do: :wheel_up
  defp wheel(:down), do: :wheel_down

  defp moved(nil, _to), do: []

  defp moved({from_x, from_y}, {x, y}) do
    across(x - from_x, :move_left, :move_right) ++ across(y - from_y, :move_up, :move_down)
  end

  defp across(delta, back, _ahead) when delta < 0, do: [back]
  defp across(delta, _back, ahead) when delta > 0, do: [ahead]
  defp across(_delta, _back, _ahead), do: []

  defp button_actions(input, button) do
    for {{:mouse, ^button}, action} <- input.bindings, do: action
  end

  defp normalise_spec({:mouse, button}), do: {:mouse, button}
  defp normalise_spec({key, mods}), do: {base_key(key), Enum.sort(mods) -- [:shift]}
  defp normalise_spec(key), do: {base_key(key), :any}

  defp base_key(key) when is_atom(key) do
    case Atom.to_string(key) do
      <<char>> when char in ?A..?Z -> String.to_atom(<<char + 32>>)
      _ -> key
    end
  end

  defp base_key(key), do: key
end
