defmodule Cauldron3D.Net.Drawer do
  @moduledoc """
  A `Cauldron.Net.Drawer` for 3D games: each client is sent its scene as the changes a
  renderer takes (`Cauldron3D.Scene.Stream`), and draws it with its own renderer.

      use Cauldron.Net.Channel, game: MyGame.Client, drawer: Cauldron3D.Net.Drawer

  A game's scene gives the drawer a `:gpu` closure, `fn target, cache, {width, height},
  aspect -> {changes, cache} end`, and optionally `:gpu_size`. For each client the drawer
  keeps an outbox (`Cauldron3D.Net.Outbox`) the closure uploads to, so a client joining
  later is given the whole scene, and uploads the game makes from another process reach
  the client as they finish.

  Pushes are `{"changes", payload}`: `Cauldron3D.Scene.Stream` bytes for a browser, which
  joins with the param `"changes" => "stream"` and draws them with `cauldron3d.js`
  (the game pages load it from `browser/0`: `Cauldron2D.Net.Pages` with `drawer:
  Cauldron3D.Net.Drawer`);
  the change terms, as `:erlang.term_to_binary/1`, for any other client, which reads them
  safely (its reader loads `cauldron_3d_scene`'s modules, whose atoms the changes use) and keeps them
  with `Cauldron3D.Net.RemoteScene` and draws them with `Cauldron3D.Net.Replay`; the
  terms themselves for a client in the same node.

  A client's pane (`c:Cauldron.Net.Drawer.pane/2`) is its picture's size in pixels; the
  scene's `:gpu_size` stands in until the client gives one. There is no world point under
  the pointer (`world_at/3` is `nil`); hud colours are `Cauldron.Palette`'s.
  """

  @behaviour Cauldron.Net.Drawer

  alias Cauldron3D.Net.{Outbox, Page, RemoteScene}
  alias Cauldron3D.Scene.{Stream, Target}

  @enforce_keys [:outbox, :format]
  defstruct [:outbox, :format, size: nil, cache: nil]

  @type t :: %__MODULE__{
          outbox: Outbox.t(),
          format: :stream | :terms | :local,
          size: {pos_integer(), pos_integer()} | nil,
          cache: term()
        }

  @default_size {1280, 720}

  @impl Cauldron.Net.Drawer
  def open(_game, opts) do
    {:ok, outbox} = Outbox.start_link()
    {%__MODULE__{outbox: outbox, format: format(opts)}, []}
  end

  @impl Cauldron.Net.Drawer
  def changed(%__MODULE__{} = drawer, _game, {Outbox, ref, :changed}) do
    if ref == Outbox.ref(drawer.outbox),
      do: {:ok, drawer, taken(drawer)},
      else: :unknown
  end

  def changed(_drawer, _game, _message), do: :unknown

  @impl Cauldron.Net.Drawer
  def pane(drawer, {width, height}) when width > 0 and height > 0,
    do: %{drawer | size: {width, height}}

  def pane(drawer, _pane), do: drawer

  @impl Cauldron.Net.Drawer
  def draw(drawer, props), do: drawn(drawer, props[:gpu], props[:gpu_size])

  @impl Cauldron.Net.Drawer
  def world_at(_drawer, _props, _fraction), do: nil

  @impl Cauldron.Net.Drawer
  def close(drawer, _game), do: Outbox.stop(drawer.outbox)

  @impl Cauldron.Net.Drawer
  def colour(name), do: Cauldron.Palette.rgb(name)

  @impl Cauldron.Net.Drawer
  def local(_game, {"changes", changes}) when is_list(changes), do: [{:changes, changes}]
  def local(_game, _push), do: []

  @impl Cauldron.Net.Drawer
  def browser do
    three = "https://cdn.jsdelivr.net/npm/three@#{Page.three_version()}"
    static = Application.app_dir(:cauldron_3d_net, "priv/static")

    %{
      scripts: [
        {"cauldron3d.js", Path.join(static, "cauldron3d.js")},
        {"cauldron3d_drawer.js", Path.join(static, "cauldron3d_drawer.js")}
      ],
      head:
        ~s|<script type="importmap">{"imports": {"three": "#{three}/build/three.module.js", "three/addons/": "#{three}/examples/jsm/"}}</script>|,
      params: %{"changes" => "stream"}
    }
  end

  @impl Cauldron.Net.Drawer
  def reader(_opts) do
    {:ok, modules} = :application.get_key(:cauldron_3d_scene, :modules)
    Enum.each(modules, &Code.ensure_loaded/1)
    %{}
  end

  @impl Cauldron.Net.Drawer
  def read(reader, "changes", payload, link) when is_binary(payload) do
    send(link.owner, {:cauldron_link, :changes, :erlang.binary_to_term(payload, [:safe])})
    {:ok, reader}
  end

  def read(_reader, _event, _payload, _link), do: :unknown

  @impl Cauldron.Net.Drawer
  def remote(remote, {:changes, changes}), do: {:frame, RemoteScene.received(remote, changes)}
  def remote(_remote, _message), do: :unknown

  defp format(opts) do
    cond do
      Keyword.get(opts, :local) == true -> :local
      get_in(opts, [:params, "changes"]) == "stream" -> :stream
      true -> :terms
    end
  end

  defp drawn(drawer, nil, _gpu_size), do: {drawer, []}

  defp drawn(drawer, gpu, gpu_size) do
    {width, height} = size = drawer.size || gpu_size || @default_size
    {changes, cache} = gpu.(drawer.outbox, drawer.cache, size, width / height)
    Target.submit(drawer.outbox, changes)
    drawer = %{drawer | cache: cache}
    {drawer, taken(drawer)}
  end

  defp taken(drawer) do
    case Outbox.take(drawer.outbox) do
      [] -> []
      changes -> [{"changes", payload(drawer.format, changes)}]
    end
  end

  defp payload(:stream, changes), do: changes |> Stream.encode() |> IO.iodata_to_binary()
  defp payload(:terms, changes), do: :erlang.term_to_binary(changes)
  defp payload(:local, changes), do: changes
end
