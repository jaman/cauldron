defmodule Beast.Summary do
  @moduledoc """
  The end of the journey, a `Cauldron.Front`: the beast freed, its score and how many
  times it fell, the best journeys (`Cauldron.Scores`), and three letters to sign a score
  that earns its place. Its menu begins again or goes back to the title.
  """

  @behaviour Cauldron.Front

  alias Beast.{Art, Sound}
  alias Cauldron.Menu
  alias Cauldron.Menu.Item
  alias Cauldron.Scores
  alias Cauldron2D.Menu.Layout

  @bone {240, 228, 200}
  @blood {230, 60, 70}
  @gold {255, 214, 110}
  @ink {14, 6, 8}
  @sounds %{move: :menu_move, change: :menu_move, choose: :menu_choose, back: :menu_back}

  @impl true
  def init(_screen, context) do
    outcome = context.outcome || %{score: 0, deaths: 0}
    table = Scores.read(:beast)

    %{
      outcome: outcome,
      table: table,
      menu: menu(Scores.qualifies?(table, Map.get(outcome, :score, 0)), context.settings),
      clock: 0
    }
  end

  @impl true
  def tick(state, ms), do: %{state | clock: state.clock + ms}

  @impl true
  def event(state, event, settings) do
    reply = Menu.event(state.menu, event, settings)
    state = %{state | menu: reply.menu || menu(false, reply.settings)}

    case Map.get(reply, :request) do
      :sign -> signed(state, reply)
      {:go, move} -> %{state: state, settings: reply.settings, go: move}
      nil -> %{state: state, settings: reply.settings}
    end
    |> Map.merge(Map.take(reply, [:sounds]))
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
          name: :sky,
          art: Art.fallback(:plain_sky_tile, :frame),
          size: {32, 9},
          wrap: :x,
          factor: {0.0, 0.0},
          void: :opaque
        )
      ],
      screen: screen(state)
    }
  end

  @impl true
  def cue(_state), do: Sound.cue(:title)

  defp signed(state, reply) do
    initials =
      reply.settings |> Map.get(:options, %{}) |> Map.get(:initials, "AAA") |> String.upcase()

    table = Scores.add(state.table, %{initials: initials, score: state.outcome.score, region: 4})
    Scores.write(:beast, table)
    %{state: %{state | table: table, menu: menu(false, reply.settings)}, settings: reply.settings}
  end

  defp menu(true, settings) do
    pages = %{
      main: %{
        title: "A PLACE AMONG THE LEGENDS",
        items: [
          Item.text("YOUR LETTERS", [:options, :initials], max: 3, default: "AAA"),
          Item.action("CARVE IT", {:request, :sign})
        ],
        back: :stay
      }
    }

    Menu.open(pages, settings, sounds: @sounds)
  end

  defp menu(false, settings) do
    pages = %{
      main: %{
        title: "",
        items: [
          Item.action("BEGIN AGAIN", {:request, {:go, :again}}),
          Item.action("TO THE TITLE", {:request, {:go, :title}})
        ],
        back: {:request, {:go, :title}}
      }
    }

    Menu.open(pages, settings, sounds: @sounds)
  end

  defp screen(state) do
    [
      big("ZELEK FALLS", -86, @gold),
      centred("THE BEAST IS FREE", -58, @bone),
      centred(
        "SCORE #{state.outcome.score}    FELL #{Map.get(state.outcome, :deaths, 0)} TIMES",
        -46,
        @blood
      )
    ] ++
      table(state.table) ++
      Layout.items(state.menu, Art.name(),
        font: :pixel,
        panel: {:frame, 5},
        cursor: :cursor,
        at: {0, 66},
        width: 220,
        rows: 3,
        row: 12,
        padding: 8,
        outline: @ink,
        colours: %{text: @bone, focused: @gold, value: @blood, title: @gold, prompt: @gold}
      )
  end

  defp table(entries) do
    entries
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, place} ->
      centred(
        "#{place}. #{String.pad_trailing(entry.initials, 3)}  #{entry.score}",
        -34 + place * 9,
        if(place == 1, do: @gold, else: @bone)
      )
    end)
  end

  defp big(words, y, colour) do
    width = width(words) * 2

    {:text, :pixel, words, {-div(width, 2), y},
     anchor: :centre, pivot: :top_left, colour: colour, shadow: @ink, scale: 2}
  end

  defp centred(words, y, colour),
    do:
      {:text, :pixel, words, {-div(width(words), 2), y},
       anchor: :centre, pivot: :top_left, colour: colour, outline: @ink}

  defp width(words),
    do: Cauldron2D.Font.width(Cauldron2D.Atlas.font!(Art.name(), :pixel), words)
end
