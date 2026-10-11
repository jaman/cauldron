defmodule Cauldron2D.Input.Pad do
  @moduledoc """
  Turns game-controller events into the set of actions a player is holding.

  A game declares a padmap from action to controls, in the Xbox layout whatever the
  hardware, as `Gamepad.Wire` names them:

      padmap = %{left: [:dpad_left, {:axis, :left_x, :neg}], fire: [:a, :right_bumper]}
      pad = Cauldron2D.Input.Pad.new(padmap, deadzone: 0.3)

  Feed it every `{:controller, event}` map with `handle/2`; `held/1` is the set of
  actions held and `strength/1` how hard each axis-driven one is pushed. Hand both to
  `Cauldron2D.Input.merge/3`.

  A control is a button name (`:a`, `:b`, `:x`, `:y`, `:left_bumper`, `:right_bumper`,
  `:back`, `:start`, `:guide`, `:left_stick`, `:right_stick`, `:dpad_up`, `:dpad_down`,
  `:dpad_left`, `:dpad_right`) or `{:axis, name, :neg | :pos}` for one direction of
  `:left_x`, `:left_y`, `:right_x`, `:right_y`, `:left_trigger` or `:right_trigger`.
  Axis values run `-1.0..1.0`, up and left negative; a trigger runs `0.0..1.0`.

  A button holds its action in full. An axis holds it at its magnitude once past
  `:deadzone`. An action held by both is held in full. Every controller's controls
  count, and a controller that goes away releases what it held.

  A stick may aim instead of holding actions: the padmap's `:aim` bound to
  `{:stick, :left}` or `{:stick, :right}` makes `aim/1` the direction that stick is
  pushed in, `{dx, dy}` of length one (up and left negative), or `nil` inside the
  deadzone, measured radially; a client turns it into an aim point a fixed way from
  the focus, as an on-screen thumbstick does. `:aim` holds no action of its own, but
  the stick may push one: `{:stick, :left, push: [action: :thrust, beyond: 0.6,
  least: 0.3, gain: 1.4]}` holds `:thrust` while the stick is past `beyond` of its
  travel, at a strength that starts at `least` and grows by `gain` over the rest of the
  travel to `1.0` — the rule an on-screen thumbstick's `push` follows. Defaults:
  `beyond: 0.5`, `least: 0.25`, `gain: 1.6`.
  """

  alias Cauldron2D.Input

  @type control ::
          atom()
          | {:axis, atom(), :neg | :pos}
          | {:stick, :left | :right}
          | {:stick, :left | :right, [push: keyword()]}
  @type push :: %{action: Input.action(), beyond: float(), least: float(), gain: float()}
  @type padmap :: %{Input.action() => [control()]}
  @type event :: %{required(:type) => atom(), optional(atom()) => term()}
  @type t :: %__MODULE__{
          bindings: %{control() => [Input.action()]},
          deadzone: float(),
          buttons: %{{non_neg_integer(), atom()} => true},
          axes: %{{non_neg_integer(), atom()} => float()},
          aim_stick: :left | :right | nil,
          push: push() | nil,
          sticks: %{{non_neg_integer(), atom()} => float()}
        }

  defstruct bindings: %{},
            deadzone: 0.3,
            buttons: %{},
            axes: %{},
            aim_stick: nil,
            push: nil,
            sticks: %{}

  @directions [
    {:left, :dpad_left, :left_x, :neg},
    {:right, :dpad_right, :left_x, :pos},
    {:up, :dpad_up, :left_y, :neg},
    {:down, :dpad_down, :left_y, :pos}
  ]

  @doc """
  A pad reading `padmap`.

  ## Options

    * `:deadzone` — the axis magnitude below which an axis holds nothing. Default `0.3`
  """
  @spec new(padmap(), keyword()) :: t()
  def new(padmap, opts \\ []) do
    bindings =
      for {action, controls} <- padmap,
          action != :aim,
          control <- controls,
          not stick?(control),
          reduce: %{} do
        acc -> Map.update(acc, control, [action], &[action | &1])
      end

    {aim_stick, push} =
      Enum.find_value(Map.get(padmap, :aim, []), {nil, nil}, fn
        {:stick, side} -> {side, nil}
        {:stick, side, options} -> {side, push_of(Keyword.get(options, :push))}
        _other -> nil
      end)

    %__MODULE__{
      bindings: bindings,
      deadzone: Keyword.get(opts, :deadzone, 0.3),
      aim_stick: aim_stick,
      push: push
    }
  end

  defp stick?({:stick, _side}), do: true
  defp stick?({:stick, _side, _options}), do: true
  defp stick?(_control), do: false

  defp push_of(nil), do: nil

  defp push_of(options) do
    %{
      action: Keyword.fetch!(options, :action),
      beyond: Keyword.get(options, :beyond, 0.5) / 1,
      least: Keyword.get(options, :least, 0.25) / 1,
      gain: Keyword.get(options, :gain, 1.6) / 1
    }
  end

  @doc "Whether the padmap binds either direction of `axis` to an action."
  @spec binds_axis?(t(), atom()) :: boolean()
  def binds_axis?(%__MODULE__{bindings: bindings}, axis),
    do: Enum.any?(Map.keys(bindings), &match?({:axis, ^axis, _direction}, &1))

  @doc "The stick bound to `:aim`, or `nil`."
  @spec aim_stick(t()) :: :left | :right | nil
  def aim_stick(%__MODULE__{aim_stick: stick}), do: stick

  @doc "What the aim stick pushes when pushed far, or `nil`."
  @spec push(t()) :: push() | nil
  def push(%__MODULE__{push: push}), do: push

  @doc "Where the aim stick points: a direction of length one, or `nil` with no aim stick or inside the deadzone."
  @spec aim(t()) :: {float(), float()} | nil
  def aim(%__MODULE__{aim_stick: nil}), do: nil

  def aim(%__MODULE__{deadzone: deadzone} = pad), do: pad |> stick_push() |> unit(deadzone)

  defp stick_push(%__MODULE__{aim_stick: side, sticks: sticks}) do
    {x_axis, y_axis} = {:"#{side}_x", :"#{side}_y"}

    sticks
    |> Enum.filter(fn {{_device, axis}, _} -> axis in [x_axis, y_axis] end)
    |> Enum.group_by(fn {{device, _}, _} -> device end)
    |> Enum.map(fn {_device, readings} ->
      {Enum.find_value(readings, 0.0, &stick_axis(&1, x_axis)),
       Enum.find_value(readings, 0.0, &stick_axis(&1, y_axis))}
    end)
    |> Enum.max_by(&magnitude/1, fn -> {0.0, 0.0} end)
  end

  defp pushed(%__MODULE__{push: nil}), do: %{}

  defp pushed(%__MODULE__{push: push} = pad) do
    length = pad |> stick_push() |> magnitude()

    if length >= push.beyond,
      do: %{
        push.action =>
          max(push.least, min(1.0, (length - push.beyond) / (1 - push.beyond) * push.gain))
      },
      else: %{}
  end

  defp stick_axis({{_device, axis}, value}, axis), do: value
  defp stick_axis(_reading, _axis), do: nil

  defp magnitude({x, y}), do: :math.sqrt(x * x + y * y)

  defp unit({x, y} = push, deadzone) do
    length = magnitude(push)
    if length < deadzone, do: nil, else: {x / length, y / length}
  end

  @doc """
  The padmap for `actions` that steers with the d-pad and the left stick.

  Of the actions given, `:left`, `:right`, `:up` and `:down` are bound to the matching
  d-pad button and direction of the left stick; the rest are left unbound.
  """
  @spec default_map([Input.action()]) :: padmap()
  def default_map(actions) do
    for {action, button, axis, direction} <- @directions,
        action in actions,
        into: %{},
        do: {action, [button, {:axis, axis, direction}]}
  end

  @doc "Apply one controller event."
  @spec handle(t(), event()) :: t()
  def handle(%__MODULE__{} = pad, %{type: :button, device: device, button: button, pressed: true}),
      do: %{pad | buttons: Map.put(pad.buttons, {device, button}, true)}

  def handle(%__MODULE__{} = pad, %{type: :button, device: device, button: button, pressed: false}),
      do: %{pad | buttons: Map.delete(pad.buttons, {device, button})}

  def handle(%__MODULE__{} = pad, %{type: :axis, device: device, axis: axis, value: value}) do
    pad = %{pad | sticks: Map.put(pad.sticks, {device, axis}, value / 1)}

    if abs(value) < pad.deadzone,
      do: %{pad | axes: Map.delete(pad.axes, {device, axis})},
      else: %{pad | axes: Map.put(pad.axes, {device, axis}, value / 1)}
  end

  def handle(%__MODULE__{} = pad, %{type: :disconnected, device: device}) do
    %{
      pad
      | buttons: Map.reject(pad.buttons, fn {{held_by, _}, _} -> held_by == device end),
        axes: Map.reject(pad.axes, fn {{held_by, _}, _} -> held_by == device end),
        sticks: Map.reject(pad.sticks, fn {{held_by, _}, _} -> held_by == device end)
    }
  end

  def handle(%__MODULE__{} = pad, _event), do: pad

  @doc """
  Where `axis` stands now, `-1.0..1.0` (`0.0..1.0` for a trigger): the reading furthest
  from centre over every controller, or `0.0` while none is past the deadzone.
  """
  @spec axis(t(), atom()) :: float()
  def axis(%__MODULE__{axes: axes}, axis) do
    for {{_device, ^axis}, value} <- axes, reduce: 0.0 do
      furthest -> if abs(value) > abs(furthest), do: value, else: furthest
    end
  end

  @doc "The actions held by any controller."
  @spec held(t()) :: MapSet.t(Input.action())
  def held(%__MODULE__{} = pad) do
    MapSet.new(button_actions(pad) ++ Map.keys(axis_strengths(pad)) ++ Map.keys(pushed(pad)))
  end

  @doc """
  How hard each action held only through an axis is pushed, `0.0..1.0`.

  An action a button holds is held in full and has no entry.
  """
  @spec strength(t()) :: %{Input.action() => float()}
  def strength(%__MODULE__{} = pad) do
    full = MapSet.new(button_actions(pad))

    pad
    |> axis_strengths()
    |> Map.merge(pushed(pad), fn _action, a, b -> max(a, b) end)
    |> Map.reject(fn {action, _} -> MapSet.member?(full, action) end)
  end

  defp button_actions(pad) do
    for {{_device, button}, true} <- pad.buttons,
        action <- Map.get(pad.bindings, button, []),
        do: action
  end

  defp axis_strengths(pad) do
    for {{_device, axis}, value} <- pad.axes,
        action <- Map.get(pad.bindings, {:axis, axis, direction(value)}, []),
        reduce: %{} do
      acc -> Map.update(acc, action, abs(value), &max(&1, abs(value)))
    end
  end

  defp direction(value) when value < 0, do: :neg
  defp direction(_value), do: :pos
end
