defmodule Cauldron2D.Client.Game do
  @moduledoc """
  What a 2D game gives a client, over `Cauldron.Client.Game`: its atlas (`atlas/0`), and
  scenes and looks drawn by `Cauldron2D.Client.View`.

      defmodule MyGame.Client do
        use Cauldron2D.Client.Game

        def title, do: %{name: "My Game"}
        def atlas, do: :my_game
        def actions, do: [:left, :right, :launch]
        def keymaps, do: [arrows: %{left: [:left], right: [:right], launch: [:" "]}]
        def worlds(_props), do: Cauldron.Worlds.list()
        def scene(view, _look), do: %{focus: view.me.pos, bounds: view.bounds, cell: &MyGame.cell/1, movers: view.movers}
      end

  `use Cauldron2D.Client.Game` is `use Cauldron.Client.Game` (its defaults for the
  callbacks most games write the same way) with `view/0` answering
  `Cauldron2D.Client.View`, and declares this behaviour, whose one callback is `atlas/0`:
  the `Cauldron2D.Atlas` the game's tiles, sprites and fonts are in.

  ## Scenes

  A scene is a map with `:focus` (the world point the view is drawn around), `:bounds`
  (the world's size in tiles, or `:unbounded`), `:cell` (a function from a tile to what
  is there) and `:movers` (`{art, {x, y}}`, with a heading as a third element, `{art,
  {x, y}, heading}`, for the projections that pose them).

  Its `:volumes` are coloured regions of space, as `Cauldron2D.Projection.Volume`
  describes them, that tint what is seen through them in every projection. Its
  `:layers` are `Cauldron2D.Parallax` layers drawn behind the world, and in front of it
  where a layer has `front: true`, in the top-down view. Its `:labels` are text drawn
  over the world as `Cauldron2D.Surface.compose/4` takes them, in tiles; default none.
  Its `:screen` is what is drawn fixed to the pane rather than to the world — the hud, a
  menu, a title — as `Cauldron2D.Screen` describes it, over everything else; default
  none. A game that draws its hud there returns `[]` from `hud/1`. Its `:outlines`,
  `[{{left, top, right, bottom}, {r, g, b, a}}]` in world tiles, are boxes drawn as
  their edges over everything — hit boxes, triggers, regions — to check them while
  building a game. Its `:subject` is as `Cauldron.Client.Game` describes. Its
  `:heading`, in radians with `0` along `+x`, is where the subject looks: a first-person
  view is drawn along it, and a client whose scene gives none turns the eye itself.

  A scene with a `:picture` — `fn {width, height}, aspect -> raster end` — is drawn by
  the game itself rather than from the atlas: the client draws it as the `:picture`
  projection, at the pane's size in pixels, and the focus, cell and movers then serve
  only the listener and the pointer. A scene's `:native` (`{width, height}`), over the
  look's, is the picture's own size in pixels: the size a terminal client draws it at
  times a whole number, for a terminal that keeps images to scale.

  A scene with a `:picture` may also have a `:gpu` —
  `fn target, cache, {width, height}, aspect -> {changes, cache} end` — the same picture
  described for a graphics card: it uploads what it needs through `target` (a
  `Cauldron3D.Scene.Target`) and answers the tick's `Cauldron3D.Scene.Stream` changes, with the
  game's 2D layer (status bar, messages, menus) as an `{:overlay, texture}`. `cache` is
  what it answered last time, `nil` the first time. A scene with a `:gpu` may give
  `:gpu_size` (`{width, height}`), the size the graphics card draws it at for the
  terminal to scale to the pane; without it the card draws at the pane's own pixels. A
  client whose picture options ask for the graphics card draws with `:gpu` when the
  scene has it and the card opens, and with `:picture` otherwise.

  ## Looks

  `c:Cauldron.Client.Game.look/0` may give, over `Cauldron2D.Client.Look`'s defaults,
  any of `:projection` (`:top`, `:oblique`, `:iso`, `:mode7` or `:first_person`),
  `:projections` (a list of those, the views the projection key cycles through in
  order; default top-down, isometric and first person), `:facing` (a step), `:facings`
  (steps in a turn), `:tilt` (`0.5..1.5`), `:heading` (radians), `:pitch`
  (`-1.0..1.0`), `:zoom` (how many times native a tile is drawn when a world opens),
  `:native` (`{width, height}`, a picture's own size in pixels), `:density` (the pixels
  a terminal client draws a cell with) and `:picture` (the picture options a terminal
  client uses when the player gives none).
  """

  @type scene :: %{
          required(:focus) => {number(), number()},
          required(:bounds) => {pos_integer(), pos_integer()} | :unbounded,
          required(:cell) => ({integer(), integer()} -> term()),
          required(:movers) => [
            {term(), {number(), number()}}
            | {term(), {number(), number()}, number() | nil}
            | {term(), {number(), number()}, number() | nil, %{optional(:tint) => atom()}}
          ],
          optional(:labels) => list(),
          optional(:screen) => [Cauldron2D.Screen.item()],
          optional(:volumes) => list(),
          optional(:layers) => [Cauldron2D.Parallax.Layer.t()],
          optional(:subject) => String.t() | atom() | number(),
          optional(:heading) => number(),
          optional(:picture) => ({pos_integer(), pos_integer()}, number() ->
                                   FrenchCurve.Raster.t()),
          optional(:native) => {pos_integer(), pos_integer()},
          optional(:gpu) => (term(), term(), {pos_integer(), pos_integer()}, number() ->
                               {list(), term()}),
          optional(:gpu_size) => {pos_integer(), pos_integer()},
          optional(:outlines) => [{Cauldron2D.Box.t(), {byte(), byte(), byte(), byte()}}]
        }

  @callback atlas() :: Cauldron2D.Atlas.name()

  @doc false
  defmacro __using__(_opts) do
    quote do
      use Cauldron.Client.Game
      @behaviour Cauldron2D.Client.Game

      def view, do: Cauldron2D.Client.View

      defoverridable view: 0
    end
  end
end
