defmodule Cauldron2D.Drafter.Client.Settings do
  @moduledoc """
  A player's settings: which keys do what, whether the pointer steers, how loud things
  are, how the world is drawn (`display`, and `drawing`: on the graphics card or not), and
  the game's own options (`Cauldron.Client.Game`'s
  `options/0`, its defaults under whatever was saved), and which player each game
  controller plays: `pads`, a map from a controller's name to a player number or `:none`
  (`Cauldron.Client.Controllers`). `controllers` lists the controllers
  connected now, each `%{name, player}`; the client keeps it up to date for the game's
  menus to show, and it is not saved.

  Kept per kind of client — the terminal, a desktop, a browser, a phone: a kind is any
  atom, `:terminal` the default — on disk under
  `$XDG_CONFIG_HOME/<home>/<player>.settings` for the terminal and
  `<player>.<kind>.settings` for another kind, `<home>` being the game's
  `Cauldron.Client.Game.home/1` (or under `~/.config`), and, when the player has an
  account, in its props as well: `settings` for the terminal, `settings_<kind>` for
  another kind. `load/4` reads the file over any account props, from the folder named
  after the game's title (`title_folder/1`) when the home has none; `save/5` writes both,
  the file under the home.

      settings = Cauldron2D.Drafter.Client.Settings.load(MyGame.Client, "alice", account_props)
      settings.bindings[:launch]
      Cauldron2D.Drafter.Client.Settings.load(MyGame.Client, "alice", account_props, kind: :desktop)
  """

  alias Cauldron.Client.Game
  alias Cauldron.Input
  alias Cauldron.Menu.Item

  @type t :: %__MODULE__{
          preset: atom(),
          bindings: Input.keymap(),
          pointer: boolean(),
          sfx: float(),
          music: float(),
          display: display(),
          drawing: drawing(),
          fps: fps(),
          options: map(),
          pads: %{String.t() => pos_integer() | :none},
          controllers: [%{name: String.t(), player: pos_integer() | nil}]
        }

  defstruct preset: nil,
            bindings: %{},
            pointer: true,
            sfx: 0.85,
            music: 0.35,
            display: :auto,
            drawing: :auto,
            fps: :auto,
            options: %{},
            pads: %{},
            controllers: []

  @typedoc "How the world is drawn: pixels where the terminal has them, else glyphs; braille; block characters of a glyph set; or glyphs."
  @type display :: :auto | :braille | :half | :quad | :sextant | :octant | :glyphs

  @typedoc """
  Where a game that can be drawn by the graphics card is drawn: `:auto` on the card in the
  pane when there is one, `:software` never on the card, `:pane` on the card in the pane,
  `:window` on the card in a window of its own.
  """
  @type drawing :: :auto | :software | :pane | :window

  @typedoc "Frames per second, or `:auto` for the terminal's best."
  @type fps :: :auto | pos_integer()

  @cell_sets [:half, :quad, :sextant, :octant]
  @displays [:auto, :braille | @cell_sets] ++ [:glyphs]
  @drawings [:auto, :software, :pane, :window]

  @doc """
  Settings for `game` with `overrides` applied over the game's first preset.

  An override naming a preset the game no longer has starts from the first preset, and
  its bindings are dropped with it.
  """
  @spec new(module(), map()) :: t()
  def new(game, overrides \\ %{}) do
    presets = presets(game)
    overrides = current(overrides, presets)
    preset = Map.get(overrides, :preset, List.first(presets))
    base = keymap(game, preset)
    levels = Cauldron.Audio.default_levels()

    %__MODULE__{
      preset: preset,
      bindings: Map.merge(base, Map.get(overrides, :bindings, %{})),
      pointer: Map.get(overrides, :pointer, true),
      sfx: Map.get(overrides, :sfx, levels.sfx) / 1,
      music: Map.get(overrides, :music, levels.music) / 1,
      display: overrides |> Map.get(:display, :auto) |> display_option(),
      drawing: overrides |> Map.get(:drawing, :auto) |> drawing_option(),
      options:
        Map.merge(
          Game.optional(game, :options, [], %{}),
          Map.get(overrides, :options, %{})
        ),
      fps: Map.get(overrides, :fps, :auto),
      pads: Map.get(overrides, :pads, %{})
    }
  end

  @typedoc "One line of the settings screen: the preset, an action's binding, or a switch or level."
  @type item ::
          :preset
          | {:action, Input.action()}
          | :pointer
          | :sfx
          | :music
          | :display
          | :drawing
          | :fps

  @doc """
  The settings screen's items for `game`, top to bottom; `:drawing` is there when the
  build has the graphics card renderer (`cauldron_gpu`).
  """
  @spec items(module()) :: [item()]
  def items(game) do
    [:preset] ++
      Enum.map(game.actions(), &{:action, &1}) ++
      [:pointer, :sfx, :music, :display] ++ drawing_item() ++ [:fps]
  end

  @doc """
  Rows for a game's own options menu that change how the client draws, for a game that
  keeps its players in its own menus rather than the settings screen: display, drawing
  (when the build has the graphics card renderer) and frame rate, as
  `Cauldron.Menu.Item` choices over these settings. The client saves and applies what
  they change, as it does the settings screen's. `text` restyles every label and choice
  (`&String.upcase/1` for a font with capitals only).

      [Item.slider("Music", [:music], {0.0, 1.0})] ++
        Cauldron2D.Drafter.Client.Settings.menu_items(MyGame.Client)
  """
  @spec menu_items(module(), (String.t() -> String.t())) :: [Cauldron.Menu.Item.t()]
  def menu_items(game, text \\ & &1) do
    [Item.choice(text.("Display"), [:display], labelled(@displays, &display_text/1, text))] ++
      drawing_rows(text) ++
      [Item.choice(text.("Frame rate"), [:fps], labelled(frame_rates(game), &fps_text/1, text))]
  end

  defp drawing_rows(text) do
    if Code.ensure_loaded?(CauldronGPU.Host),
      do: [Item.choice(text.("Drawing"), [:drawing], labelled(@drawings, &drawing_text/1, text))],
      else: []
  end

  defp labelled(values, describe, text), do: Enum.map(values, &{&1, text.(describe.(&1))})

  defp display_text(:auto), do: "pixels"
  defp display_text(:half), do: "half blocks"
  defp display_text(:quad), do: "quarter blocks"
  defp display_text(display), do: Atom.to_string(display)

  defp drawing_text(:auto), do: "card if there is one"
  defp drawing_text(:software), do: "software"
  defp drawing_text(:pane), do: "card, in the pane"
  defp drawing_text(:window), do: "card, in a window"

  defp fps_text(:auto), do: "auto"
  defp fps_text(fps), do: "#{fps} fps"

  defp drawing_item, do: if(Code.ensure_loaded?(CauldronGPU.Host), do: [:drawing], else: [])

  defp drawing_option(drawing) when drawing in @drawings, do: drawing
  defp drawing_option(_other), do: :auto

  @doc "The next or previous drawing choice, in the order auto, software, pane, window, wrapping."
  @spec step_drawing(t(), -1 | 1) :: t()
  def step_drawing(%__MODULE__{} = settings, delta),
    do: %{settings | drawing: step(@drawings, settings.drawing, delta)}

  defp display_option(:text), do: :glyphs
  defp display_option(display) when display in @displays, do: display
  defp display_option(_other), do: :auto

  @doc "The next or previous display choice, in the order auto, braille, half, quad, sextant, octant, glyphs, wrapping."
  @spec step_display(t(), -1 | 1) :: t()
  def step_display(%__MODULE__{} = settings, delta),
    do: %{settings | display: step(@displays, settings.display, delta)}

  @doc "The next or previous frame rate choice of `game`'s `frame_rates/1`, wrapping."
  @spec step_fps(t(), module(), -1 | 1) :: t()
  def step_fps(%__MODULE__{} = settings, game, delta),
    do: %{settings | fps: step(frame_rates(game), settings.fps, delta)}

  defp step(choices, current, delta) do
    index = Enum.find_index(choices, &(&1 == current)) || 0
    Enum.at(choices, Integer.mod(index + delta, length(choices)))
  end

  @doc """
  The frame rate to draw at: the setting, or for `:auto` the terminal's best — 12 where
  every frame is an inline image (iTerm2's own, sixel), 20 where every frame is a kitty
  picture sent whole (a terminal without placements) or the session is served over ssh
  (`link` `:ssh`), 60 where the graphics card's frames reach a local kitty terminal through
  shared memory (`card_frames?`), 30 elsewhere.
  """
  @spec frame_rate(t(), atom() | nil | :unprobed, boolean(), :local | :ssh, boolean()) ::
          pos_integer()
  def frame_rate(settings, protocol, placements? \\ true, link \\ :local, card_frames? \\ false)

  def frame_rate(%__MODULE__{fps: :auto}, protocol, _placements?, _link, _card_frames?)
      when protocol in [:iterm2, :sixel],
      do: 12

  def frame_rate(%__MODULE__{fps: :auto}, :kitty, false, _link, _card_frames?), do: 20
  def frame_rate(%__MODULE__{fps: :auto}, _protocol, _placements?, :ssh, _card_frames?), do: 20
  def frame_rate(%__MODULE__{fps: :auto}, :kitty, true, :local, true), do: 60
  def frame_rate(%__MODULE__{fps: :auto}, _protocol, _placements?, :local, _card_frames?), do: 30
  def frame_rate(%__MODULE__{fps: fps}, _protocol, _placements?, _link, _card_frames?), do: fps

  @doc "The surface mode for the display setting: `nil` lets the terminal decide."
  @spec surface_mode(t()) :: nil | :braille | :half | :quad | :sextant | :octant | :text
  def surface_mode(%__MODULE__{display: :auto}), do: nil
  def surface_mode(%__MODULE__{display: :glyphs}), do: :text
  def surface_mode(%__MODULE__{display: display}), do: display

  @doc "The presets in the order the settings screen offers them: the game's `keymaps/0` order for a keyword list, by name for a map."
  @spec presets(module()) :: [atom()]
  def presets(game) do
    case game.keymaps() do
      keymaps when is_map(keymaps) -> keymaps |> Map.keys() |> Enum.sort()
      keymaps -> Keyword.keys(keymaps)
    end
  end

  defp current(%{preset: preset} = overrides, presets) do
    if preset in presets, do: overrides, else: Map.drop(overrides, [:preset, :bindings])
  end

  defp current(overrides, _presets), do: overrides

  defp keymap(game, preset) do
    case game.keymaps() do
      keymaps when is_map(keymaps) -> Map.get(keymaps, preset, %{})
      keymaps -> Keyword.get(keymaps, preset, %{})
    end
  end

  @doc "The frame rates the settings screen offers: the game's `frame_rates/0`, else `:auto`, 15, 30, 50 and 60."
  @spec frame_rates(module()) :: [fps()]
  def frame_rates(game), do: Game.frame_rates(game)

  @doc "Switch to `preset` of `game`, dropping individual rebindings."
  @spec choose_preset(t(), module(), atom()) :: t()
  def choose_preset(%__MODULE__{} = settings, game, preset) do
    %{settings | preset: preset, bindings: keymap(game, preset)}
  end

  @doc "Bind `action` to `key` alone, in place of whatever it had."
  @spec rebind(t(), Input.action(), Input.key_spec()) :: t()
  def rebind(%__MODULE__{} = settings, action, key) do
    %{settings | bindings: Map.put(settings.bindings, action, [key])}
  end

  @doc "Add `key` to what `action` is bound to, after the keys it has; a key already there is not added twice."
  @spec bind(t(), Input.action(), Input.key_spec()) :: t()
  def bind(%__MODULE__{} = settings, action, key) do
    keys = Map.get(settings.bindings, action, [])
    keys = if key in keys, do: keys, else: keys ++ [key]
    %{settings | bindings: Map.put(settings.bindings, action, keys)}
  end

  @doc "Drop the last key `action` is bound to; an action with no keys is unchanged."
  @spec unbind_last(t(), Input.action()) :: t()
  def unbind_last(%__MODULE__{} = settings, action) do
    keys = settings.bindings |> Map.get(action, []) |> Enum.drop(-1)
    %{settings | bindings: Map.put(settings.bindings, action, keys)}
  end

  @doc "Move a 0.0–1.0 level by `delta`, clamped."
  @spec nudge(t(), :sfx | :music, number()) :: t()
  def nudge(%__MODULE__{} = settings, level, delta) when level in [:sfx, :music] do
    Map.update!(settings, level, fn current ->
      current |> Kernel.+(delta) |> max(0.0) |> min(1.0) |> Float.round(2)
    end)
  end

  @doc "The map kept in account props and on disk."
  @spec to_props(t()) :: map()
  def to_props(%__MODULE__{} = settings),
    do: settings |> Map.from_struct() |> Map.delete(:controllers)

  @doc "Settings for `player` of `game` on a `:kind` of client (default `:terminal`): the file on disk over `account_props` over the defaults."
  @spec load(module(), String.t(), map(), keyword()) :: t()
  def load(game, player, account_props \\ %{}, opts \\ []) do
    kind = Keyword.get(opts, :kind, :terminal)

    file = Cauldron.Paths.existing(path(game, player, kind), title_path(game, player, kind))

    stored =
      case File.read(file) do
        {:ok, binary} -> :erlang.binary_to_term(binary, [:safe])
        {:error, _} -> %{}
      end

    new(game, Map.merge(Map.get(account_props, prop_key(kind), %{}), stored))
  end

  @doc "Write the settings to disk, and to the account when `accounts` is given, for a `:kind` of client (default `:terminal`)."
  @spec save(t(), module(), String.t(), GenServer.server() | nil, keyword()) :: :ok
  def save(%__MODULE__{} = settings, game, player, accounts \\ nil, opts \\ []) do
    kind = Keyword.get(opts, :kind, :terminal)
    file = path(game, player, kind)
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, :erlang.term_to_binary(to_props(settings)))

    if accounts,
      do: Drafter.Accounts.put_props(accounts, player, %{prop_key(kind) => to_props(settings)})

    :ok
  end

  @doc "The account prop a kind's settings are kept under: `:settings` for the terminal, `:settings_<kind>` for another."
  @spec prop_key(atom()) :: atom()
  def prop_key(:terminal), do: :settings
  def prop_key(kind), do: :"settings_#{kind}"

  @doc "Where `player`'s settings for `game` are written, for a kind of client (default `:terminal`): under the game's home."
  @spec path(module(), String.t(), atom()) :: Path.t()
  def path(game, player, kind \\ :terminal),
    do: Cauldron.Paths.config(Game.home(game), file_name(player, kind))

  @doc """
  The folder under the configuration directory named after `game`'s title in lower case,
  runs of other characters as `_`. `load/4` and `Cauldron2D.Drafter.Launcher.load/1` read
  from it when the game's home has nothing.
  """
  @spec title_folder(module()) :: Path.t()
  def title_folder(game) do
    name = game.title().name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "_")
    Cauldron.Paths.config(name)
  end

  defp title_path(game, player, kind), do: Path.join(title_folder(game), file_name(player, kind))

  defp file_name(player, :terminal), do: "#{player}.settings"
  defp file_name(player, kind), do: "#{player}.#{kind}.settings"

  @doc "The keys bound to `action`, as text for a screen."
  @spec keys_text(t(), Input.action()) :: String.t()
  def keys_text(%__MODULE__{bindings: bindings}, action) do
    bindings |> Map.get(action, []) |> Enum.map_join(", ", &key_text/1)
  end

  defp key_text({:mouse, button}),
    do: "mouse " <> String.replace(Atom.to_string(button), "_", " ")

  defp key_text({key, mods}),
    do: Enum.map_join(mods, "+", &Atom.to_string/1) <> "+" <> key_text(key)

  defp key_text(:" "), do: "space"
  defp key_text(key), do: Atom.to_string(key)
end
