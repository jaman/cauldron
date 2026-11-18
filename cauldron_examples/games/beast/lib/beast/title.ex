defmodule Beast.Title do
  @moduledoc """
  The title, a `Cauldron.Front`: the painting of the beast on its cliff before the
  mage's castle, the name in bone letters, and the title's menu (`Beast.Menus.title/1`),
  with its keys named for a controller on a phone or once a controller has been used.
  """

  @behaviour Cauldron.Front

  alias Beast.{Art, Menus, Sound}
  alias Cauldron.Menu
  alias Cauldron2D.Menu.Layout

  @bone {240, 228, 200}
  @blood {230, 60, 70}
  @gold {255, 214, 110}
  @ink {14, 6, 8}
  @pad_only Mix.target() in [:ios, :android]

  @impl true
  def init(_screen, context), do: %{menu: Menus.title(context.settings), clock: 0}

  @impl true
  def tick(state, ms), do: %{state | clock: state.clock + ms}

  @impl true
  def event(state, event, settings) do
    reply = Menu.event(state.menu, event, settings)

    out = %{
      state: %{state | menu: reply.menu || Menus.title(reply.settings)},
      settings: reply.settings
    }

    out = Map.merge(out, Map.take(reply, [:sounds]))

    case Map.get(reply, :request) do
      {:go, move} -> Map.put(out, :go, move)
      _none -> out
    end
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
          art: Art.fallback(:title_art, :frame),
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
    keys = hints(@pad_only or Menu.pad?(state.menu))

    [
      {:text, :pixel, "BEAST", {-122, -90},
       anchor: :centre, pivot: :top_left, colour: @bone, shadow: @blood, scale: 3},
      {:text, :pixel, "A JOURNEY ACROSS FOUR LANDS", {-122, -62},
       anchor: :centre, pivot: :top_left, colour: @gold, outline: @ink},
      {:text, :pixel, keys, {-div(width(keys), 2), 84},
       anchor: :centre, pivot: :top_left, colour: @bone, outline: @ink}
    ] ++
      Layout.items(state.menu, Art.name(),
        font: :pixel,
        panel: {:frame, 5},
        cursor: :cursor,
        slider: {:slider_track, :slider_fill},
        at: {44, 26},
        width: 224,
        rows: 6,
        row: 12,
        padding: 9,
        outline: @ink,
        colours: %{text: @bone, focused: @gold, value: @blood, title: @gold, prompt: @gold}
      )
  end

  defp hints(true), do: "D-PAD CHOOSE   A PICKS   B BACK"
  defp hints(false), do: "ARROWS CHOOSE   STRIKE PICKS   ESC BACK"

  defp width(words),
    do: Cauldron2D.Font.width(Cauldron2D.Atlas.font!(Art.name(), :pixel), words)
end
