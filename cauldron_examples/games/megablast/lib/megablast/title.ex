defmodule Megablast.Title do
  @moduledoc """
  The title, a `Cauldron.Front`: the painting of the ship blasting up the hive toward
  the Queen, the name in chrome letters, and the title's menu (`Megablast.Menus.title/1`).
  """

  @behaviour Cauldron.Front

  alias Cauldron.Menu
  alias Cauldron2D.Menu.Layout
  alias Megablast.{Art, Menus, Sound}

  @chrome {200, 220, 255}
  @gold {255, 214, 110}
  @cyan {110, 230, 255}
  @ink {6, 4, 16}

  @impl true
  def init(_screen, context), do: %{menu: Menus.title(context.settings), clock: 0}

  @impl true
  def tick(state, ms), do: %{state | clock: state.clock + ms}

  @impl true
  def event(state, event, settings) do
    reply = Menu.event(state.menu, event, settings)
    state = %{state | menu: reply.menu || Menus.title(reply.settings)}

    %{state: state, settings: reply.settings}
    |> Map.merge(Map.take(reply, [:sounds]))
    |> then(fn out ->
      case Map.get(reply, :request) do
        {:go, move} -> Map.put(out, :go, move)
        _none -> out
      end
    end)
  end

  @impl true
  def scene(state) do
    %{
      focus: {8.0, 6.0},
      bounds: {16, 12},
      cell: fn _at -> :void end,
      movers: [],
      layers: [
        Cauldron2D.Parallax.panorama(
          name: :title_art,
          art: :title_art,
          size: {16, 12},
          at: {0, 0},
          wrap: :none,
          factor: {1.0, 1.0},
          void: :opaque
        )
      ],
      screen: screen(state)
    }
  end

  @impl true
  def cue(_state), do: Sound.cue(:title)

  defp screen(state) do
    name = "MEGABLAST"
    width = text_width(name) * 3
    shine = if rem(div(state.clock, 120), 12) == 0, do: {255, 255, 255}, else: @chrome
    keys = "ARROWS CHOOSE   FIRE PICKS   ESC BACK"

    [
      {:text, :pixel, name, {-div(width, 2), -86},
       anchor: :centre, pivot: :top_left, colour: shine, shadow: @ink, scale: 3},
      {:text, :pixel, "FIVE STAGES UP THE LIVING LANE",
       {-tw("FIVE STAGES UP THE LIVING LANE"), -58},
       anchor: :centre, pivot: :top_left, colour: @cyan, outline: @ink},
      {:text, :pixel, keys, {-tw(keys), 84},
       anchor: :centre, pivot: :top_left, colour: @chrome, outline: @ink}
    ] ++
      Layout.items(state.menu, Art.name(),
        font: :pixel,
        panel: {:frame, 5},
        cursor: :cursor,
        slider: {:bar_track, :bar_shield},
        at: {0, 30},
        width: 168,
        rows: 6,
        row: 12,
        padding: 9,
        outline: @ink,
        colours: %{text: @chrome, focused: @gold, value: @cyan, title: @gold, prompt: @gold}
      )
  end

  defp tw(words), do: div(text_width(words), 2)

  defp text_width(words),
    do: Cauldron2D.Font.width(Cauldron2D.Atlas.font!(Art.name(), :pixel), words)
end
