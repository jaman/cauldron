defmodule Cauldron2D.Client.Game do
  @moduledoc """
  What a game gives a client — the terminal's, the browser's or the desktop's — to put
  its worlds in front of a player. One contract; every front end draws from it.

      defmodule MyGame.Client do
        @behaviour Cauldron2D.Client.Game

        def title, do: %{name: "My Game", tagline: "a thing with paddles"}
        def atlas, do: :my_game
        def actions, do: [:left, :right, :launch]
        def keymaps, do: [arrows: %{left: [:left], right: [:right], launch: [:" "]}, wasd: %{...}]
        def toggles, do: []
        def arenas(_props), do: Cauldron2D.Arenas.list()
        def scene(view), do: %{focus: view.me.pos, bounds: view.bounds, cell: &MyGame.cell/1, movers: view.movers, labels: []}
        def hud(view), do: [["Balls ", {Integer.to_string(view.me.balls), {255, 220, 0}}], [{:score, ["Score \#{view.me.score}"]}]]
        def listener(view), do: view.me.pos
        def sounds, do: &MyGame.Sound.voice/1
        def music, do: [{"meadow", %{bpm: 112, beats_per_bar: 4, layers: [...], sections: %{...}}}]
        def cue(view, :arena), do: %{piece: "meadow", section: view.tension, layers: %{}}
        def cue(_view, _screen), do: nil
      end

  A view is whatever the game's `c:Cauldron2D.Game.view/2` returned for this player;
  `scene/1`, `hud/1`, `listener/1`, `outcome/1` and `cue/2` read it; none of them is
  asked before an arena's first frame has arrived. The hud is data in
  the shapes `Cauldron2D.Client.Hud` describes. `scene/1`'s `:labels` are text drawn over
  the world as `Cauldron2D.Surface.compose/4` takes them, in tiles; default none. Its
  `:subject` names what the focus follows — the player's own ship, the ship they watch,
  a free camera — as a string, atom or number; a client that has panned the view drops
  the pan when the subject changes, so a new ship comes up centred.

  `arenas/1` is given the client's props and read whenever a lobby draws, so it may
  answer differently each time. An arena is `%{id, name, world, players, humans, map,
  note, kind, teams}` as `Cauldron2D.Arenas.list/0` gives it: `world` is the name a
  player joins, `{module, opts}` for a world the client starts itself for this player
  alone (as `Cauldron2D.World.start_link/1` takes them, the client adding `:name`),
  `players` how many humans are in it and `humans` their ids where the lister knows
  them, `kind` `{text, rgb}`, `teams` the choices a player may join as (prop `:team`).
  A lobby reads an arena's players from the listing alone; it never speaks to the
  world, whose name may start it.

  The lobby is the screen that lists the arenas — the worlds — and lets a player pick
  one, a team in it, or watching; it has nothing to do with how the world steps, and a
  turn-based game whose players share a world keeps it. Who a player is once in the
  world — a character, a party, a side — is the game's: chosen through `join_props/1`,
  on a page of its own from `pages/1`, or in the world itself. A game with `lobby?/0`
  false has no arena to choose; its client goes from the title straight into its first
  arena, and back to the title from it.

  `cue/2`'s second argument is the screen — `:title`, `:lobby`, `:settings`, `:arena`,
  `:summary` or `:guide` — and `nil` means no music. On `:summary` the view is the last
  one the arena showed. A client whose music is static (`Cauldron2D.Audio` with
  `static_music: true`, as a server's `Cauldron2D.Net.Audio` policy `:static` sets) asks
  `cue(view, {:static, screen})` first — the one section it will loop for the whole
  stay, so a game can answer with a piece written as a loop rather than the layered
  one that follows the play — and falls back to `cue(view, screen)` when that is `nil`.

  ## Optional callbacks

    * `holds/0` — actions a terminal without key releases keeps held through its key-repeat
      delay on a press, with the milliseconds each is held, as `Cauldron2D.Input`'s
      `:holds`
    * `steering/0` — the actions the pointer also drives
    * `outcome/1` — `nil` while play goes on, or `%{title, lines, next}` when it is over
      for this player; `next` is `:next_arena`, `:same_arena` or `:lobby` (the default)
    * `join_props/1` — extra props for the world's join, from `%{username, settings,
      params}` (`params` a browser's join params, absent elsewhere)
    * `map/1` — the static layer a browser or window draws once, `%{width, height, cell,
      wrap?}` with `cell` a tile to an art or `nil`; without it, the layer is read from
      `scene/1`'s bounds and cell, the topmost art of each tile
    * `guide/0` — sections of entries, each `%{art, name, text}`
    * `sink/1` — the `TuningFork.Sink` this player's audio plays through, from the props
    * `pages/1` — extra pages reachable from the title, from the props: `[%{key, hint,
      title, render}]`, `render` a function returning rows of runs
    * `refusal_text/1` — the words a refused join is reported with
    * `player_label/1` — how a player id is written in a lobby and signed in chat; the
      lobby header shows the player their own id and, when this differs, this after it
    * `client_keys/0` — the client's own keys, as the terminal client documents them
    * `chat?/0` — whether the lobby and arena carry a chat; `true` without it
    * `frame_rates/0` — the frame rates a settings screen offers
    * `lobby?/0` — whether a screen of arenas stands between the title and play; `true`
      without it
    * `home/0` — the name the game keeps its files under, as `Cauldron2D.Paths` takes it:
      rendered music goes to `Cauldron2D.Paths.cache(home, "music")`. Without it, the
      game's module name underscored, up to its first dot: `MyGame.Client` is `:my_game`
  """

  alias Cauldron2D.Client.Hud

  @type action :: atom()
  @type screen :: :title | :lobby | :settings | :arena | :summary | :guide | {:static, atom()}
  @type rgb :: {byte(), byte(), byte()}
  @type arena :: %{
          required(:id) => term(),
          required(:name) => String.t(),
          required(:world) => GenServer.server() | {module(), keyword()},
          optional(:players) => non_neg_integer(),
          optional(:humans) => [term()],
          optional(:map) => String.t(),
          optional(:note) => String.t(),
          optional(:kind) => {String.t(), rgb()},
          optional(:teams) => [term()]
        }
  @type scene :: %{
          required(:focus) => {number(), number()},
          required(:bounds) => {pos_integer(), pos_integer()} | :unbounded,
          required(:cell) => ({integer(), integer()} -> term()),
          required(:movers) => [{term(), {number(), number()}}],
          optional(:labels) => list(),
          optional(:subject) => String.t() | atom() | number()
        }
  @type page :: %{key: atom(), hint: String.t(), title: String.t(), render: (-> [Hud.row()])}

  @callback title() :: %{required(:name) => String.t(), optional(:tagline) => String.t()}
  @callback atlas() :: Cauldron2D.Atlas.name()
  @callback actions() :: [action()]
  @callback keymaps() ::
              %{atom() => Cauldron2D.Input.keymap()} | [{atom(), Cauldron2D.Input.keymap()}]
  @callback toggles() :: [action()]
  @callback arenas(map()) :: [arena()]
  @callback scene(term()) :: scene()
  @callback hud(term()) :: Hud.t()
  @callback listener(term()) :: {number(), number()} | nil
  @callback sounds() :: (atom() -> Cauldron2D.Audio.sound())
  @callback music() :: [{String.t(), Cauldron2D.Audio.Music.spec()}]
  @callback cue(term(), screen()) :: Cauldron2D.Audio.Music.cue() | nil

  @callback holds() :: [{action(), pos_integer()}]
  @callback steering() :: [action()]
  @callback outcome(term()) ::
              nil
              | %{
                  required(:title) => String.t(),
                  required(:lines) => [String.t()],
                  optional(:next) => :next_arena | :same_arena | :lobby
                }
  @callback join_props(map()) :: map()
  @callback map(term()) :: %{
              required(:width) => pos_integer(),
              required(:height) => pos_integer(),
              required(:cell) => ({integer(), integer()} -> term() | nil),
              optional(:wrap?) => boolean()
            }
  @callback guide() :: [{String.t(), [%{art: term(), name: String.t(), text: String.t()}]}]
  @callback sink(map()) :: module() | {module(), keyword()}
  @callback pages(map()) :: [page()]
  @callback refusal_text(term()) :: String.t()
  @callback player_label(term()) :: String.t()
  @callback client_keys() :: %{atom() => atom() | nil}
  @callback chat?() :: boolean()
  @callback frame_rates() :: [:auto | pos_integer()]
  @callback lobby?() :: boolean()
  @callback home() :: atom()

  @optional_callbacks holds: 0,
                      steering: 0,
                      outcome: 1,
                      join_props: 1,
                      map: 1,
                      guide: 0,
                      sink: 1,
                      pages: 1,
                      refusal_text: 1,
                      player_label: 1,
                      client_keys: 0,
                      chat?: 0,
                      frame_rates: 0,
                      lobby?: 0,
                      home: 0

  @doc "Call an optional callback of `game` with `args`, or `default` when it has none."
  @spec optional(module(), atom(), [term()], term()) :: term()
  def optional(game, callback, args \\ [], default) do
    if Code.ensure_loaded?(game) and function_exported?(game, callback, length(args)),
      do: apply(game, callback, args),
      else: default
  end

  @doc "The static layer for `view`: the game's `map/1`, else read from its scene's bounds and cell."
  @spec static_map(module(), term()) :: %{
          width: pos_integer(),
          height: pos_integer(),
          cell: ({integer(), integer()} -> term() | nil),
          wrap?: boolean()
        }
  def static_map(game, view) do
    case optional(game, :map, [view], nil) do
      nil -> from_scene(game.scene(view))
      map -> Map.put_new(map, :wrap?, false)
    end
  end

  defp from_scene(%{bounds: {width, height}, cell: cell}) do
    %{width: width, height: height, wrap?: false, cell: fn point -> topmost(cell.(point)) end}
  end

  defp topmost(:void), do: nil
  defp topmost({base, [], _tint}), do: base
  defp topmost({_base, overlays, _tint}), do: List.last(overlays)

  @doc "The arena whose id writes as `id`, from `game`'s arenas for `props`."
  @spec arena(module(), map(), String.t()) :: arena() | nil
  def arena(game, props, id), do: Enum.find(game.arenas(props), &(to_string(&1.id) == id))

  @doc "The player's outcome for `view`, `nil` while play goes on."
  @spec outcome(module(), term()) :: map() | nil
  def outcome(game, view), do: optional(game, :outcome, [view], nil)

  @doc "The words `game` gives for a refused join."
  @spec refusal_text(module(), term()) :: String.t()
  def refusal_text(game, reason), do: optional(game, :refusal_text, [reason], inspect(reason))

  @doc "The name the game keeps its files under: its `home/0`, else its module name's first part underscored."
  @spec home(module()) :: atom()
  def home(game) do
    optional(
      game,
      :home,
      [],
      game |> Module.split() |> hd() |> Macro.underscore() |> String.to_atom()
    )
  end

  @doc "Where the game's rendered music is kept: `Cauldron2D.Paths.cache(home, \"music\")`."
  @spec music_dir(module()) :: Path.t()
  def music_dir(game), do: Cauldron2D.Paths.cache(home(game), "music")
end
