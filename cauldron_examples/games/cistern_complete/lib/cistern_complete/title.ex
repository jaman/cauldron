defmodule CisternComplete.Title do
  @moduledoc """
  The title, a `Cauldron.Front`: the painting of the keeper and the Squall over the
  dusk town, rain drifting across it, the name in large letters, and the title's menu
  (`CisternComplete.Menus.title/1`) in the game's own frame and font.
  """

  @behaviour Cauldron.Front

  alias Cauldron.Menu
  alias Cauldron2D.Menu.Layout
  alias CisternComplete.{Art, Scene, Sound}

  @gold {255, 214, 110}
  @cream {245, 232, 210}
  @ink {28, 16, 22}
  @rain 36

  @impl true
  def init(_screen, context), do: %{menu: CisternComplete.Menus.title(context.settings), clock: 0}

  @impl true
  def tick(state, ms), do: %{state | clock: state.clock + ms}

  @impl true
  def event(state, event, settings) do
    reply = Menu.event(state.menu, event, settings)
    menu = reply.menu || CisternComplete.Menus.title(reply.settings)

    %{state: %{state | menu: menu}, settings: reply.settings}
    |> put_sounds(reply)
    |> put_go(reply)
  end

  @impl true
  def scene(state) do
    %{
      focus: {8.0, 6.0},
      bounds: {16, 12},
      cell: &Scene.cell/1,
      movers: rain(state.clock),
      layers: [
        Cauldron2D.Parallax.panorama(
          name: :title_art,
          art: :title_art,
          size: {16, 11},
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

  defp put_sounds(reply, %{sounds: sounds}), do: Map.put(reply, :sounds, sounds)
  defp put_sounds(reply, _menu_reply), do: reply

  defp put_go(reply, %{request: {:go, move}}), do: Map.put(reply, :go, move)
  defp put_go(reply, _menu_reply), do: reply

  defp rain(clock) do
    for index <- 1..@rain do
      x = :erlang.phash2({:x, index}, 160) / 10
      speed = 4.0 + :erlang.phash2({:speed, index}, 30) / 10
      start = :erlang.phash2({:start, index}, 120) / 10
      y = :math.fmod(start + clock / 1000 * speed, 12.0)
      {:drop, {x, y - 1.0}}
    end
  end

  defp screen(state) do
    tagline = "THE TOWN IS DRY. A STORM HAS COME."
    keys = "ARROWS CHOOSE   ENTER PICKS   ESC BACK"

    [
      {:text, :pixel, "CISTERN", {-122, -90},
       anchor: :centre, pivot: :top_left, colour: @gold, shadow: @ink, scale: 2},
      {:text, :pixel, tagline, {-tw(tagline), 70},
       anchor: :centre, pivot: :top_left, colour: @cream, outline: @ink},
      {:text, :pixel, keys, {-tw(keys), 84},
       anchor: :centre, pivot: :top_left, colour: @cream, outline: @ink, alpha: 0.85}
    ] ++
      Layout.items(state.menu, Art.name(),
        font: :pixel,
        panel: {:frame, 5},
        cursor: :cursor,
        slider: {:fill_track, :fill_bar},
        at: {49, 18},
        width: 152,
        rows: 6,
        row: 12,
        padding: 9,
        outline: @ink,
        colours: %{
          text: @cream,
          focused: @gold,
          value: {150, 216, 255},
          title: @gold,
          prompt: @gold
        }
      )
  end

  defp tw(words), do: div(text_width(words), 2)

  defp text_width(words),
    do: Cauldron2D.Font.width(Cauldron2D.Atlas.font!(Art.name(), :pixel), words)
end
