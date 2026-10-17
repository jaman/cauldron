defmodule Cauldron3D.Net.Socket do
  @moduledoc """
  The socket browsers watching scenes connect through, with the channel
  `Cauldron3D.Net.Channel` defines.

      defmodule MyGame.Web.SceneSocket do
        use Cauldron3D.Net.Socket, channel: MyGame.Web.SceneChannel
      end

  `:topic` is the channel's topic prefix (default `"scene"`). `:verify`, a `{module,
  function}` given the connect params and answering `{:ok, assigns}` or `:error`, decides
  who may connect; without it everyone may.
  """

  defmacro __using__(opts) do
    channel = Keyword.fetch!(opts, :channel)
    prefix = Keyword.get(opts, :topic, "scene")
    verify = Keyword.get(opts, :verify)

    quote do
      use Phoenix.Socket

      channel(unquote(prefix) <> ":*", unquote(channel))

      @impl true
      def connect(params, socket, _connect_info) do
        case Cauldron3D.Net.Socket.verify(unquote(verify), params) do
          {:ok, assigns} -> {:ok, Phoenix.Socket.assign(socket, assigns)}
          :error -> :error
        end
      end

      @impl true
      def id(_socket), do: nil
    end
  end

  @doc false
  @spec verify({module(), atom()} | nil, map()) :: {:ok, map()} | :error
  def verify(nil, _params), do: {:ok, %{}}
  def verify({module, function}, params), do: apply(module, function, [params])
end
