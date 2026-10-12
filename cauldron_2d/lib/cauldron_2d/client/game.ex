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
        def worlds(_props), do: Cauldron2D.Worlds.list()
        def scene(view), do: %{focus: view.me.pos, bounds: view.bounds, cell: &MyGame.cell/1, movers: view.movers, labels: []}
        def hud(view), do: [["Balls ", {Integer.to_string(view.me.balls), {255, 220, 0}}], [{:score, ["Score \#{view.me.score}"]}]]
        def listener(view), do: view.me.pos
        def sounds, do: &MyGame.Sound.voice/1
        def music, do: [{"meadow", %{bpm: 112, beats_per_bar: 4, layers: [...], sections: %{...}}}]
        def cue(view, :play), do: %{piece: "meadow", section: view.tension, layers: %{}}
        def cue(_view, _screen), do: nil
      end

  A view is whatever the game's `c:Cauldron2D.Game.view/2` returned for this player;
  `scene/1`, `hud/1`, `listener/1`, `outcome/1` and `cue/2` read it; none of them is
  asked before a world's first frame has arrived. The hud is data in
  the shapes `Cauldron2D.Client.Hud` describes. `scene/1`'s `:volumes` are coloured
  regions of space, as `Cauldron2D.Projection.Volume` describes them, that tint what is
  seen through them in every projection. `scene/1`'s `:layers` are
  `Cauldron2D.Parallax` layers drawn behind the world, and in front of it where a layer
  has `front: true`, in the top-down view. `scene/1`'s `:labels` are text drawn over
  the world as `Cauldron2D.Surface.compose/4` takes them, in tiles; default none. Its
  `:subject` names what the focus follows — the player's own ship, the ship they watch,
  a free camera — as a string, atom or number; a client that has panned the view drops
  the pan when the subject changes, so a new ship comes up centred. Its `:heading`, in
  radians with `0` along `+x`, is where the subject looks: a first-person view is drawn
  along it, and a client whose scene gives none turns the eye itself. `:movers` may
  carry a heading as a third element, `{art, {x, y}, heading}`, for the projections
  that pose them.
  A scene with a `:picture` — `fn {width, height}, aspect -> raster end` — is drawn by
  the game itself rather than from the atlas: the client hands it to
  `Cauldron2D.Drafter.Surface` as the `:picture` projection, at the pane's size in pixels,
  and the focus, cell and movers then serve only the listener and the pointer. A scene's
  `:native` (`{width, height}`), over the look's, is the picture's own size in pixels:
  the size the client's picture options (`Cauldron2D.Drafter.Client.Picture`) draw it at
  times a whole number, for a terminal that keeps images to scale.

  `worlds/1` is given the client's props and read whenever a lobby draws, so it may
  answer differently each time. A world is `%{id, name, world, players, humans, map,
  note, kind, teams}` as `Cauldron2D.Worlds.list/0` gives it: `world` is the name a
  player joins, `{module, opts}` for a world the client starts itself for this player
  alone (as `Cauldron2D.World.start_link/1` takes them, the client adding `:name`),
  `players` how many humans are in it and `humans` their ids where the lister knows
  them, `kind` `{text, rgb}`, `teams` the choices a player may join as (prop `:team`).
  A lobby reads a world's players from the listing alone; it never speaks to the
  world, whose name may start it.

  The lobby is the screen that lists the worlds and lets a player pick
  one, a team in it, or watching; it has nothing to do with how the world steps, and a
  turn-based game whose players share a world keeps it. Who a player is once in the
  world — a character, a party, a side — is the game's: chosen through `join_props/1`,
  on a page of its own from `pages/1`, or in the world itself. Whether a client shows
  a lobby at all, a title, or opens straight in a world, is the game's `start/0`.

  `cue/2`'s second argument is the screen — `:title`, `:lobby`, `:settings`, `:play`,
  `:summary` or `:guide` — and `nil` means no music. On `:summary` the view is the last
  one the world showed. A client whose music is static (`Cauldron2D.Audio` with
  `static_music: true`, as a server's `Cauldron2D.Net.Audio` policy `:static` sets) asks
  `cue(view, {:static, screen})` first — the one section it will loop for the whole
  stay, so a game can answer with a piece written as a loop rather than the layered
  one that follows the play — and falls back to `cue(view, screen)` when that is `nil`.

  ## Optional callbacks

    * `holds/0` — actions a terminal without key releases keeps held through its key-repeat
      delay on a press, with the milliseconds each is held, as `Cauldron2D.Input`'s
      `:holds`
    * `steering/0` — the actions the pointer also drives
    * `padmap/1` — a `Cauldron2D.Input.Pad` padmap for game controllers, given the
      client's props like `worlds/1` (so a game may keep a player's own bindings in
      their account). Default `Cauldron2D.Input.Pad.default_map(actions())`: the d-pad
      and left stick steer `:left`, `:right`, `:up` and `:down`, nothing else is bound
    * `local_seats/1` — further players on the same machine, given the client's props with
      `:settings`, the player's settings (its `:options` the game's own, as saved): a
      `Cauldron2D.Input` keymap for each, the keys that play that seat. Each joins the
      world as `"<username> 2"`, `"<username> 3"`, … with `frames: false`; every key
      reaches every seat and counts where it is mapped; controllers go to the seats, the
      player's own first, in the order they first report. Default `[]`, one player
    * `outcome/1` — `nil` while play goes on, or `%{title, lines, next}` when it is over
      for this player; `next` is `:next_world`, `:same_world` or `:lobby` (the default)
    * `join_props/1` — extra props for the world's join, from `%{username, settings,
      params}` (`params` a browser's join params, absent elsewhere)
    * `received/3` — called with each frame's view and events and what it returned for
      the frame before (`nil` for a world's first frame), before anything else reads
      them; returns `{view, events, kept}`, the view and events the client goes on with
      and what to give it with the next frame. A game whose world sends a client part of
      what it shows as operations keeps their result here and puts it in the view.
      Default: both as they came, nothing kept
    * `map/1` — the static layer a browser or window draws once, `%{width, height, cell,
      wrap?}` with `cell` a tile to an art or `nil`; without it, the layer is read from
      `scene/1`'s bounds and cell, the topmost art of each tile
    * `guide/0` — sections of entries, each `%{art, name, text}`
    * `sink/1` — the `TuningFork.Sink` this player's audio plays through, from the props
    * `audio/0` — sound settings, any of `:voices` (most sounds at once, default 12),
      `:earshot` (tiles at which a placed sound falls silent, default 30.0) and `:master`
      (`:sfx` for the effects level to scale the music too, `Cauldron2D.Audio`'s)
    * `recordings/0` — the function `Cauldron2D.Audio`'s `:recordings` takes: an event
      name to its recording in its own channels, for music the world sends as keyed
      sounds with `music: true`
    * `pages/1` — extra pages reachable from the title, from the props: `[%{key, hint,
      title, render}]`, `render` a function returning rows of runs
    * `opening/1` — rows of runs a client shows, centred, from the moment it asks to
      join a world until that world's first frame arrives, given the world as `worlds/1`
      listed it. Default `[]`: nothing is drawn until the first frame
    * `refusal_text/1` — the words a refused join is reported with
    * `player_label/1` — how a player id is written in a lobby and signed in chat; the
      lobby header shows the player their own id and, when this differs, this after it
    * `client_keys/0` — the client's own keys, as the terminal client documents them;
      an entry `{:look, key} => keys` adds a key of the game's own that flips the
      boolean `key` of the look, shown among the key hints by its name
    * `client_pad/0` — the client's own actions on controller buttons, as the terminal
      client documents them
    * `look/0` — the view a client starts in: a map with any of `:projection` (`:top`,
      `:oblique`, `:iso`, `:mode7` or `:first_person`), `:projections` (a list of
      those), `:facing` (a step), `:facings` (steps in a turn), `:tilt` (`0.5..1.5`),
      `:heading` (radians), `:pitch` (`-1.0..1.0`), `:zoom` (how many times native a
      tile is drawn when a world opens), `:mouse_look?` (a boolean), `:native`
      (`{width, height}`, a picture's own size in pixels) and `:picture` (the picture
      options `Cauldron2D.Drafter.Client.Picture` uses when the player gives none).
      `projections` lists the views the projection key cycles through, in order;
      `density` is `Cauldron2D.Drafter.Surface`'s, the pixels a cell is drawn with.
      Default top-down, cycling all three. Any other key is the game's own, kept on
      the look and given to `scene/2`
    * `scene/2` — as `scene/1`, given the client's look as well, for a scene that
      changes with the view or with a key of the game's own on it; when defined it is
      called in place of `scene/1`
    * `start/0` — where the client starts: `:lobby` (the title, then the lobby), `{:lobby,
      title: false}`, `{:play, id}` (straight into that world of `worlds/1`, `:first` for the
      first), `{:play, id, title: true}`, or a function of the client's state for a flow of
      the game's own; the terminal client documents each. Default `:lobby`
    * `chat?/0` — whether the lobby and world carry a chat; `true` without it
    * `frame_rates/0` — the frame rates a settings screen offers
    * `lobby?/0` — the older way of saying `start/0`: `false` is `{:play, :first, title: true}`
    * `options/0` — the game's own player options and their defaults, as a map. A client
      keeps them in the player's settings under `:options`, saves them with the rest,
      puts them on the look given to `scene/2` as `:options` and sends them with every
      input as `:options`
    * `open_menu/1` — the game's own menu, opened by the client's `menu` key during play:
      given the player's settings, the menu's state. While it is open the look carries
      it as `:menu`, the player's held actions are let go, a world of the player's own
      is paused, and every key press, mouse
      button press and wheel notch goes to `menu_event/3` instead of the world; the
      look's `:menu_frame` counts up ten times a second, so the scene is drawn again
      for a menu's animations while the world stands still; a
      controller's d-pad arrives as the keys `:up`, `:down`, `:left` and `:right`, `A` as
      `:enter`, and `B` and `Start` as `:escape`
    * `open_menu/2` — `(settings, arg)`, the game's menu opened because the world asked
      for it with `{:menu, arg}` (see `ask/1`); a game without it gets `open_menu/1`
    * `menu_event/3` — `(menu, event, settings)`, one event while the menu is open. Returns
      `%{menu: menu_or_nil, settings: settings}`, with any of `:sounds` (sound events to
      play, as `sounds/0`'s table knows them), `:request` (a term for the world, sent once
      with the next input as `:request`, as `{number, term}` numbered from 1 so the world
      can act on each once) and `:leave` (`true` to leave the world). A `nil` menu closes
      it; settings that changed are saved and take effect at once. The settings are a
      map with at least `:bindings` (the keymap in force), `:preset`, `:sfx` and `:music`
      (`0.0..1.0`) and `:options`
    * `ask/1` — what the world asks of this player's client, read from each view: `nil`,
      or `{number, ask}` with `ask` `:menu` (open the game's menu, as the `menu` key does),
      `{:menu, arg}` (open the game's menu given `arg`, `open_menu/2`),
      `:quit` (end the client), or `{:enter, props}` (leave this world, merge `props` into
      the client's mount props and join the first world `worlds/1` then gives; should
      that world go down, the client takes its earlier props back and joins the first of
      their worlds again). The client acts on each number once, so the game keeps an ask
      in its views only for the few steps the client needs to see it
    * `input_options/1` — extra `Cauldron2D.Input.new/2` options for the player's
      `:options`, such as `:gesture_ms`
    * `home/0` — the name the game keeps its files under, as `Cauldron2D.Paths` takes it:
      rendered music goes to `Cauldron2D.Paths.cache(home, "music")`. Without it, the
      game's module name underscored, up to its first dot: `MyGame.Client` is `:my_game`
  """

  alias Cauldron2D.Client.Hud

  @type action :: atom()
  @type screen :: :title | :lobby | :settings | :play | :summary | :guide | {:static, atom()}
  @type rgb :: {byte(), byte(), byte()}
  @type world :: %{
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
          optional(:volumes) => list(),
          optional(:layers) => [Cauldron2D.Parallax.Layer.t()],
          optional(:subject) => String.t() | atom() | number(),
          optional(:heading) => number(),
          optional(:picture) => ({pos_integer(), pos_integer()}, number() ->
                                   FrenchCurve.Raster.t()),
          optional(:native) => {pos_integer(), pos_integer()}
        }
  @type page :: %{key: atom(), hint: String.t(), title: String.t(), render: (-> [Hud.row()])}

  @callback title() :: %{required(:name) => String.t(), optional(:tagline) => String.t()}
  @callback atlas() :: Cauldron2D.Atlas.name()
  @callback actions() :: [action()]
  @callback keymaps() ::
              %{atom() => Cauldron2D.Input.keymap()} | [{atom(), Cauldron2D.Input.keymap()}]
  @callback toggles() :: [action()]
  @callback worlds(map()) :: [world()]
  @callback scene(term()) :: scene()
  @callback scene(term(), map()) :: scene()
  @callback hud(term()) :: Hud.t()
  @callback listener(term()) :: {number(), number()} | nil
  @callback sounds() :: (atom() -> Cauldron2D.Audio.sound())
  @callback music() :: [{String.t(), Cauldron2D.Audio.Music.spec()}]
  @callback cue(term(), screen()) :: Cauldron2D.Audio.Music.cue() | nil

  @callback holds() :: [{action(), pos_integer()}]
  @callback steering() :: [action()]
  @callback padmap(map()) :: Cauldron2D.Input.Pad.padmap()
  @callback local_seats(map()) :: [Cauldron2D.Input.keymap()]
  @callback outcome(term()) ::
              nil
              | %{
                  required(:title) => String.t(),
                  required(:lines) => [String.t()],
                  optional(:next) => :next_world | :same_world | :lobby
                }
  @callback join_props(map()) :: map()
  @callback received(term(), [term()], term()) :: {term(), [term()], term()}
  @callback map(term()) :: %{
              required(:width) => pos_integer(),
              required(:height) => pos_integer(),
              required(:cell) => ({integer(), integer()} -> term() | nil),
              optional(:wrap?) => boolean()
            }
  @callback guide() :: [{String.t(), [%{art: term(), name: String.t(), text: String.t()}]}]
  @callback sink(map()) :: module() | {module(), keyword()}
  @callback audio() :: keyword()
  @callback recordings() :: (term() -> map() | nil)
  @callback pages(map()) :: [page()]
  @callback opening(world()) :: [Hud.row()]
  @callback refusal_text(term()) :: String.t()
  @callback player_label(term()) :: String.t()
  @callback client_keys() :: %{(atom() | {:look, atom()}) => atom() | [atom()] | nil}
  @callback client_pad() :: %{(atom() | {:look, atom()}) => atom() | [atom()] | nil}
  @callback look() :: map()
  @callback start() ::
              :lobby
              | {:lobby, keyword()}
              | {:play, term()}
              | {:play, term(), keyword()}
              | (map() -> map())
  @callback chat?() :: boolean()
  @callback frame_rates() :: [:auto | pos_integer()]
  @callback lobby?() :: boolean()
  @callback home() :: atom()
  @callback options() :: map()
  @callback open_menu(map()) :: term()
  @callback menu_event(term(), term(), map()) :: %{
              required(:menu) => term(),
              required(:settings) => map(),
              optional(:sounds) => [term()],
              optional(:request) => term(),
              optional(:leave) => boolean()
            }
  @callback input_options(map()) :: keyword()
  @callback open_menu(map(), term()) :: term()
  @callback ask(term()) :: {term(), :menu | {:menu, term()} | :quit | {:enter, map()}} | nil

  @optional_callbacks scene: 2,
                      holds: 0,
                      steering: 0,
                      padmap: 1,
                      local_seats: 1,
                      outcome: 1,
                      join_props: 1,
                      received: 3,
                      map: 1,
                      guide: 0,
                      sink: 1,
                      audio: 0,
                      recordings: 0,
                      pages: 1,
                      opening: 1,
                      refusal_text: 1,
                      player_label: 1,
                      client_keys: 0,
                      chat?: 0,
                      frame_rates: 0,
                      lobby?: 0,
                      client_pad: 0,
                      look: 0,
                      start: 0,
                      home: 0,
                      options: 0,
                      open_menu: 1,
                      open_menu: 2,
                      menu_event: 3,
                      input_options: 1,
                      ask: 1

  @doc "Call an optional callback of `game` with `args`, or `default` when it has none."
  @spec optional(module(), atom(), [term()], term()) :: term()
  def optional(game, callback, args \\ [], default) do
    if Code.ensure_loaded?(game) and function_exported?(game, callback, length(args)),
      do: apply(game, callback, args),
      else: default
  end

  @doc "The `Cauldron2D.Audio.start_link/1` options the game sets through `audio/0` — `:voices`, `:earshot` and `:master` — and `recordings/0`."
  @spec audio_options(module()) :: keyword()
  def audio_options(game) do
    settings = game |> optional(:audio, [], []) |> Keyword.take([:voices, :earshot, :master])

    case optional(game, :recordings, [], nil) do
      nil -> settings
      recordings -> [{:recordings, recordings} | settings]
    end
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

  @doc "The world whose id writes as `id`, from `game`'s worlds for `props`."
  @spec world(module(), map(), String.t()) :: world() | nil
  def world(game, props, id), do: Enum.find(game.worlds(props), &(to_string(&1.id) == id))

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
