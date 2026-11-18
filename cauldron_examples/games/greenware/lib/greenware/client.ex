defmodule Greenware.Client do
  @moduledoc """
  Greenware's client: a hand-painted picture in every front end, the game's own title,
  summary and menus, and the same world in a terminal, a window, a Mac app, an iPhone
  or an Android phone.

      mix greenware
      mix greenware.desktop
      mix cauldron_native.build macos --run
  """

  use Cauldron2D.Client.Game

  alias Cauldron.Menu
  alias Greenware.{Art, Game, Progress, Render, Sound}

  @impl true
  def title, do: %{name: "GREENWARE", tagline: "a stop-motion story about mending"}

  @impl true
  def atlas, do: Art.install_atlas()

  @impl true
  def actions do
    [:left, :right, :up, :down, :interact, :test, :reset, :undo, :hint, :back] ++
      Enum.map(1..7, &String.to_atom("tool_#{&1}"))
  end

  @impl true
  def keymaps do
    tools = %{
      tool_1: [:"1"],
      tool_2: [:"2"],
      tool_3: [:"3"],
      tool_4: [:"4"],
      tool_5: [:"5"],
      tool_6: [:"6"],
      tool_7: [:"7"]
    }

    common = %{
      interact: [:enter, :" ", {:mouse, :left}],
      test: [:t],
      reset: [:r],
      undo: [:z],
      hint: [:h],
      back: [:q, :backspace]
    }

    [
      arrows:
        Map.merge(
          %{
            left: [:left, :a],
            right: [:right, :d],
            up: [:up, :w],
            down: [:down, :s]
          },
          Map.merge(common, tools)
        ),
      wasd:
        Map.merge(
          %{
            left: [:a, :left],
            right: [:d, :right],
            up: [:w, :up],
            down: [:s, :down]
          },
          Map.merge(common, tools)
        )
    ]
  end

  @impl true
  def toggles, do: []

  @impl true
  def holds, do: [{:left, 140}, {:right, 140}, {:up, 140}, {:down, 140}]

  @impl true
  def steering, do: []

  @impl true
  def start, do: {:play, :campaign, title: true}

  @impl true
  def chat?, do: false

  @impl true
  def fronts(_props), do: %{title: Greenware.Title, summary: Greenware.Summary}

  @impl true
  def options, do: %{text_speed: :normal, guided: false, reduced_motion: false}

  @impl true
  def client_keys do
    %{
      menu: :escape,
      back: nil,
      title: nil,
      pause: nil,
      settings: nil,
      settings_menu: nil,
      guide: nil,
      hints: nil,
      talk: nil,
      watch: nil,
      team: nil,
      projection: nil,
      turn_left: nil,
      turn_right: nil,
      zoom_in: nil,
      zoom_out: nil,
      zoom_reset: nil
    }
  end

  @impl true
  def look, do: %{projection: :picture, native: {1280, 720}}

  @impl true
  def worlds(_props) do
    [
      %{
        id: :campaign,
        name: "THE BAKE",
        world: {Game, [hz: 12]},
        players: 0,
        humans: [],
        note: "one clay figure, one cold kiln"
      }
    ]
  end

  @impl true
  def join_props(%{settings: settings}) do
    %{options: Map.get(settings, :options, %{})}
  end

  @impl true
  def scene(view, look) do
    %{
      picture: fn size, _aspect -> Render.frame_fit(view, look, size) end,
      native: Greenware.Platform.native_size(),
      focus: {0.0, 0.0},
      bounds: {1, 1},
      cell: fn _ -> :void end,
      subject: :greenware,
      screen: []
    }
  end

  @impl true
  def open_menu(settings), do: Greenware.Menus.pause(settings)

  @impl true
  def menu_event(menu, event, settings) do
    case click_point(event) do
      nil -> Menu.event(menu, event, settings)
      point -> Greenware.Menus.click(menu, point, settings, {44, 80, 260}, 7)
    end
  end

  defp click_point({:mouse, %{type: :mouse_down, at: at}}), do: at
  defp click_point({:mouse, %{type: :mouse_down, x: x, y: y}}), do: {x, y}
  defp click_point(_), do: nil

  @impl true
  def outcome(view), do: Game.outcome(view)

  @impl true
  def listener(_view), do: nil

  @impl true
  def audio, do: [rate: 44_100]

  @impl true
  def sounds, do: &Sound.voice/1

  @impl true
  def music, do: Sound.pieces()

  @impl true
  def cue(view, screen), do: Sound.cue(view, screen)

  @impl true
  def home, do: :greenware

  def progress?, do: Progress.exists?()
end
