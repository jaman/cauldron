defmodule Cauldron2D.Native.Pad do
  @moduledoc """
  A game controller drawn on a touch screen, laid out as phone games lay out theirs: the
  middle of the screen left to the game, a thumbstick under one thumb wherever it lands,
  the buttons in a fan under the other, and the menu button small in the middle of the
  top edge, where a game seldom draws its hud. Its
  presses are `Gamepad.Wire` events of device `0`, so a session reads them with the
  game's padmap, and a front or menu with `Cauldron.Client.Menus.pad_key/1`, as it
  reads a real controller.

      pad = Cauldron2D.Native.Pad.new(
        %{width: 2556, height: 1179, scale: 3.0, insets: {0, 177, 63, 177}},
        %{a: "A JUMP", x: "X STRIKE", start: "II"},
        hand: :right
      )
      {pad, events, pointers} = Cauldron2D.Native.Pad.touch(pad, touches)

  ## Sides

  With `hand: :right` (the default) the stick is on the left and the buttons on the
  right; `hand: :left` mirrors the whole layout. The stick's side is the outer 45 % of
  the screen on its side, below the top quarter; the buttons' side is the same on the
  other side.

  ## The thumbstick

  A finger that lands on the stick's side and on no button sets the stick down where it
  landed. Moving it presses the d-pad: `:dpad_left` or `:dpad_right` past a third of the
  stick's radius to that side, `:dpad_up` or `:dpad_down` past half of it. A finger that
  goes beyond the edge drags the stick after it, so turning back is never more than a
  radius away. Lifted, the stick returns to its resting place in its bottom corner, drawn
  faintly.

  ## The buttons

  `A` sits nearest the bottom corner; `X`, `Y` and `B` fan around it towards the middle
  of the screen and up; the bumpers sit further out on the same fan. A finger counts on a
  button within half again its radius, and one that lands on the buttons' side just off
  the fan (within 2.4 radii of a button) counts on the nearest button, so a quick tap
  that misses still presses. A finger on a button presses it and, sliding onto another,
  lets the first go and presses the second.

  The fan stays where it is (`buttons: :locked`, the default), or with `buttons: :move`
  a finger that lands on the buttons' side well clear of the fan moves the whole fan so
  that `A` is under it, and presses `A`. `offset/1` gives where the fan sits, to keep and
  hand back to `new/3`.

  A finger that lands anywhere else is a pointer: its touches come back as `pointers`,
  `{:down | :move | :up, {x, y}}` in pixels.

  Sizes are in points (`:scale` pixels each), so the controls are the same size under the
  thumb on a phone and on a tablet. The bottom corners keep clear of half the side and
  bottom insets, enough for a rounded corner or a camera cutout. Controls are drawn
  faintly until held.
  """

  @face [:a, :b, :x, :y]
  @bumpers [:left_bumper, :right_bumper]
  @across 1 / 3
  @upright 1 / 2

  @stick_radius 52
  @knob_radius 22
  @primary_radius 34
  @button_radius 28
  @menu_radius 18
  @margin 12
  @reach 1.5
  @near_miss 2.4
  @fan 86
  @outer_fan 160
  @places %{
    x: {-1.0, 0.0},
    y: {-0.7071, -0.7071},
    b: {0.0, -1.0},
    left_bumper: {-0.9, -0.44},
    right_bumper: {-0.44, -0.9}
  }

  @enforce_keys [:controls, :stick, :screen, :hand, :scale, :home]
  defstruct [
    :controls,
    :stick,
    :screen,
    :hand,
    :scale,
    :home,
    buttons: :locked,
    fingers: %{},
    held: MapSet.new()
  ]

  @type hand :: :right | :left
  @type control :: %{
          button: atom(),
          x: float(),
          y: float(),
          radius: float(),
          label: String.t()
        }
  @type stick :: %{
          rest: {float(), float()},
          radius: float(),
          knob_radius: float(),
          origin: {float(), float()} | nil,
          knob: {float(), float()}
        }
  @type touch :: %{
          id: integer(),
          phase: :began | :moved | :ended | :cancelled,
          x: number(),
          y: number()
        }
  @type pointer :: {:down | :move | :up, {float(), float()}}
  @type event :: %{type: :button, device: 0, button: atom(), pressed: boolean()}
  @type t :: %__MODULE__{
          controls: [control()],
          stick: stick(),
          screen: {number(), number()},
          hand: hand(),
          scale: number(),
          home: {float(), float()},
          buttons: :locked | :move,
          fingers: %{integer() => :stick | {:button, atom()} | :pointer},
          held: MapSet.t(atom())
        }

  @doc """
  The pad for a screen (`%{width, height, scale, insets}`: pixels, pixels a point, and
  insets `{top, right, bottom, left}` in pixels) and `labels`, a button name to the words
  on it; buttons without a label are not drawn. The stick is always there. Options:

    * `:hand` — `:right` (default) or `:left`
    * `:buttons` — `:locked` (default): the fan stays where it is; `:move`: a thumb that
      lands on the buttons' side well clear of the fan brings the fan under it
    * `:offset` — `{inward, up}`, the points the fan sits from its place in the corner,
      towards the middle of the screen and up, as `offset/1` gives it. Default `{0, 0}`
  """
  @spec new(map(), %{atom() => String.t()}, keyword()) :: t()
  def new(
        %{width: width, height: height, scale: scale, insets: {top, right, bottom, left}},
        labels,
        opts \\ []
      ) do
    hand = Keyword.get(opts, :hand, :right)
    {inward, up} = Keyword.get(opts, :offset, {0, 0})
    point = &(&1 * scale)
    {near_side, far_side} = if hand == :right, do: {left, right}, else: {right, left}
    floor = height - max(bottom / 2, point.(@margin))

    stick = %{
      rest:
        {max(near_side / 2, point.(@margin)) + point.(@stick_radius + 10),
         floor - point.(@stick_radius + 6)},
      radius: point.(@stick_radius),
      knob_radius: point.(@knob_radius),
      origin: nil,
      knob: {0.0, 0.0}
    }

    home =
      {width - max(far_side / 2, point.(@margin)) - point.(@primary_radius + 6),
       floor - point.(@primary_radius + 4)}

    corner = {elem(home, 0) - point.(inward), elem(home, 1) - point.(up)}

    %__MODULE__{
      controls: fan(labels, corner, point) ++ menu(labels, width, top, point),
      stick: stick,
      screen: {width, height},
      hand: hand,
      scale: scale,
      home: home,
      buttons: Keyword.get(opts, :buttons, :locked)
    }
    |> mirrored_if_left()
  end

  @doc """
  The buttons a padmap holds an action with, each labelled with its own name and the
  action's in capitals (`"A JUMP"`), so a prompt that names the buttons can be followed,
  and `Start` as `"II"` when the client or the game puts something on it.
  """
  @spec labels(map(), map()) :: %{atom() => String.t()}
  def labels(padmap, client_pad) do
    from_game =
      for {action, controls} <- padmap,
          button <- controls,
          button in (@face ++ @bumpers),
          into: %{} do
        {button, letter(button) <> " " <> words(action)}
      end

    if Enum.any?(client_pad, fn {_action, button} -> button == :start end) or
         Enum.any?(padmap, fn {_action, controls} -> :start in controls end),
       do: Map.put(from_game, :start, "II"),
       else: from_game
  end

  @doc """
  Where the fan sits now, as `new/3`'s `:offset` takes it: `{inward, up}` in points from
  its place in the corner, so it can be kept and the fan put back there later.
  """
  @spec offset(t()) :: {float(), float()}
  def offset(%{controls: controls, home: {hx, hy}, scale: scale} = pad) do
    case Enum.find(controls, &(&1.button == :a)) do
      nil ->
        {0.0, 0.0}

      %{x: x, y: y} ->
        {width, _height} = pad.screen
        x = if pad.hand == :left, do: width - x, else: x
        {Float.round((hx - x) / scale, 1), Float.round((hy - y) / scale, 1)}
    end
  end

  @doc "The pad after `touches`, the controller events they made, and the touches that landed on no control."
  @spec touch(t(), [touch()]) :: {t(), [event()], [pointer()]}
  def touch(pad, touches) do
    {pad, pointers} = Enum.reduce(touches, {pad, []}, &finger/2)
    held = holding(pad)
    events = changes(pad.held, held)
    {%{pad | held: held}, events, Enum.reverse(pointers)}
  end

  @doc "Every finger lifted: the pad with nothing held, and the releases that makes."
  @spec release(t()) :: {t(), [event()]}
  def release(pad) do
    events = changes(pad.held, MapSet.new())
    {%{pad | fingers: %{}, held: MapSet.new(), stick: settled(pad.stick)}, events}
  end

  @doc "The shapes `CauldronNative.overlay/1` draws for the pad."
  @spec shapes(t()) :: [CauldronNative.shape()]
  def shapes(pad),
    do: stick_shapes(pad.stick) ++ Enum.map(pad.controls, &button_shape(&1, pad.held))

  defp mirrored_if_left(%{hand: :right} = pad), do: pad

  defp mirrored_if_left(%{screen: {width, _height}} = pad) do
    {sx, sy} = pad.stick.rest

    %{
      pad
      | controls: Enum.map(pad.controls, &%{&1 | x: width - &1.x}),
        stick: %{pad.stick | rest: {width - sx, sy}}
    }
  end

  defp stick_shapes(%{origin: nil, rest: {x, y}} = stick) do
    [
      %{x: x, y: y, radius: stick.radius, alpha: 0.35},
      %{x: x, y: y, radius: stick.knob_radius, alpha: 0.35}
    ]
  end

  defp stick_shapes(%{origin: {x, y}, knob: {dx, dy}} = stick) do
    [
      %{x: x, y: y, radius: stick.radius, alpha: 0.7},
      %{
        x: x + dx * stick.radius,
        y: y + dy * stick.radius,
        radius: stick.knob_radius,
        held?: true,
        alpha: 0.9
      }
    ]
  end

  defp button_shape(control, held) do
    held? = MapSet.member?(held, control.button)

    %{
      x: control.x,
      y: control.y,
      radius: control.radius,
      label: control.label,
      held?: held?,
      alpha: if(held?, do: 1.0, else: 0.55)
    }
  end

  defp fan(labels, {cx, cy}, point) do
    primary =
      for button <- [:a],
          Map.has_key?(labels, button),
          do: %{button: :a, x: cx, y: cy, radius: point.(@primary_radius), label: labels[:a]}

    others =
      for button <- [:x, :y, :b | @bumpers], Map.has_key?(labels, button) do
        {dx, dy} = @places[button]
        reach = if button in @bumpers, do: @outer_fan, else: @fan

        %{
          button: button,
          x: cx + dx * point.(reach),
          y: cy + dy * point.(reach),
          radius: point.(@button_radius),
          label: labels[button]
        }
      end

    primary ++ others
  end

  defp menu(%{start: label}, width, top, point) do
    [
      %{
        button: :start,
        x: width / 2,
        y: top + point.(@margin + @menu_radius),
        radius: point.(@menu_radius),
        label: label
      }
    ]
  end

  defp menu(_labels, _width, _top, _point), do: []

  defp letter(:left_bumper), do: "LB"
  defp letter(:right_bumper), do: "RB"
  defp letter(button), do: button |> Atom.to_string() |> String.upcase()

  defp words(action),
    do: action |> Atom.to_string() |> String.replace("_", " ") |> String.upcase()

  defp finger(%{phase: :began} = touch, {pad, pointers}) do
    cond do
      button = button_at(pad, touch, @reach) ->
        {%{pad | fingers: Map.put(pad.fingers, touch.id, {:button, button})}, pointers}

      button = near_miss(pad, touch) ->
        {%{pad | fingers: Map.put(pad.fingers, touch.id, {:button, button})}, pointers}

      side(pad, touch) == :stick and not stick_taken?(pad) ->
        stick = %{pad.stick | origin: at(touch), knob: {0.0, 0.0}}
        {%{pad | stick: stick, fingers: Map.put(pad.fingers, touch.id, :stick)}, pointers}

      side(pad, touch) == :buttons and pad.buttons == :move and has_fan?(pad) ->
        pad = fan_moved(pad, at(touch))
        {%{pad | fingers: Map.put(pad.fingers, touch.id, {:button, :a})}, pointers}

      true ->
        {%{pad | fingers: Map.put(pad.fingers, touch.id, :pointer)},
         [{:down, at(touch)} | pointers]}
    end
  end

  defp finger(%{phase: :moved} = touch, {pad, pointers}) do
    case Map.get(pad.fingers, touch.id) do
      :stick -> {%{pad | stick: dragged(pad.stick, at(touch))}, pointers}
      {:button, button} -> {slid(pad, touch, button), pointers}
      :pointer -> {pad, [{:move, at(touch)} | pointers]}
      nil -> {pad, pointers}
    end
  end

  defp finger(touch, {pad, pointers}) do
    fingers = Map.delete(pad.fingers, touch.id)

    case Map.get(pad.fingers, touch.id) do
      :stick -> {%{pad | fingers: fingers, stick: settled(pad.stick)}, pointers}
      :pointer -> {%{pad | fingers: fingers}, [{:up, at(touch)} | pointers]}
      _other -> {%{pad | fingers: fingers}, pointers}
    end
  end

  defp side(%{screen: {width, height}, hand: hand}, %{x: x, y: y}) do
    across = if hand == :right, do: x / width, else: 1 - x / width

    cond do
      y < height * 0.25 -> :neither
      across < 0.45 -> :stick
      across > 0.55 -> :buttons
      true -> :neither
    end
  end

  defp near_miss(pad, touch),
    do: if(side(pad, touch) == :buttons, do: button_at(pad, touch, @near_miss))

  defp has_fan?(pad), do: Enum.any?(pad.controls, &(&1.button == :a))

  defp fan_moved(pad, {x, y}) do
    %{x: ax, y: ay} = Enum.find(pad.controls, &(&1.button == :a))
    {dx, dy} = {x - ax, y - ay}

    controls =
      Enum.map(pad.controls, fn
        %{button: :start} = menu -> menu
        control -> %{control | x: control.x + dx, y: control.y + dy}
      end)

    %{pad | controls: controls}
  end

  defp settled(stick), do: %{stick | origin: nil, knob: {0.0, 0.0}}

  defp stick_taken?(pad), do: Enum.any?(pad.fingers, fn {_id, held} -> held == :stick end)

  defp dragged(%{origin: {ox, oy}, radius: radius} = stick, {x, y}) do
    {dx, dy} = {x - ox, y - oy}
    length = :math.sqrt(dx * dx + dy * dy)

    if length > radius do
      {ux, uy} = {dx / length, dy / length}
      %{stick | origin: {x - ux * radius, y - uy * radius}, knob: {ux, uy}}
    else
      %{stick | knob: {dx / radius, dy / radius}}
    end
  end

  defp slid(pad, touch, button) do
    case button_at(pad, touch, @reach) do
      other when other not in [nil, button] ->
        %{pad | fingers: Map.put(pad.fingers, touch.id, {:button, other})}

      _same ->
        pad
    end
  end

  defp button_at(pad, %{x: x, y: y}, reach) do
    pad.controls
    |> Enum.map(&{&1, :math.sqrt(:math.pow(x - &1.x, 2) + :math.pow(y - &1.y, 2))})
    |> Enum.filter(fn {control, distance} -> distance <= control.radius * reach end)
    |> Enum.min_by(fn {_control, distance} -> distance end, fn -> nil end)
    |> case do
      nil -> nil
      {control, _distance} -> control.button
    end
  end

  defp holding(pad) do
    buttons = for {_id, {:button, button}} <- pad.fingers, into: MapSet.new(), do: button
    MapSet.union(buttons, directions(pad.stick))
  end

  defp directions(%{origin: nil}), do: MapSet.new()

  defp directions(%{knob: {dx, dy}}) do
    [
      dx <= -@across && :dpad_left,
      dx >= @across && :dpad_right,
      dy <= -@upright && :dpad_up,
      dy >= @upright && :dpad_down
    ]
    |> Enum.filter(& &1)
    |> MapSet.new()
  end

  defp changes(before, now) do
    released = before |> MapSet.difference(now) |> Enum.map(&event(&1, false))
    pressed = now |> MapSet.difference(before) |> Enum.map(&event(&1, true))
    released ++ pressed
  end

  defp event(button, pressed?), do: %{type: :button, device: 0, button: button, pressed: pressed?}

  defp at(%{x: x, y: y}), do: {x / 1, y / 1}
end
