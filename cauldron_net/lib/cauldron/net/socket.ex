defmodule Cauldron.Net.Socket do
  @moduledoc """
  The player socket a game's browser players connect through, with the channel
  `Cauldron.Net.Channel` defines.

      defmodule MyGame.Web.UserSocket do
        use Cauldron.Net.Socket, channel: MyGame.Web.WorldChannel, verify: {MyGame.Web.Auth, :verify}
      end

  `:verify` names a function given the connect params and answering `{:ok, assigns}`
  — a map with the player's `:username` and, when the game keeps them, `:settings`
  (`:sfx` and `:music` levels) — or `:error`. `:topic` is the channel's topic prefix
  (default `"world"`). `voice: true` also routes the `"voice"` topic to
  `Cauldron.Net.Voice.Channel`, which takes players only while `Cauldron.Net.Voice` is on.
  """

  defmacro __using__(opts) do
    channel = Keyword.fetch!(opts, :channel)
    {mod, fun} = Keyword.fetch!(opts, :verify)
    prefix = Keyword.get(opts, :topic, "world")
    voice = Keyword.get(opts, :voice, false)

    quote do
      use Phoenix.Socket

      channel(unquote(prefix) <> ":*", unquote(channel))

      if unquote(voice), do: channel("voice", Cauldron.Net.Voice.Channel)

      @impl true
      def connect(params, socket, _connect_info) do
        case unquote(mod).unquote(fun)(params) do
          {:ok, %{username: username} = assigns} ->
            {:ok,
             socket
             |> assign(:username, username)
             |> assign(:settings, Cauldron.Net.Socket.settings(assigns))}

          :error ->
            :error
        end
      end

      @impl true
      def id(socket), do: "player:" <> socket.assigns.username
    end
  end

  @doc "The settings a verified player's assigns carry: their `:settings`, or `%{}` when they have none."
  @spec settings(map()) :: map()
  def settings(%{settings: settings}), do: settings
  def settings(_assigns), do: %{}
end
