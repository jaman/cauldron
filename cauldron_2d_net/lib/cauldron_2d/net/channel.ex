defmodule Cauldron2D.Net.Channel do
  @moduledoc """
  The Phoenix channel a game's browser players join, one per player, driven by
  `Cauldron2D.Net.Session`.

      defmodule MyGame.Web.WorldChannel do
        use Cauldron2D.Net.Channel, game: MyGame.Client, topic: "world", audio: %{rate: 22_050, channels: 2}
      end

  `:game` implements `Cauldron2D.Client.Game`. The topic is `"world:<id>"` (`:topic`
  names another prefix); `id` is the arena, as its id writes, among the game's
  `arenas/1` given the socket's assigns. The socket's assigns must carry `:username`; `:settings` (a map with `:sfx`
  and `:music`) and `:sheet_url` are read when present. The join params reach the game's
  `join_props/1` as `:params`, and whatever it returns joins the world as props; a
  join param `"audio"` of `%{"rate" => hertz, "channels" => 1 | 2}` (8 000 to 48 000
  Hz) is the PCM format the browser wants, as `cauldron.js`'s `audio` option sends it;
  without one the format is the `:audio` option of `use` (default 44 100 Hz stereo), and
  `false` asks for no sound; what the session gets is `Cauldron2D.Net.Audio`'s to say.
  A refusal is shown as the game's `refusal_text/1` gives it, `inspect/1` without one.

  Frames from the world are pushed as `"map"` and `"frame"`, a changed atlas as a new
  `"sheet"` and the `"map"` again, the audio as binary
  `"pcm"` pushes (the session's own stage and the world's shared music mixed, as
  `Cauldron2D.Net.Audio`'s policy has it); `"input"` (`held`, `aim` and an optional `strength`), `"levels"`,
  `"music"` (`on`, the music switched off or back on at its level) and
  `"pause"` (for a world of the player's own) from the browser reach the session. Leaving the channel leaves the world. Input
  messages arrive many times a second and are not logged.
  """

  alias Cauldron2D.Client.Game
  alias Cauldron2D.Net.Audio, as: NetAudio

  defmacro __using__(opts) do
    game = Keyword.fetch!(opts, :game)
    prefix = Keyword.get(opts, :topic, "world")
    audio = Keyword.get(opts, :audio, Macro.escape(%{rate: 44_100, channels: 2}))

    quote do
      use Phoenix.Channel, log_handle_in: false

      alias Cauldron2D.Net.Session

      @impl true
      def join(unquote(prefix) <> ":" <> id, params, socket) do
        case Cauldron2D.Net.Channel.arena(unquote(game), socket.assigns, id) do
          nil ->
            {:error, %{reason: "no such world"}}

          %{world: world} ->
            props = Cauldron2D.Net.Channel.props(socket.assigns, params)
            sheet_url = Map.get(socket.assigns, :sheet_url, "/atlas.png")

            case Session.join(
                   unquote(game),
                   world,
                   socket.assigns.username,
                   props,
                   Cauldron2D.Net.Channel.audio(params) ++
                     [sheet_url: sheet_url, audio: unquote(audio)]
                 ) do
              {:ok, session, pushes} ->
                NetAudio.subscribe()
                send(self(), {:cauldron_web_pushes, pushes})
                {:ok, assign(socket, :session, session)}

              {:error, reason} ->
                {:error, %{reason: Cauldron2D.Net.Channel.reason(unquote(game), reason)}}
            end
        end
      end

      @impl true
      def handle_in("input", %{"held" => held, "aim" => aim} = payload, socket)
          when is_list(held) do
        strength = if is_map(payload["strength"]), do: payload["strength"], else: %{}

        {:noreply,
         assign(socket, :session, Session.input(socket.assigns.session, held, aim, strength))}
      end

      def handle_in("levels", %{"sfx" => sfx, "music" => music}, socket)
          when is_number(sfx) and is_number(music) do
        {:noreply, assign(socket, :session, Session.levels(socket.assigns.session, sfx, music))}
      end

      def handle_in("music", %{"on" => on}, socket) when is_boolean(on) do
        {:noreply, assign(socket, :session, Session.music(socket.assigns.session, on))}
      end

      def handle_in("pause", _payload, socket) do
        {:noreply, assign(socket, :session, Session.toggle_pause(socket.assigns.session))}
      end

      def handle_in(_event, _payload, socket), do: {:noreply, socket}

      @impl true
      def handle_info({:cauldron_frame, message}, socket) do
        {session, pushes} = Session.frame(socket.assigns.session, message)
        Cauldron2D.Net.Channel.push_all(socket, pushes)
        {:noreply, assign(socket, :session, session)}
      end

      def handle_info({:cauldron_atlas, _name, :changed}, socket) do
        {session, pushes} = Session.atlas_changed(socket.assigns.session)
        Cauldron2D.Net.Channel.push_all(socket, pushes)
        {:noreply, assign(socket, :session, session)}
      end

      def handle_info({:pcm, chunk}, socket) do
        {session, pushes} = Session.pcm(socket.assigns.session, chunk)
        Cauldron2D.Net.Channel.push_all(socket, pushes)
        {:noreply, assign(socket, :session, session)}
      end

      def handle_info({:cauldron_shared_pcm, chunk}, socket) do
        {session, pushes} = Session.shared_pcm(socket.assigns.session, chunk)
        Cauldron2D.Net.Channel.push_all(socket, pushes)
        {:noreply, assign(socket, :session, session)}
      end

      def handle_info({:cauldron_audio_rate, rate}, socket) do
        {session, pushes} = Session.rerate(socket.assigns.session, rate)
        Cauldron2D.Net.Channel.push_all(socket, pushes)
        {:noreply, assign(socket, :session, session)}
      end

      def handle_info({:cauldron_web_pushes, pushes}, socket) do
        Cauldron2D.Net.Channel.push_all(socket, pushes)
        {:noreply, socket}
      end

      def handle_info(_message, socket), do: {:noreply, socket}

      @impl true
      def terminate(_reason, socket) do
        case socket.assigns do
          %{session: session} -> Session.leave(session)
          _ -> :ok
        end
      end
    end
  end

  @doc false
  def props(assigns, params), do: %{settings: Map.get(assigns, :settings, %{}), params: params}

  @doc ~S|The `:audio` option for `Cauldron2D.Net.Session.join/5` from the join params: the format asked, `:off` for `"audio": false`, `[]` without a valid `"audio"`.|
  @spec audio(map()) :: [audio: %{rate: pos_integer(), channels: 1 | 2} | :off]
  def audio(%{"audio" => false}), do: [audio: :off]

  def audio(%{"audio" => %{"rate" => rate, "channels" => channels}})
      when is_integer(rate) and rate >= 8_000 and rate <= 48_000 and channels in [1, 2] do
    [audio: %{rate: rate, channels: channels}]
  end

  def audio(_params), do: []

  @doc false
  def push_all(socket, pushes) do
    Enum.each(pushes, fn
      {event, payload} when is_binary(payload) ->
        Phoenix.Channel.push(socket, event, {:binary, payload})

      {event, payload} ->
        Phoenix.Channel.push(socket, event, payload)
    end)
  end

  @doc false
  def reason(game, reason), do: Game.refusal_text(game, reason)

  @doc false
  def arena(game, assigns, id), do: Game.arena(game, assigns, id)
end
