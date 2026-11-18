defmodule Cauldron.Net.Drawer do
  @moduledoc """
  How a kind of game's scenes go over the network: what a session sends a client to show
  each scene (`Cauldron.Net.Session`, `Cauldron.Net.FrontSession`), and what a client's
  link makes of it (`Cauldron.Net.Link.Socket`, `Cauldron.Net.Link.World`).

  A drawer is named with the `:drawer` option wherever a session or a link starts: a
  module, or `{module, opts}` with options of the drawer's own.
  `Cauldron2D.Net.Drawer` sends 2D scenes as pictures or as scene data drawn against the
  game's atlas.

      use Cauldron.Net.Channel, game: MyGame.Client, drawer: {Cauldron2D.Net.Drawer, drawing: :client}

  ## On the server

  A session opens its drawer with `c:open/2` and keeps the state it returns. The session
  passes on the client's pane (`c:pane/2`), asks for the pushes that show each scene
  (`c:draw/2`; the world sends a player its frames at the player's frame rate, every
  so many ticks, so every frame is drawn), the world point under the pointer (`c:world_at/3`) and the colour a hud names (`c:colour/1`).
  A message the session's process receives and does not know goes to `c:changed/3`.
  A push is `{event, payload}`, sent to the client as it is.

  A session's options reach `c:open/2` along with the drawer's own; the session adds
  `:local`, `true` when the client runs in this node and receives the payloads as
  terms, and a channel adds `:params`, the client's join params, so a client can say
  how it wants the scenes. `c:local/2` turns a push into the messages `Cauldron.Net.Link.Local` gives
  its owner, as `{:cauldron_link, ...}` with the tuple's elements after it.

  ## On the client

  ## In a browser

  A drawer whose browser client needs its own scripts names them with the optional
  `c:browser/0`: the scripts, as `{name, path}` of files the pages serve and load as
  modules, after which the page mounts; any HTML for the page's head, such as an import
  map; and the join params the browser client sends. A script sets
  `window.CauldronDrawer` to `{mount(canvas)}`, answering an object with `events` (the
  pushes it draws, by event name), `pane()` (the pane it reports, `[width, height]`) and
  `stop()`; the page's own drawing then stays out of the way.

  A socket link starts its reader with `c:reader/1`, given the link's options, and
  passes it every push it does not read itself (`c:read/4`). A link world
  (`Cauldron.Net.Link.World`) keeps the messages a reader sends in the view's `remote`
  map with `c:remote/2`.
  """

  @type state :: term()
  @type push :: {String.t(), term()}
  @type spec :: module() | {module(), keyword()}
  @type link :: %{owner: pid(), base: URI.t()}

  @doc "The drawer's state for `game` and the pushes a client gets first."
  @callback open(game :: module(), opts :: keyword()) :: {state(), [push()]}

  @doc "A message the session's process received: `{:ok, state, pushes}` when it is the drawer's, the scene then drawn again; `:unknown` otherwise."
  @callback changed(state(), game :: module(), message :: term()) ::
              {:ok, state(), [push()]} | :unknown

  @doc "The client's pane: `{columns, rows}` it shows at zoom 1."
  @callback pane(state(), {pos_integer(), pos_integer()}) :: state()

  @doc "The pushes that show a scene, given the props it is drawn with (`c:Cauldron.Client.View.props/4`)."
  @callback draw(state(), props :: keyword()) :: {state(), [push()]}

  @doc "The world point under `{fx, fy}`, fractions of the client's picture, or `nil`."
  @callback world_at(state(), props :: keyword(), {number(), number()}) ::
              {float(), float()} | nil

  @doc "Stop: the drawer's subscriptions end."
  @callback close(state(), game :: module()) :: :ok

  @doc "The RGB colour a hud names, or `nil`."
  @callback colour(name :: atom()) :: {byte(), byte(), byte()} | nil

  @doc "A push as the messages a link in this node gives its owner, each without `:cauldron_link`."
  @callback local(game :: module(), push()) :: [tuple()]

  @doc "A socket link's reader, from the link's options."
  @callback reader(opts :: keyword()) :: state()

  @doc "A push the link received: the messages are sent to `link.owner`; `{:closed, reason}` ends the link."
  @callback read(state(), event :: String.t(), payload :: term(), link()) ::
              {:ok, state()} | {:closed, term()} | :unknown

  @doc "A reader's message `{key, value}` kept in a link world's `remote` map: `{:frame, remote}` when the player gets a frame for it."
  @callback remote(remote :: map(), {atom(), term()}) ::
              {:frame | :kept, map()} | :unknown

  @doc "The scripts, head HTML and join params a browser client needs."
  @callback browser() :: %{scripts: [{String.t(), String.t()}], head: String.t(), params: map()}

  @optional_callbacks browser: 0

  @doc "The drawer module and its options."
  @spec spec(spec()) :: {module(), keyword()}
  def spec({module, opts}) when is_atom(module) and is_list(opts), do: {module, opts}
  def spec(module) when is_atom(module), do: {module, []}

  @doc "The drawer named by the `:drawer` option in `opts`; raises without one."
  @spec fetch!(keyword()) :: {module(), keyword()}
  def fetch!(opts), do: spec(Keyword.fetch!(opts, :drawer))
end
