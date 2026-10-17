defmodule Cauldron3D.Net.Channel do
  @moduledoc """
  The Phoenix channel a browser joins to watch a `Cauldron3D.Net.Scene`.

      defmodule MyGame.Web.SceneChannel do
        use Cauldron3D.Net.Channel
      end

  The topic is `"scene:<id>"` (`:topic` names another prefix), `id` a scene started with
  `Cauldron3D.Net.Scene.start_link/1`. On joining, the browser is pushed the whole scene
  as one binary `"changes"` message, then each batch the scene broadcasts; its `"event"`
  messages reach the scene's `:events` pid (`Cauldron3D.Net.Events`), with `:joined` when
  it arrives and `:left` when it goes.
  """

  defmacro __using__(opts) do
    prefix = Keyword.get(opts, :topic, "scene")

    quote do
      use Phoenix.Channel, log_handle_in: false

      alias Cauldron3D.Net.{Events, Scene}

      @impl true
      def join(unquote(prefix) <> ":" <> id, _params, socket) do
        case Scene.lookup(id) do
          nil ->
            {:error, %{reason: "no such scene"}}

          scene ->
            Phoenix.PubSub.subscribe(Cauldron3D.Net.PubSub, Scene.topic(id))
            send(self(), :snapshot)
            session = make_ref()
            Scene.event(scene, session, :joined)
            {:ok, assign(socket, scene: scene, session: session)}
        end
      end

      @impl true
      def handle_info(:snapshot, socket) do
        push(socket, "changes", {:binary, Scene.snapshot(socket.assigns.scene)})
        {:noreply, socket}
      end

      def handle_info({:cauldron_3d_net_changes, bytes}, socket) do
        push(socket, "changes", {:binary, bytes})
        {:noreply, socket}
      end

      @impl true
      def handle_in("event", message, socket) do
        with {:ok, event} <- Events.decode(message),
             do: Scene.event(socket.assigns.scene, socket.assigns.session, event)

        {:noreply, socket}
      end

      @impl true
      def terminate(_reason, socket) do
        if scene = socket.assigns[:scene], do: Scene.event(scene, socket.assigns.session, :left)
        :ok
      end
    end
  end
end
