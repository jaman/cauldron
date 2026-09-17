defmodule Cauldron2D.Net.Link.Socket do
  @moduledoc """
  A player's connection to a game server anywhere: the same Phoenix channel a
  browser uses, over a WebSocket, speaking `Cauldron2D.Net.Wire`.

      {:ok, link} = Cauldron2D.Net.Link.Socket.start_link(url: "http://host:port", token: token, topic: "world:main", params: %{"side" => "left"}, owner: self())

  The owner receives `{:cauldron_link, :joined}` or `{:cauldron_link, :refused, reason}`, then
  `{:cauldron_link, :sheet, sheet, png}` once (the PNG fetched from the server),
  `{:cauldron_link, :audio, %{rate: hertz, channels: 1 | 2}}` once (or `:off`, for no
  PCM at all, when asked for none or the server gives none), the format the PCM
  comes in, `{:cauldron_link, :map, map}` once, `{:cauldron_link, :frame, frame}` each tick,
  `{:cauldron_link, :pcm, chunk}` for the sound and `{:cauldron_link, :closed, reason}` when
  the connection ends. `input/2`, `levels/3` and `leave/1` are what the player does.

  Options: `:url`, the server's base HTTP URL; `:token`, from the server's login;
  `:topic`; `:params`, the join params; `:owner`; `:path`, the socket's path (default
  `"/socket/websocket"`); `:audio`, the PCM format to ask for as `%{rate: hertz,
  channels: 1 | 2}` (default the server's choice).
  """

  use GenServer

  alias Cauldron2D.Net.Wire

  @heartbeat_ms 30_000

  @doc "Connect, join and report to `:owner`."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "What the player holds and aims at, as `Cauldron2D.Wx.Input.state/1` gives it."
  @spec input(GenServer.server(), %{held: [String.t()], aim: [number()] | nil}) :: :ok
  def input(link, state), do: GenServer.cast(link, {:push, "input", state})

  @doc "The effects and music levels."
  @spec levels(GenServer.server(), number(), number()) :: :ok
  def levels(link, sfx, music),
    do: GenServer.cast(link, {:push, "levels", %{sfx: sfx, music: music}})

  @doc "Ask the server to pause or resume a world of the player's own."
  @spec pause(GenServer.server()) :: :ok
  def pause(link), do: GenServer.cast(link, {:push, "pause", %{}})

  @doc "Leave the channel, close the socket and stop."
  @spec leave(GenServer.server()) :: :ok
  def leave(link), do: GenServer.stop(link, :normal)

  @impl GenServer
  def init(opts) do
    owner = Keyword.fetch!(opts, :owner)
    Process.monitor(owner)
    uri = URI.parse(Keyword.fetch!(opts, :url))

    path =
      Keyword.get(opts, :path, "/socket/websocket") <>
        "?vsn=2.0.0&token=" <> URI.encode_www_form(Keyword.fetch!(opts, :token))

    state = %{
      owner: owner,
      base: %{uri | path: nil, query: nil},
      topic: Keyword.fetch!(opts, :topic),
      params: join_params(Keyword.get(opts, :params, %{}), Keyword.get(opts, :audio)),
      conn: nil,
      websocket: nil,
      ref: nil,
      join_ref: "1",
      next_ref: 2,
      joined?: false
    }

    with {:ok, conn} <- Mint.HTTP.connect(scheme(uri), uri.host, uri.port, protocols: [:http1]),
         {:ok, conn, ref} <- Mint.WebSocket.upgrade(ws_scheme(uri), conn, path, []) do
      Process.send_after(self(), :heartbeat, @heartbeat_ms)
      {:ok, %{state | conn: conn, ref: ref}}
    else
      {:error, reason} -> refused(owner, reason)
      {:error, _conn, reason} -> refused(owner, reason)
    end
  end

  defp join_params(params, nil), do: params

  defp join_params(params, :off), do: Map.put(params, "audio", false)

  defp join_params(params, %{rate: rate, channels: channels}),
    do: Map.put(params, "audio", %{"rate" => rate, "channels" => channels})

  defp refused(owner, reason) do
    send(owner, {:cauldron_link, :refused, reason})
    :ignore
  end

  defp scheme(%URI{scheme: "https"}), do: :https
  defp scheme(_uri), do: :http
  defp ws_scheme(%URI{scheme: "https"}), do: :wss
  defp ws_scheme(_uri), do: :ws

  @impl GenServer
  def handle_cast({:push, event, payload}, %{joined?: true} = state) do
    {ref, state} = next_ref(state)
    {:noreply, send_frame(state, Wire.encode(state.join_ref, ref, state.topic, event, payload))}
  end

  def handle_cast({:push, _event, _payload}, state), do: {:noreply, state}

  @impl GenServer
  def handle_info(:heartbeat, %{websocket: websocket} = state) when websocket != nil do
    Process.send_after(self(), :heartbeat, @heartbeat_ms)
    {ref, state} = next_ref(state)
    {:noreply, send_frame(state, Wire.encode(nil, ref, "phoenix", "heartbeat", %{}))}
  end

  def handle_info(:heartbeat, state), do: {:noreply, state}

  def handle_info({:DOWN, _ref, :process, pid, reason}, %{owner: pid} = state),
    do: {:stop, {:shutdown, {:owner_gone, reason}}, state}

  def handle_info(message, %{conn: conn} = state) when conn != nil do
    case Mint.WebSocket.stream(conn, message) do
      {:ok, conn, responses} ->
        responses |> Enum.reduce(%{state | conn: conn}, &response/2) |> continue()

      {:error, conn, reason, _responses} ->
        closed(%{state | conn: conn}, reason)

      :unknown ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp continue(%{conn: nil} = state), do: {:stop, :normal, state}
  defp continue(state), do: {:noreply, state}

  defp response({:status, ref, status}, %{ref: ref} = state), do: Map.put(state, :status, status)

  defp response({:headers, ref, headers}, %{ref: ref} = state),
    do: Map.put(state, :headers, headers)

  defp response({:done, ref}, %{ref: ref} = state) do
    case Mint.WebSocket.new(state.conn, ref, state.status, state.headers) do
      {:ok, conn, websocket} ->
        %{state | conn: conn, websocket: websocket}
        |> send_frame(
          Wire.encode(state.join_ref, state.join_ref, state.topic, "phx_join", state.params)
        )

      {:error, conn, reason} ->
        send(state.owner, {:cauldron_link, :refused, reason})
        %{state | conn: Mint.HTTP.close(conn) |> elem(1) |> then(fn _ -> nil end)}
    end
  end

  defp response({:data, ref, data}, %{ref: ref, websocket: websocket} = state)
       when websocket != nil do
    case Mint.WebSocket.decode(websocket, data) do
      {:ok, websocket, frames} -> Enum.reduce(frames, %{state | websocket: websocket}, &frame/2)
      {:error, websocket, _reason} -> %{state | websocket: websocket}
    end
  end

  defp response(_other, state), do: state

  defp frame({:text, text}, state), do: state |> message(Wire.decode(text))
  defp frame({:binary, bytes}, state), do: state |> message(Wire.decode_binary(bytes))
  defp frame({:ping, data}, state), do: send_frame(state, {:pong, data})

  defp frame({:close, _code, _reason}, state) do
    send(state.owner, {:cauldron_link, :closed, :server_closed})
    %{state | conn: nil}
  end

  defp frame(_other, state), do: state

  defp message(state, {:reply, join_ref, join_ref, topic, "ok", _response})
       when topic == state.topic do
    send(state.owner, {:cauldron_link, :joined})
    %{state | joined?: true}
  end

  defp message(state, {:reply, join_ref, join_ref, topic, "error", response})
       when topic == state.topic do
    send(state.owner, {:cauldron_link, :refused, Map.get(response, "reason", response)})
    %{state | conn: nil}
  end

  defp message(state, {:push, _join_ref, topic, event, payload}) when topic == state.topic do
    deliver(state, event, payload)
    state
  end

  defp message(state, {:push, _join_ref, _topic, "phx_error", _payload}) do
    send(state.owner, {:cauldron_link, :closed, :channel_crashed})
    %{state | conn: nil}
  end

  defp message(state, _other), do: state

  defp deliver(state, "sheet", payload) do
    sheet = Wire.sheet(payload)
    owner = state.owner
    url = URI.to_string(%{state.base | path: sheet.url})

    Task.start(fn ->
      case fetch(url) do
        {:ok, png} -> send(owner, {:cauldron_link, :sheet, sheet, png})
        {:error, reason} -> send(owner, {:cauldron_link, :closed, {:sheet, reason}})
      end
    end)
  end

  defp deliver(state, "map", payload),
    do: send(state.owner, {:cauldron_link, :map, Wire.map(payload)})

  defp deliver(state, "audio", %{"rate" => rate, "channels" => channels}),
    do: send(state.owner, {:cauldron_link, :audio, %{rate: rate, channels: channels}})

  defp deliver(state, "audio", %{"off" => true}),
    do: send(state.owner, {:cauldron_link, :audio, :off})

  defp deliver(state, "frame", payload),
    do: send(state.owner, {:cauldron_link, :frame, Wire.frame(payload)})

  defp deliver(state, "pcm", chunk) when is_binary(chunk),
    do: send(state.owner, {:cauldron_link, :pcm, chunk})

  defp deliver(_state, _event, _payload), do: :ok

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

  defp send_frame(%{websocket: nil} = state, _frame), do: state

  defp send_frame(state, frame) when is_binary(frame), do: send_frame(state, {:text, frame})

  defp send_frame(state, frame) do
    with {:ok, websocket, data} <- Mint.WebSocket.encode(state.websocket, frame),
         {:ok, conn} <- Mint.WebSocket.stream_request_body(state.conn, state.ref, data) do
      %{state | websocket: websocket, conn: conn}
    else
      {:error, %Mint.WebSocket{} = websocket, _reason} -> %{state | websocket: websocket}
      {:error, conn, reason} -> closed(%{state | conn: conn}, reason) |> elem(2)
    end
  end

  defp closed(state, reason) do
    send(state.owner, {:cauldron_link, :closed, reason})
    {:stop, :normal, %{state | conn: nil}}
  end

  defp next_ref(state),
    do: {Integer.to_string(state.next_ref), %{state | next_ref: state.next_ref + 1}}

  @impl GenServer
  def terminate(_reason, %{conn: conn, websocket: websocket, joined?: joined?} = state)
      when conn != nil and websocket != nil do
    {ref, state} = next_ref(state)

    state =
      if joined?,
        do: send_frame(state, Wire.encode(state.join_ref, ref, state.topic, "phx_leave", %{})),
        else: state

    if state.conn, do: Mint.HTTP.close(state.conn)
    :ok
  end

  def terminate(_reason, _state), do: :ok
end
