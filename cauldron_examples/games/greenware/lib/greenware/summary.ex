defmodule Greenware.Summary do
  @moduledoc "The screen after the last page: what happened, and the way back."

  @behaviour Cauldron.Front

  alias Cauldron.Menu
  alias Greenware.{Menus, Progress, Render}

  @impl true
  def init(_screen, context) do
    %{
      menu: Menus.summary(context.settings),
      settings: context.settings,
      clock: 0,
      outcome: Map.get(context, :outcome),
      view: Map.get(context, :view)
    }
  end

  @impl true
  def tick(state, ms), do: %{state | clock: state.clock + ms}

  @impl true
  def event(state, event, settings) do
    reply =
      case click_point(event) do
        nil -> Menu.event(state.menu, event, settings)
        point -> Menus.click(state.menu, point, settings, {380, 250, 230}, 2)
      end

    state = %{state | menu: reply.menu || Menus.summary(reply.settings), settings: reply.settings}
    base = %{state: state, settings: reply.settings}
    base = if reply[:sounds], do: Map.put(base, :sounds, reply.sounds), else: base

    case reply[:request] do
      {:go, :new_game} ->
        Progress.delete()
        Map.put(base, :go, :play)

      {:go, :title} ->
        Map.put(base, :go, :title)

      _ ->
        base
    end
  end

  @impl true
  def scene(state) do
    ending =
      case state.view do
        %{ending: %{title: title}} -> %{title: title}
        _ -> nil
      end

    %{
      picture: fn size, _aspect ->
        Render.summary_fit(%{outcome: state.outcome, ending: ending, menu: state.menu}, size)
      end,
      native: Greenware.Platform.native_size(),
      focus: {0.0, 0.0},
      bounds: {1, 1},
      cell: fn _ -> :void end,
      screen: []
    }
  end

  @impl true
  def cue(_state), do: Greenware.Sound.cue(nil, :summary)

  defp click_point({:mouse, %{type: :mouse_down, at: at}}), do: at
  defp click_point({:mouse, %{type: :mouse_down, x: x, y: y}}), do: {x, y}
  defp click_point(_), do: nil
end
