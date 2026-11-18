defmodule Cauldron.Client.Game do
  @moduledoc """
  What a game gives a client — the terminal's, the browser's or the desktop's — to put
  its worlds in front of a player. One contract; every front end draws from it.

  How the game is drawn is its view's (`c:view/0`, a `Cauldron.Client.View`): the keys a
  scene has, the keys of the look, the zoom steps. A kind of game's package gives a
  `use` that names its view and adds the callbacks that kind needs: `cauldron_2d`'s
  client game for tile worlds and 2D projections adds `atlas/0`.

      defmodule MyGame.Client do
        @behaviour Cauldron.Client.Game

        def title, do: %{name: "My Game", tagline: "a thing with paddles"}
        def view, do: MyGame.View
        def actions, do: [:left, :right, :launch]
        def keymaps, do: [arrows: %{left: [:left], right: [:right], launch: [:" "]}, wasd: %{...}]
        def toggles, do: []
        def worlds(_props), do: Cauldron.Worlds.list()
        def scene(view), do: %{focus: view.me.pos, bounds: view.bounds, cell: &MyGame.cell/1, movers: view.movers, labels: []}
        def hud(view), do: [["Balls ", {Integer.to_string(view.me.balls), {255, 220, 0}}], [{:score, ["Score \#{view.me.score}"]}]]
        def listener(view), do: view.me.pos
        def sounds, do: &MyGame.Sound.voice/1
        def music, do: [{"meadow", %{bpm: 112, beats_per_bar: 4, layers: [...], sections: %{...}}}]
        def cue(view, :play), do: %{piece: "meadow", section: view.tension, layers: %{}}
        def cue(_view, _screen), do: nil
      end

  `use Cauldron.Client.Game` declares the behaviour and gives the callbacks most games
  write the same way, each of which a game may define for itself instead:

    * `toggles/0` — `[]`
    * `hud/1` — `[]`, nothing drawn in rows (a hud on the scene's `:screen` needs none)
    * `listener/1` — `nil`, sounds heard as they are, without place
    * `sounds/0` — no sound for any event
    * `music/0` — `[]`
    * `cue/2` — `nil`, no music on any screen
    * `scene/1` — the game's `scene/2` given its `look/0` (an empty map without one), for a
      game that writes only `scene/2`

      defmodule MyGame.Client do
        use Cauldron.Client.Game

        def title, do: %{name: "My Game"}
        def view, do: MyGame.View
        def actions, do: [:left, :right, :launch]
        def keymaps, do: [arrows: %{left: [:left], right: [:right], launch: [:" "]}]
        def worlds(_props), do: Cauldron.Worlds.list()
        def scene(view, _look), do: %{focus: view.me.pos, bounds: view.bounds, cell: &MyGame.cell/1, movers: view.movers}
      end

  A view is whatever the game's `c:Cauldron.Game.view/2` returned for this player;
  `scene/1`, `hud/1`, `listener/1`, `outcome/1` and `cue/2` read it; none of them is
  asked before a world's first frame has arrived. The hud is data in
  the shapes `Cauldron.Client.Hud` describes.

  A scene is a map the game's view draws; which keys it has is the view's. One key every
  client reads: `:subject` names what the scene follows — the player's own ship, the ship
  they watch, a free camera — as a string, atom or number; a client that has panned the
  view drops the pan when the subject changes, so a new ship comes up centred.

  `worlds/1` is given the client's props and read whenever a lobby draws, so it may
  answer differently each time. A world is `%{id, name, world, players, humans, map,
  note, kind, teams}` as `Cauldron.Worlds.list/0` gives it: `world` is the name a
  player joins, `{module, opts}` for a world the client starts itself for this player
  alone (as `Cauldron.World.start_link/1` takes them, the client adding `:name`),
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
  one the world showed. A client whose music is static (`Cauldron.Audio` with
  `static_music: true`, as the static audio policy of a `cauldron_2d_net` server sets) asks
  `cue(view, {:static, screen})` first — the one section it will loop for the whole
  stay, so a game can answer with a piece written as a loop rather than the layered
  one that follows the play — and falls back to `cue(view, screen)` when that is `nil`.

  ## Optional callbacks

    * `holds/0` — actions a terminal without key releases keeps held through its key-repeat
      delay on a press, with the milliseconds each is held, as `Cauldron.Input`'s
      `:holds`
    * `steering/0` — the actions the pointer also drives
    * `padmap/1` — a `Cauldron.Input.Pad` padmap for game controllers, given the
      client's props like `worlds/1` (so a game may keep a player's own bindings in
      their account). Default `Cauldron.Input.Pad.default_map/3` of `actions()` and the
      first keymap: the d-pad and left stick steer `:left`, `:right`, `:up` and `:down`,
      an action on an arrow key is also on that arrow of the d-pad, and the other
      actions take `A`, `X`, `B`, `Y` and the bumpers in the order `actions()` lists
      them, passing over the buttons the client keeps (`padmap/3`)
    * `local_seats/1` — further players on the same machine, given the client's props with
      `:settings`, the player's settings (its `:options` the game's own, as saved): a
      `Cauldron.Input` keymap for each, the keys that play that seat. Each joins the
      world as `"<username> 2"`, `"<username> 3"`, … with `frames: false`; every key
      reaches every seat and counts where it is mapped; controllers go to the seats, the
      player's own first, in the order they first report. Default `[]`, one player
    * `outcome/1` — `nil` while play goes on, or `%{title, lines, next}` when it is over
      for this player; `next` is `:next_world`, `:same_world` or `:lobby` (the default)
    * `join_props/1` — extra props for the world's join, from `%{username, settings,
      params}` (`params` a browser's join params, absent elsewhere)
    * `guide/0` — sections of entries, each `%{art, name, text}`
    * `sink/1` — the `Cauldron.Audio.Sink` this player's audio plays through, from the props
    * `audio/0` — sound settings, any of `:voices` (most sounds at once, default 12),
      `:earshot` (tiles at which a placed sound falls silent, default 30.0), `:master`
      (`:sfx` for the effects level to scale the music too, `Cauldron.Audio`'s) and
      `:rate` (the stage's sample rate, default 44 100; a game whose music is recorded at
      another rate sets it to that rate so the recordings play as they are)
    * `recordings/0` — the function `Cauldron.Audio`'s `:recordings` takes: an event
      name to its recording in its own channels, for music the world sends as keyed
      sounds with `music: true`
    * `pages/1` — extra pages reachable from the title, from the props: `[%{key, hint,
      title, render}]`, `render` a function returning rows of runs
    * `fronts/1` — the screens outside the world the game draws and runs itself, from
      the props: `%{title: module, summary: module}`, each a `Cauldron.Front`. A
      screen left out is the client's own. Default `%{}`
    * `opening/1` — rows of runs a client shows, centred, from the moment it asks to
      join a world until that world's first frame arrives, given the world as `worlds/1`
      listed it. Default `[]`: nothing is drawn until the first frame
    * `refusal_text/1` — the words a refused join is reported with
    * `player_label/1` — how a player id is written in a lobby and signed in chat; the
      lobby header shows the player their own id and, when this differs, this after it
    * `client_keys/0` — the client's own keys over `Cauldron.Client.Keys.defaults/0`;
      an entry `{:look, key} => keys` adds a key of the game's own that flips the
      boolean `key` of the look, shown among the key hints by its name
    * `client_pad/0` — the client's own actions on controller buttons, over
      `Cauldron.Client.Keys.pad/2`'s
    * `look/0` — the look a client starts in, over the view's defaults
      (`c:Cauldron.Client.View.look/1`): any of the keys the view knows, `:mouse_look?`
      (a boolean) and `:fps?` (a boolean: the frames a second shown from the start). Any
      other key is the game's own, kept on the look and given to `scene/2`
    * `scene/2` — as `scene/1`, given the client's look as well, for a scene that
      changes with the view or with a key of the game's own on it; when defined it is
      called in place of `scene/1`
    * `start/0` — where the client starts: `:lobby` (the title, then the lobby), `{:lobby,
      title: false}`, `{:play, id}` (straight into that world of `worlds/1`, `:first` for the
      first), `{:play, id, title: true}`, as `Cauldron.Client.Start` reads them, or a
      function of the terminal client's state for a flow of the game's own, which the
      desktop and the browser open on the title. Default `:lobby`
    * `chat?/0` — whether the lobby and world carry a chat; `true` without it
    * `frame_rates/0` — the frame rates a settings screen offers (`frame_rates/1`); the
      world sends a player frames at the rate they chose
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
      `:enter`, and `B` and `Start` as `:escape`, each as `{:key, key, [:pad]}` so a game
      can tell a controller's press from the keyboard's (a yes/no prompt takes `A` as
      yes, as console ports of the games do)
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
      `:quit` (end the client), `{:options, changes}` (merge the map `changes` into the
      player's game options and save them, as the menu saves its own changes),
      `{:clipboard, text}` (put `text` on the player's clipboard),
      `{:enter, props}` (leave this world, merge `props` into
      the client's mount props and join the first world `worlds/1` then gives; should
      that join fail, the client joins the first world of its earlier props again with
      `refused: true` among that join's props, and should that world go down, the client
      takes its earlier props back and joins the first of their worlds again, adding the
      props of the last `{:on_return, props}` to that join's),
      `{:return, props}` (in a world entered that way, leave it
      at once for the first world of the earlier props, joining it with `props` added to
      that join's props only), or `{:on_return, props}` (keep `props` for the join that
      follows should the world entered go down). The client acts on each number once, so the game keeps an ask
      in its views only for the few steps the client needs to see it
    * `input_options/1` — extra `Cauldron.Input.new/2` options for the player's
      `:options`, such as `:gesture_ms`
    * `home/0` — the name the game keeps its files under, as `Cauldron.Paths` takes it:
      rendered music goes to `Cauldron.Paths.cache(home, "music")`. Without it, the
      game's module name underscored, up to its first dot: `MyGame.Client` is `:my_game`

  ## Which front ends read which callbacks

  Every front end reads every callback alike, through the same modules: the scene
  through the game's view (`Cauldron.Client.View`), the game's fronts
  (`Cauldron.Client.Fronts`), its menu (`Cauldron.Client.Menus`), the look and the
  client's keys (`Cauldron.Client.Keys`, `Cauldron.Client.Stage`), what the player holds
  (`Cauldron.Client.Controls`, `Cauldron.Client.Party`), where the client starts
  (`Cauldron.Client.Start`) and the chat (`Cauldron.Chat`). Each front end keeps its
  own lobby, settings and guide screens. Two callbacks have no part in some front ends:

    * `holds/0` is for a terminal that reports no key releases; the desktop and the
      browser report them, and a key is held from its press to its release
    * `sink/1` is where a player's sound plays on the machine that runs the client — the
      terminal's, the desktop's playing a world in its own node; a browser, or a desktop
      joined over the socket, plays the sound the server sends
  """

  alias Cauldron.Client.Hud
  alias Cauldron.Input.Pad

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
          optional(:subject) => String.t() | atom() | number(),
          optional(atom()) => term()
        }
  @type page :: %{key: atom(), hint: String.t(), title: String.t(), render: (-> [Hud.row()])}

  @callback title() :: %{required(:name) => String.t(), optional(:tagline) => String.t()}
  @callback view() :: module()
  @callback actions() :: [action()]
  @callback keymaps() ::
              %{atom() => Cauldron.Input.keymap()} | [{atom(), Cauldron.Input.keymap()}]
  @callback toggles() :: [action()]
  @callback worlds(map()) :: [world()]
  @callback scene(term()) :: scene()
  @callback scene(term(), map()) :: scene()
  @callback hud(term()) :: Hud.t()
  @callback listener(term()) :: {number(), number()} | nil
  @callback sounds() :: (atom() -> Cauldron.Audio.sound())
  @callback music() :: [{String.t(), Cauldron.Audio.Music.spec()}]
  @callback cue(term(), screen()) :: Cauldron.Audio.Music.cue() | nil

  @callback holds() :: [{action(), pos_integer()}]
  @callback steering() :: [action()]
  @callback padmap(map()) :: Pad.padmap()
  @callback local_seats(map()) :: [Cauldron.Input.keymap()]
  @callback outcome(term()) ::
              nil
              | %{
                  required(:title) => String.t(),
                  required(:lines) => [String.t()],
                  optional(:next) => :next_world | :same_world | :lobby
                }
  @callback join_props(map()) :: map()
  @callback guide() :: [{String.t(), [%{art: term(), name: String.t(), text: String.t()}]}]
  @callback sink(map()) :: module() | {module(), keyword()}
  @callback audio() :: keyword()
  @callback recordings() :: (term() -> map() | nil)
  @callback pages(map()) :: [page()]
  @callback fronts(map()) :: %{optional(Cauldron.Front.screen()) => module()}
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
  @callback ask(term()) ::
              {term(),
               :menu
               | {:menu, term()}
               | :quit
               | {:options, map()}
               | {:clipboard, String.t()}
               | {:enter, map()}
               | {:return, map()}
               | {:on_return, map()}}
              | nil

  @optional_callbacks scene: 2,
                      fronts: 1,
                      holds: 0,
                      steering: 0,
                      padmap: 1,
                      local_seats: 1,
                      outcome: 1,
                      join_props: 1,
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

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Cauldron.Client.Game

      def toggles, do: []
      def hud(_view), do: []
      def listener(_view), do: nil
      def sounds, do: fn _event -> nil end
      def music, do: []
      def cue(_view, _screen), do: nil

      def scene(view) do
        look =
          if function_exported?(__MODULE__, :look, 0), do: apply(__MODULE__, :look, []), else: %{}

        apply(__MODULE__, :scene, [view, look])
      end

      defoverridable toggles: 0, hud: 1, listener: 1, sounds: 0, music: 0, cue: 2, scene: 1
    end
  end

  @doc "Call an optional callback of `game` with `args`, or `default` when it has none."
  @spec optional(module(), atom(), [term()], term()) :: term()
  def optional(game, callback, args \\ [], default) do
    if Code.ensure_loaded?(game) and function_exported?(game, callback, length(args)),
      do: apply(game, callback, args),
      else: default
  end

  @doc """
  The padmap `game` is played with by controller: its `padmap/1` given `props`, or
  without one `Cauldron.Input.Pad.default_map/3` of its actions and its first keymap,
  passing over the buttons in `taken`, the ones the client keeps for itself.
  """
  @spec padmap(module(), map(), [atom()]) :: Pad.padmap()
  def padmap(game, props, taken \\ []) do
    optional(game, :padmap, [props], nil) ||
      Pad.default_map(game.actions(), first_keymap(game), taken)
  end

  @doc "The `Cauldron.Audio.start_link/1` options the game sets through `audio/0` — `:voices`, `:earshot`, `:master` and `:rate` — and `recordings/0`."
  @spec audio_options(module()) :: keyword()
  def audio_options(game) do
    settings =
      game |> optional(:audio, [], []) |> Keyword.take([:voices, :earshot, :master, :rate])

    case optional(game, :recordings, [], nil) do
      nil -> settings
      recordings -> [{:recordings, recordings} | settings]
    end
  end

  @doc "The world whose id writes as `id`, from `game`'s worlds for `props`."
  @spec world(module(), map(), String.t()) :: world() | nil
  def world(game, props, id), do: Enum.find(game.worlds(props), &(to_string(&1.id) == id))

  @doc "How `game` writes the player `id`, in a lobby and signing a chat message: its `player_label/1`, else the id as text."
  @spec player_label(module(), term()) :: String.t()
  def player_label(game, id) do
    case optional(game, :player_label, [id], nil) do
      nil -> plain_label(id)
      label -> label
    end
  end

  defp plain_label(id) when is_binary(id), do: id
  defp plain_label(id) when is_atom(id), do: Atom.to_string(id)
  defp plain_label(id), do: inspect(id)

  @doc "The frame rates `game` offers a player: its `frame_rates/0`, else `:auto`, 15, 30, 50 and 60."
  @spec frame_rates(module()) :: [:auto | pos_integer()]
  def frame_rates(game), do: optional(game, :frame_rates, [], [:auto, 15, 30, 50, 60])

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

  @doc "Where the game's rendered music is kept: `Cauldron.Paths.cache(home, \"music\")`."
  @spec music_dir(module()) :: Path.t()
  def music_dir(game), do: Cauldron.Paths.cache(home(game), "music")

  defp first_keymap(game) do
    case Enum.at(game.keymaps(), 0) do
      {_name, keymap} -> keymap
      nil -> %{}
    end
  end
end
