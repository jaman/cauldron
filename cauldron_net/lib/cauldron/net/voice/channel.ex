defmodule Cauldron.Net.Voice.Channel do
  @moduledoc """
  The `"voice"` channel a player's browser joins to make and take calls (`Cauldron.Net.Voice`).
  The player is the socket's `:username`. Joining is refused while voice is off.

  The join reply is `Cauldron.Net.Voice.browser/1` with the player's `state`. The browser sends:

    * `"call"` `%{to: name}`, `"accept"` `%{from: name}`, `"decline"` `%{from: name}`,
      `"hang_up"` `%{with: name}`, `"mute"` `%{muted: boolean}`
    * `"signal"` `%{to: name, data: term}` — an offer, answer or address for a player it is
      talking to, handed on as `"signal"` `%{from: name, data: term}`
    * `"audio"`, binary: a byte giving the length of the other player's name, the name in UTF-8,
      then one Opus packet. It is handed on, when the server relays and the two are talking, with
      the sender's name in place of the receiver's

  It is pushed the events `Cauldron.Net.Voice.Calls` lists, and `"signal"` and `"audio"` from
  the players it talks to. Anything sent for a player the sender is not talking to is dropped.
  """

  use Phoenix.Channel, log_handle_in: false

  alias Cauldron.Net.Voice
  alias Cauldron.Net.Voice.Calls

  @impl Phoenix.Channel
  def join("voice", _params, socket) do
    if Voice.open?() do
      name = socket.assigns.username
      :ok = Calls.present(name, self())
      {:ok, Map.put(Voice.browser(name), :state, Calls.state(name)), socket}
    else
      {:error, %{reason: "voice is off"}}
    end
  end

  @impl Phoenix.Channel
  def handle_in("call", %{"to" => to}, socket), do: answer(Calls.call(me(socket), to), socket)

  def handle_in("accept", %{"from" => from}, socket),
    do: answer(Calls.accept(me(socket), from), socket)

  def handle_in("decline", %{"from" => from}, socket),
    do: answer(Calls.decline(me(socket), from), socket)

  def handle_in("hang_up", %{"with" => other}, socket),
    do: answer(Calls.hang_up(me(socket), other), socket)

  def handle_in("mute", %{"muted" => muted}, socket),
    do: answer(Calls.mute(me(socket), muted == true), socket)

  def handle_in("signal", %{"to" => to, "data" => data}, socket) do
    with true <- Calls.talking?(me(socket), to), pid when is_pid(pid) <- Calls.carrier(to) do
      send(pid, {:cauldron_voice_signal, me(socket), data})
    end

    {:noreply, socket}
  end

  def handle_in("audio", {:binary, <<length, to::binary-size(length), packet::binary>>}, socket) do
    from = me(socket)

    with %{relay: true} <- Voice.settings(),
         true <- byte_size(from) < 256,
         true <- Calls.talking?(from, to),
         pid when is_pid(pid) <- Calls.carrier(to) do
      send(pid, {:cauldron_voice_audio, <<byte_size(from), from::binary, packet::binary>>})
    end

    {:noreply, socket}
  end

  def handle_in(_event, _payload, socket), do: {:noreply, socket}

  @impl Phoenix.Channel
  def handle_info({:cauldron_voice, event, payload}, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end

  def handle_info({:cauldron_voice_signal, from, data}, socket) do
    push(socket, "signal", %{from: from, data: data})
    {:noreply, socket}
  end

  def handle_info({:cauldron_voice_audio, frame}, socket) do
    push(socket, "audio", {:binary, frame})
    {:noreply, socket}
  end

  defp me(socket), do: socket.assigns.username

  defp answer(:ok, socket), do: {:reply, :ok, socket}

  defp answer({:error, reason}, socket),
    do: {:reply, {:error, %{reason: Atom.to_string(reason)}}, socket}
end
