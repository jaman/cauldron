defmodule CisternComplete.Summary do
  @moduledoc """
  The end of a keeper's storm, a `Cauldron.Front`: the dusk backdrop with the Squall
  grinning, what was poured and scored, the town's best keepers (`Cauldron.Scores`)
  and, when the score earns a place among them, three letters to sign it with. Its menu
  goes again or back to the title.
  """

  @behaviour Cauldron.Front

  alias Cauldron.Menu
  alias Cauldron.Menu.Item
  alias Cauldron.Scores
  alias Cauldron2D.Menu.Layout
  alias CisternComplete.{Art, Scene, Sound}

  @gold {255, 214, 110}
  @cream {245, 232, 210}
  @water {150, 216, 255}
  @ink {28, 16, 22}
  @sounds %{move: :menu_move, change: :menu_move, choose: :menu_choose, back: :menu_back}

  @impl true
  def init(_screen, context) do
    outcome = context.outcome || %{score: 0, water: 0, best: 1}
    table = Scores.read(:cistern_complete)
    signing? = Scores.qualifies?(table, Map.get(outcome, :score, 0))

    %{
      outcome: outcome,
      table: table,
      signed?: not signing?,
      menu: menu(signing?, context.settings),
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
      cell: &Scene.cell/1,
      movers: [{:squall_grin, {7.5, 1.0 + :math.sin(state.clock / 400) * 0.12}}],
      layers: [
        Cauldron2D.Parallax.panorama(
          name: :backdrop,
          art: :backdrop,
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

  defp signed(state, reply) do
    initials =
      reply.settings |> Map.get(:options, %{}) |> Map.get(:initials, "AAA") |> String.upcase()

    entry = %{initials: initials, score: state.outcome.score, storm: state.outcome.best}
    table = Scores.add(state.table, entry)
    Scores.write(:cistern_complete, table)

    %{
      state: %{state | table: table, signed?: true, menu: menu(false, reply.settings)},
      settings: reply.settings
    }
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
          Item.action("ANOTHER STORM", {:request, {:go, :again}}),
          Item.action("TO THE TITLE", {:request, {:go, :title}})
        ],
        back: {:request, {:go, :title}}
      }
    }

    Menu.open(pages, settings, sounds: @sounds)
  end

  defp screen(state) do
    lines = [
      {"THE LAST JAR BREAKS", @gold, -52},
      {"#{state.outcome.water} DROPS POURED    #{state.outcome.score} POINTS", @cream, -38},
      {"STORM #{state.outcome.best} AT THE MOST", @water, -27}
    ]

    Enum.map(lines, fn {words, colour, y} -> centred(words, colour, y) end) ++
      table(state.table) ++
      Layout.items(state.menu, Art.name(),
        font: :pixel,
        panel: {:frame, 5},
        cursor: :cursor,
        at: {0, 70},
        width: 200,
        rows: 3,
        row: 12,
        padding: 8,
        outline: @ink,
        colours: %{text: @cream, focused: @gold, value: @water, title: @gold, prompt: @gold}
      )
  end

  defp table(entries) do
    entries
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, place} ->
      words =
        "#{place}. #{String.pad_trailing(entry.initials, 3)}  #{entry.score}  STORM #{entry.storm}"

      centred(words, if(place == 1, do: @gold, else: @cream), -12 + place * 9)
    end)
  end

  defp centred(words, colour, y) do
    width = Cauldron2D.Font.width(Cauldron2D.Atlas.font!(Art.name(), :pixel), words)

    {:text, :pixel, words, {-div(width, 2), y},
     anchor: :centre, pivot: :top_left, colour: colour, outline: @ink}
  end
end
