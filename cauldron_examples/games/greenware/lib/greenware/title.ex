defmodule Greenware.Title do
  @moduledoc "The title: a lamplit workshop, a small figure, a cat, and the game's own menu."

  @behaviour Cauldron.Front

  alias Cauldron.Menu
  alias Greenware.{Menus, Progress, Render}

  @impl true
  def init(_screen, context) do
    %{menu: Menus.title(context.settings), settings: context.settings, clock: 0}
  end

  @impl true
  def tick(state, ms), do: %{state | clock: state.clock + ms}

  @impl true
  def event(state, event, settings) do
    reply =
      case click_point(event) do
        nil -> Menu.event(state.menu, event, settings)
        point -> Menus.click(state.menu, point, settings, {372, 140, 236}, 7)
      end

    menu = reply.menu || Menus.title(reply.settings)
    state = %{state | menu: menu, settings: reply.settings}

    base = %{state: state, settings: reply.settings}
    base = if reply[:sounds], do: Map.put(base, :sounds, reply.sounds), else: base

    case reply[:request] do
      {:go, :continue} ->
        Map.put(base, :go, :play)

      {:go, :new_game} ->
        Progress.delete()
        Map.put(base, :go, :play)

      {:go, :quit} ->
        Map.put(base, :go, :quit)

      _ ->
        base
    end
  end

  @impl true
  def scene(state) do
    %{
      picture: fn size, _aspect -> Render.title_fit(state, state.settings, size) end,
      native: Greenware.Platform.native_size(),
      focus: {0.0, 0.0},
      bounds: {1, 1},
      cell: fn _ -> :void end,
      screen: []
    }
  end

  @impl true
  def cue(_state), do: Greenware.Sound.cue(nil, :title)

  defp click_point({:mouse, %{type: :mouse_down, at: at}}), do: at
  defp click_point({:mouse, %{type: :mouse_down, x: x, y: y}}), do: {x, y}
  defp click_point(_), do: nil
end
