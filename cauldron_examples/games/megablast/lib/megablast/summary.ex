defmodule Megablast.Summary do
  @moduledoc """
  The end of a flight, a `Cauldron.Front`: the score and the stage reached, the best
  pilots (`Cauldron.Scores`), and three letters to sign a score that earns its place.
  Its menu flies again or goes back to the title.
  """

  @behaviour Cauldron.Front

  alias Cauldron.Menu
  alias Cauldron.Menu.Item
  alias Cauldron.Scores
  alias Cauldron2D.Menu.Layout
  alias Megablast.{Art, Sound}

  @chrome {200, 220, 255}
  @gold {255, 214, 110}
  @cyan {110, 230, 255}
  @ink {6, 4, 16}
  @sounds %{move: :menu_move, change: :menu_move, choose: :menu_choose, back: :menu_back}

  @impl true
  def init(_screen, context) do
    outcome = context.outcome || %{score: 0, stage: 1, won?: false, title: "SHIP LOST"}
    table = Scores.read(:megablast)
    signing? = Scores.qualifies?(table, Map.get(outcome, :score, 0))
    %{outcome: outcome, table: table, menu: menu(signing?, context.settings), clock: 0}
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
          name: :backdrop,
          art: :deep_5_tile,
          size: {10, 40},
          wrap: :both,
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

    table =
      Scores.add(state.table, %{
        initials: initials,
        score: state.outcome.score,
        stage: state.outcome.stage
      })

    Scores.write(:megablast, table)
    %{state: %{state | table: table, menu: menu(false, reply.settings)}, settings: reply.settings}
  end

  defp menu(true, settings) do
    pages = %{
      main: %{
        title: "A PLACE AMONG THE BEST",
        items: [
          Item.text("YOUR LETTERS", [:options, :initials], max: 3, default: "AAA"),
          Item.action("SIGN IT", {:request, :sign})
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
          Item.action("FLY AGAIN", {:request, {:go, :again}}),
          Item.action("TO THE TITLE", {:request, {:go, :title}})
        ],
        back: {:request, {:go, :title}}
      }
    }

    Menu.open(pages, settings, sounds: @sounds)
  end

  defp screen(state) do
    title = if state.outcome.won?, do: "THE QUEEN IS DEAD", else: "SHIP LOST"

    [
      big(title, -86, @gold),
      centred("SCORE #{state.outcome.score}", -54, @chrome),
      centred("REACHED STAGE #{state.outcome.stage}", -43, @cyan)
    ] ++
      table(state.table) ++
      Layout.items(state.menu, Art.name(),
        font: :pixel,
        panel: {:frame, 5},
        cursor: :cursor,
        at: {0, 66},
        width: 210,
        rows: 3,
        row: 12,
        padding: 8,
        outline: @ink,
        colours: %{text: @chrome, focused: @gold, value: @cyan, title: @gold, prompt: @gold}
      )
  end

  defp table(entries) do
    entries
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, place} ->
      centred(
        "#{place}. #{String.pad_trailing(entry.initials, 3)}  #{entry.score}  STAGE #{entry.stage}",
        -32 + place * 9,
        if(place == 1, do: @gold, else: @chrome)
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
