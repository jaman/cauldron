defmodule Cauldron2D.Net.Socket do
  @moduledoc """
  The player socket a game's browser players connect through, with the channel
  `Cauldron2D.Net.Channel` defines.

      defmodule MyGame.Web.UserSocket do
        use Cauldron2D.Net.Socket, channel: MyGame.Web.WorldChannel, verify: {MyGame.Web.Auth, :verify}
      end

  `:verify` names a function given the connect params and answering `{:ok, assigns}`
  — a map with the player's `:username` and, when the game keeps them, `:settings`
  (`:sfx` and `:music` levels) — or `:error`. `:topic` is the channel's topic prefix
  (default `"world"`), `:sheet_url` where the sheet is served (default `"/atlas.png"`).
  """

  defmacro __using__(opts) do
    channel = Keyword.fetch!(opts, :channel)
    {mod, fun} = Keyword.fetch!(opts, :verify)
    prefix = Keyword.get(opts, :topic, "world")
    sheet_url = Keyword.get(opts, :sheet_url, "/atlas.png")

    quote do
      use Phoenix.Socket

      channel(unquote(prefix) <> ":*", unquote(channel))

      @impl true
      def connect(params, socket, _connect_info) do
        case unquote(mod).unquote(fun)(params) do
          {:ok, %{username: username} = assigns} ->
            {:ok,
             socket
             |> assign(:username, username)
             |> assign(:settings, Map.get(assigns, :settings, %{}))
             |> assign(:sheet_url, unquote(sheet_url))}

          :error ->
            :error
        end
      end

      @impl true
      def id(socket), do: "player:" <> socket.assigns.username
    end
  end
end
