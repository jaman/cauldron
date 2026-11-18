defmodule Cauldron2D.Drafter.Client.WindowMouse do
  @moduledoc """
  Turns a `CauldronGPU` window's mouse events into the mouse events a drafter app gets
  from a terminal reporting the pointer in pixels: `%{type: :move | :drag | :mouse_down |
  :mouse_up | :scroll, x, y, px, modifiers}` under `:mouse`, `x` and `y` in 8 by 16 pixel
  cells and `px` the pointer in pixels.

  While the pointer is captured (`capture/1`, the window's relative mouse mode) it has no
  place in the window, so the pointer reported is the sum of the window's movements from
  where it was captured, and turning never meets the window's edge.

      iex> alias Cauldron2D.Drafter.Client.WindowMouse
      iex> {events, _mouse} = WindowMouse.events(WindowMouse.new(), {:mouse_motion, 16.0, 32.0, 4.0, 0.0}, [])
      iex> events
      [{:mouse, %{type: :move, x: 2, y: 2, px: {16, 32}, modifiers: []}}]
  """

  @type t :: %{pointer: {float(), float()}, buttons: [atom()], captured?: boolean()}
  @type window_event ::
          {:mouse_motion, number(), number(), number(), number()}
          | {:mouse_button, :down | :up, pos_integer(), number(), number()}
          | {:mouse_wheel, number(), number()}

  @cell {8, 16}

  @doc "A pointer at the window's corner, no button held, not captured."
  @spec new() :: t()
  def new, do: %{pointer: {0.0, 0.0}, buttons: [], captured?: false}

  @doc "The mouse with the pointer captured."
  @spec capture(t()) :: t()
  def capture(mouse), do: %{mouse | captured?: true}

  @doc "The mouse with the pointer let go and no button held."
  @spec release(t()) :: t()
  def release(mouse), do: %{mouse | captured?: false, buttons: []}

  @doc "The drafter events a window's mouse event gives, and the mouse after it."
  @spec events(t(), window_event(), [atom()]) :: {[Drafter.Event.t()], t()}
  def events(mouse, {:mouse_motion, x, y, dx, dy}, modifiers) do
    mouse = %{mouse | pointer: moved(mouse, {x, y}, {dx, dy})}
    {[mouse_event(mouse, motion(mouse), modifiers)], mouse}
  end

  def events(mouse, {:mouse_button, direction, number, x, y}, modifiers) do
    button = button(number)

    mouse = %{
      mouse
      | pointer: placed(mouse, {x, y}),
        buttons: pressed(mouse.buttons, direction, button)
    }

    type = if direction == :down, do: :mouse_down, else: :mouse_up
    {[mouse_event(mouse, %{type: type, button: button}, modifiers)], mouse}
  end

  def events(mouse, {:mouse_wheel, _dx, dy}, modifiers) when dy != 0 do
    direction = if dy > 0, do: :up, else: :down
    {[mouse_event(mouse, %{type: :scroll, direction: direction}, modifiers)], mouse}
  end

  def events(mouse, _event, _modifiers), do: {[], mouse}

  defp moved(%{captured?: true, pointer: {x, y}}, _at, {dx, dy}), do: {x + dx, y + dy}
  defp moved(_mouse, {x, y}, _delta), do: {x / 1, y / 1}

  defp placed(%{captured?: true, pointer: pointer}, _at), do: pointer
  defp placed(_mouse, {x, y}), do: {x / 1, y / 1}

  defp pressed(buttons, :down, button), do: [button | List.delete(buttons, button)]
  defp pressed(buttons, :up, button), do: List.delete(buttons, button)

  defp motion(%{buttons: [button | _]}), do: %{type: :drag, button: button}
  defp motion(_mouse), do: %{type: :move}

  defp mouse_event(%{pointer: {x, y}}, fields, modifiers) do
    {cell_width, cell_height} = @cell
    {px, py} = {round(x), round(y)}

    {:mouse,
     Map.merge(fields, %{
       x: div(px, cell_width),
       y: div(py, cell_height),
       px: {px, py},
       modifiers: modifiers
     })}
  end

  defp button(1), do: :left
  defp button(2), do: :middle
  defp button(3), do: :right
  defp button(_other), do: :other
end
