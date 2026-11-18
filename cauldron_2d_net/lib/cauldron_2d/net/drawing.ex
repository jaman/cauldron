defmodule Cauldron2D.Net.Drawing do
  @moduledoc """
  Who draws a served world's picture: the server, sending each frame as an image, or
  the client (the browser, a desktop joined over the socket), sending the scene as data
  it draws itself — for the world and for the screen over it (`:screen`, `:outlines`)
  separately.

      # config/runtime.exs
      config :cauldron_2d_net, drawing: :client

  The setting is one of:

    * `:server` — the server draws everything; the client shows pictures. Every client
      sees exactly what the terminal draws, and the server pays for it in CPU and
      bandwidth
    * `:client` — the client draws everything from scene data; the server sends what
      changed
    * `:split` — the client draws the world, the server the screen, sent as an
      overlay picture only when it changes
    * `[world: part, screen: part]`, each part `:server` or `:client`

  It is read, first found, from `Cauldron2D.Net.Drawer`'s `:drawing` option, the
  `CAULDRON_DRAWING` environment variable (`server`, `client` or `split`), the
  `:cauldron_2d_net` application's `:drawing` config, and `:client`.

  A scene with a `:picture` — drawn by a function of the game's — is drawn by the
  server whatever the setting.
  """

  alias Cauldron.Launch

  @type part :: :server | :client
  @type t :: %{world: part(), screen: part()}

  @doc "The setting in force, `given` over the environment and the config."
  @spec resolve(term()) :: t()
  def resolve(given \\ nil) do
    Launch.value(
      given: given,
      env: {"CAULDRON_DRAWING", &parse/1},
      config: {:cauldron_2d_net, :drawing},
      default: :client
    )
    |> parts()
  end

  @doc "A setting's text, `server`, `client` or `split`, as its atom; `nil` for other text."
  @spec parse(String.t()) :: :server | :client | :split | nil
  def parse("server"), do: :server
  def parse("client"), do: :client
  def parse("split"), do: :split
  def parse(_text), do: nil

  @doc "A setting as its two parts."
  @spec parts(term()) :: t()
  def parts(:server), do: %{world: :server, screen: :server}
  def parts(:client), do: %{world: :client, screen: :client}
  def parts(:split), do: %{world: :client, screen: :server}

  def parts(%{world: world, screen: screen} = parts)
      when world in [:server, :client] and screen in [:server, :client], do: parts

  def parts(parts) when is_list(parts) do
    parts(%{
      world: Keyword.get(parts, :world, :server),
      screen: Keyword.get(parts, :screen, :server)
    })
  end

  def parts(other),
    do:
      raise(
        ArgumentError,
        "drawing is :server, :client, :split or [world: part, screen: part], not #{inspect(other)}"
      )
end
