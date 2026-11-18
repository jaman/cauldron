defmodule Cauldron2D.Net.Reader do
  @moduledoc """
  The client side of `Cauldron2D.Net.Drawer`: what a socket link makes of the pushes a 2D
  session sends, and what a link world keeps of them. `Cauldron2D.Net.Drawer` describes
  the messages.
  """

  alias Cauldron2D.Net.{Scene, Wire}

  @type t :: %{scene: term() | nil}

  @doc "A reader for the link's options: `:atlas`, the game's atlas installed here, reads scenes the client draws."
  @spec new(keyword()) :: t()
  def new(opts) do
    case Keyword.get(opts, :atlas) do
      nil -> %{scene: nil}
      atlas -> %{scene: Scene.reader(atlas)}
    end
  end

  @doc "A push the link received, its messages sent to `link.owner` (`c:Cauldron.Net.Drawer.read/4`)."
  @spec read(t(), String.t(), term(), Cauldron.Net.Drawer.link()) ::
          {:ok, t()} | {:closed, term()} | :unknown
  def read(%{scene: nil}, "scene", _payload, _link), do: {:closed, :no_atlas}

  def read(reader, "scene", payload, link) do
    {scene, view} = Scene.read(reader.scene, payload)
    send(link.owner, {:cauldron_link, :scene, view})
    {:ok, %{reader | scene: scene}}
  end

  def read(reader, "sheet", payload, link) do
    sheet = Wire.sheet(payload)
    url = URI.to_string(%{link.base | path: sheet.url})
    owner = link.owner

    Task.start(fn ->
      case fetch(url) do
        {:ok, png} -> send(owner, {:cauldron_link, :sheet, sheet, png})
        {:error, reason} -> send(owner, {:cauldron_link, :closed, {:sheet, reason}})
      end
    end)

    {:ok, reader}
  end

  def read(reader, "drawing", payload, link) do
    send(link.owner, {:cauldron_link, :drawing, Wire.drawing(payload)})
    {:ok, reader}
  end

  def read(reader, "picture", png, link) when is_binary(png) do
    decoded(link, :picture, png)
    {:ok, reader}
  end

  def read(reader, "overlay", "", link) do
    send(link.owner, {:cauldron_link, :overlay, nil})
    {:ok, reader}
  end

  def read(reader, "overlay", png, link) when is_binary(png) do
    decoded(link, :overlay, png)
    {:ok, reader}
  end

  def read(_reader, _event, _payload, _link), do: :unknown

  @doc "A link world's `remote` map with a message kept (`c:Cauldron.Net.Drawer.remote/2`): a picture or a scene makes a frame."
  @spec remote(map(), {atom(), term()}) :: {:frame | :kept, map()} | :unknown
  def remote(remote, {:picture, raster}),
    do: {:frame, Map.merge(remote, %{picture: raster, drawn: nil})}

  def remote(remote, {:scene, view}),
    do: {:frame, Map.merge(remote, %{drawn: view, picture: nil})}

  def remote(remote, {:overlay, overlay}), do: {:kept, Map.put(remote, :overlay, overlay)}
  def remote(_remote, _message), do: :unknown

  defp decoded(link, key, png) do
    case Linocut.Png.decode(png) do
      {:ok, raster} -> send(link.owner, {:cauldron_link, key, raster})
      {:error, _reason} -> :ok
    end
  end

  defp fetch(url) do
    :inets.start()
    :ssl.start()

    case :httpc.request(
           :get,
           {String.to_charlist(url), []},
           [ssl: [verify: :verify_none], timeout: 15_000],
           body_format: :binary
         ) do
      {:ok, {{_, 200, _}, _headers, body}} -> {:ok, body}
      {:ok, {{_, status, _}, _headers, _body}} -> {:error, status}
      {:error, reason} -> {:error, reason}
    end
  end
end
