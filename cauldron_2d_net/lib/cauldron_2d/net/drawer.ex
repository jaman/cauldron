defmodule Cauldron2D.Net.Drawer do
  @moduledoc """
  The `Cauldron.Net.Drawer` of a 2D game: each scene goes to the client as a picture, as
  scene data the client draws against the game's atlas, or as both, as the drawing
  setting (`Cauldron2D.Net.Drawing`) has it.

      use Cauldron.Net.Channel, game: MyGame.Client, drawer: {Cauldron2D.Net.Drawer, sheet_url: "/play/atlas.png"}

  ## On the server

  The first pushes are `"sheet"` (`Cauldron2D.Net.Atlas.index/2`: the atlas's sheet, its
  tile and the URL the PNG is served at) and `"drawing"` (`%{world, screen}`, who draws
  each). Each scene goes as `Cauldron2D.Net.Drawn` pushes it, over the client's pane in
  tiles. When the game's atlas changes the sheet is pushed again.

  Options:

    * `:sheet_url` — where the sheet PNG is served: a path, or `{module, function}` of no
      arguments called each time a sheet is sent, for a path that changes with the sheet.
      Default `"/atlas.png"`
    * `:drawing` — as `Cauldron2D.Net.Drawing.resolve/1` takes it
    * `:picture` — a server-drawn picture as `:png` bytes, or `:raster`, the
      `Cauldron2D.Raster` itself
    * `:local` — `true` for a client in this node: the server draws everything and
      pictures go as rasters

  A link in this node (`Cauldron.Net.Link.Local`) gives its owner `{:cauldron_link,
  :sheet, sheet, png}` (`Cauldron2D.Net.Wire.sheet/1` and the sheet's PNG),
  `{:cauldron_link, :drawing, %{world, screen}}` and `{:cauldron_link, :picture,
  raster}`.

  ## On the client

  A socket link (`Cauldron.Net.Link.Socket`) gives its owner the same sheet message, the
  PNG fetched from the server; `{:cauldron_link, :drawing, %{world, screen}}`;
  `{:cauldron_link, :picture, raster}`, the PNG decoded; and for a server that leaves
  drawing to its clients, `{:cauldron_link, :scene, view}`, a `Cauldron2D.Draw` view to
  draw over the pane, read with the link's `:atlas` (the game's own, installed on this
  node), and `{:cauldron_link, :overlay, raster | nil}` when the server draws the screen
  over it. Without an `:atlas` such a server closes the link with `:no_atlas`. A link
  world's `remote` map keeps the last `:picture`, `:drawn` view and `:overlay`;
  `Cauldron2D.Net.RemoteScene` draws it.
  """

  @behaviour Cauldron.Net.Drawer

  alias Cauldron2D.{Atlas, Draw}
  alias Cauldron2D.Net.Atlas, as: NetAtlas
  alias Cauldron2D.Net.{Drawing, Drawn, Reader, Wire}

  @type t :: %__MODULE__{
          atlas: Atlas.name(),
          sheet_url: String.t() | {module(), atom()},
          drawn: Drawn.t()
        }

  defstruct [:atlas, :sheet_url, :drawn]

  @impl true
  def open(game, opts) do
    atlas = game.atlas()
    Atlas.subscribe(atlas)
    local? = Keyword.get(opts, :local, false)
    drawing = Drawing.resolve(if local?, do: :server, else: Keyword.get(opts, :drawing))
    picture = Keyword.get(opts, :picture, if(local?, do: :raster, else: :png))

    drawer = %__MODULE__{
      atlas: atlas,
      sheet_url: Keyword.get(opts, :sheet_url, "/atlas.png"),
      drawn: Drawn.new(drawing, picture)
    }

    {drawer, [sheet(drawer), {"drawing", drawing}]}
  end

  @impl true
  def changed(%__MODULE__{atlas: atlas} = drawer, _game, {:cauldron_atlas, atlas, :changed}),
    do: {:ok, drawer, [sheet(drawer)]}

  def changed(_drawer, _game, _message), do: :unknown

  @impl true
  def pane(drawer, pane), do: %{drawer | drawn: Drawn.pane(drawer.drawn, pane)}

  @impl true
  def draw(drawer, props) do
    {drawn, pushes} = Drawn.pushes(drawer.drawn, Draw.new(props))
    {%{drawer | drawn: drawn}, pushes}
  end

  @impl true
  def world_at(drawer, props, fraction),
    do: Drawn.world_at(drawer.drawn, Draw.new(props), fraction)

  @impl true
  def close(drawer, _game), do: Atlas.unsubscribe(drawer.atlas)

  @impl true
  defdelegate colour(name), to: Cauldron2D.Palette, as: :rgb

  @impl true
  def local(game, {"sheet", sheet}),
    do: [{:sheet, Wire.sheet(sheet), NetAtlas.cached(game.atlas()).png}]

  def local(_game, {"drawing", drawing}), do: [{:drawing, drawing}]
  def local(_game, {"picture", raster}), do: [{:picture, raster}]
  def local(_game, _push), do: []

  @impl true
  defdelegate reader(opts), to: Reader, as: :new

  @impl true
  defdelegate read(reader, event, payload, link), to: Reader

  @impl true
  defdelegate remote(remote, message), to: Reader

  defp sheet(drawer),
    do: {"sheet", NetAtlas.index(NetAtlas.cached(drawer.atlas), sheet_url(drawer.sheet_url))}

  defp sheet_url({mod, fun}), do: apply(mod, fun, [])
  defp sheet_url(path) when is_binary(path), do: path
end
