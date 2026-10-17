defmodule Cauldron2D.Link do
  @moduledoc """
  Two `Cauldron2D.World`s on two machines playing with rollback over one TCP connection,
  without BEAM distribution: nothing a peer sends can run code in this VM.

      {:ok, listener} = Cauldron2D.Link.listen(host_world, port: 0)
      Cauldron2D.Link.port(listener)

      {:ok, link} = Cauldron2D.Link.connect({192, 168, 1, 5}, port)
      Cauldron2D.World.start_link(game: MyGame, follow: link, rollback: true)

  `listen/2` accepts connections on `:port` (default any free port) for the world
  `world`, one link process for each. `connect/3` makes a link process on this machine
  that stands for that world: a world started with `follow: link, rollback: ...` plays
  with it as if it were the host world itself.

  A link carries only what two worlds playing with rollback send each other: the
  rollback messages (`Cauldron2D.World.Rollback`) and the calls a world makes of its host
  (its tick rate, starting to play, joins and leaves). Each message is a 4-byte length
  and an Erlang term, read with `:erlang.binary_to_term/2`'s `:safe`; a message of any
  other shape closes the connection. Pids never cross: a link puts itself in the place of
  every pid in what it passes on, so the world on the other side sees the link as the
  peer, and as every player of the other machine. When the connection closes the link
  stops, so the world sees its peer, and those players, gone.

  `ping/3` measures the round trip to a listener by connecting and closing again.
  `drop/1` closes every connection a listener has accepted, so the worlds on the other
  side see their peer gone.
  """

  use GenServer

  @call_timeout 9_000
  @max_frame 4 * 1024 * 1024

  @doc """
  Accept connections on `:port` (default `0`, any free port) for `world`. Returns the
  listener; `port/1` gives the port it took.
  """
  @spec listen(GenServer.server(), keyword()) :: {:ok, pid()} | {:error, term()}
  def listen(world, opts \\ []), do: GenServer.start_link(__MODULE__, {:listen, world, opts})

  @doc "The port `listener` accepts connections on."
  @spec port(pid()) :: :inet.port_number()
  def port(listener), do: GenServer.call(listener, :port)

  @doc "Stop a listener accepting connections, links already made going on; or close a link's connection."
  @spec close(pid()) :: :ok
  def close(link), do: GenServer.stop(link, :normal)

  @doc "Close every connection `listener` has accepted that is still open."
  @spec drop(pid()) :: :ok
  def drop(listener), do: GenServer.call(listener, :drop)

  @doc """
  A link to the world behind the listener at `address` and `port`, for a world of this
  machine to follow. `{:error, reason}` when it cannot connect within `timeout`
  milliseconds (default `5_000`).
  """
  @spec connect(:inet.ip_address() | String.t(), :inet.port_number(), timeout()) ::
          {:ok, pid()} | {:error, term()}
  def connect(address, port, timeout \\ 5_000),
    do: GenServer.start(__MODULE__, {:connect, address(address), port, timeout})

  @doc "The milliseconds a TCP connection to `address` and `port` takes to open, or `{:error, reason}`."
  @spec ping(:inet.ip_address() | String.t(), :inet.port_number(), timeout()) ::
          {:ok, float()} | {:error, term()}
  def ping(address, port, timeout \\ 2_000) do
    started = System.monotonic_time(:microsecond)

    case :gen_tcp.connect(address(address), port, [:binary, active: false], timeout) do
      {:ok, socket} ->
        elapsed = (System.monotonic_time(:microsecond) - started) / 1000
        :gen_tcp.close(socket)
        {:ok, elapsed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl GenServer
  def init({:listen, world, opts}) do
    case :gen_tcp.listen(Keyword.get(opts, :port, 0), [
           :binary,
           packet: 4,
           active: false,
           reuseaddr: true,
           packet_size: @max_frame
         ]) do
      {:ok, socket} ->
        listener = self()
        acceptor = spawn_link(fn -> accept(socket, world, listener) end)
        {:ok, %{socket: socket, acceptor: acceptor, accepted: %{}}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  def init({:connect, address, port, timeout}) do
    case :gen_tcp.connect(
           address,
           port,
           [:binary, packet: 4, active: :once, packet_size: @max_frame],
           timeout
         ) do
      {:ok, socket} ->
        {:ok, %{socket: socket, side: :guest, world: nil, calls: %{}, next: 0, monitor: nil}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  def init({:accepted, socket, world}) do
    {:ok, %{socket: socket, side: :host, world: world, calls: %{}, next: 0, monitor: nil}}
  end

  defp accept(socket, world, listener) do
    case :gen_tcp.accept(socket) do
      {:ok, client} ->
        {:ok, link} = GenServer.start(__MODULE__, {:accepted, client, world})
        :gen_tcp.controlling_process(client, link)
        send(link, :owned)
        send(listener, {:accepted, link})
        accept(socket, world, listener)

      {:error, :closed} ->
        :ok

      {:error, _reason} ->
        accept(socket, world, listener)
    end
  end

  @impl GenServer
  def handle_call(:port, _from, %{socket: socket} = state) do
    {:ok, port} = :inet.port(socket)
    {:reply, port, state}
  end

  def handle_call(:drop, _from, %{accepted: accepted} = state) do
    Enum.each(Map.keys(accepted), &stop_link/1)
    {:reply, :ok, state}
  end

  def handle_call(request, from, %{side: :guest} = state) do
    case outgoing_call(request) do
      {:ok, wire} ->
        ref = state.next
        transmit(state, {:call, ref, wire})
        state = %{state | calls: Map.put(state.calls, ref, from), next: ref + 1}
        {:noreply, following(state, request)}

      :error ->
        {:reply, {:error, :not_carried}, state}
    end
  end

  @impl GenServer
  def handle_info({:accepted, link}, %{accepted: accepted} = state),
    do: {:noreply, %{state | accepted: Map.put(accepted, link, Process.monitor(link))}}

  def handle_info({:DOWN, _monitor, :process, link, _reason}, %{accepted: accepted} = state)
      when is_map_key(accepted, link),
      do: {:noreply, %{state | accepted: Map.delete(accepted, link)}}

  def handle_info(:owned, %{socket: socket} = state) do
    :inet.setopts(socket, active: :once)
    {:noreply, state}
  end

  def handle_info({:tcp, socket, data}, %{socket: socket} = state) do
    :inet.setopts(socket, active: :once)

    with {:ok, message} <- decoded(data),
         {:ok, state} <- received(message, state) do
      {:noreply, state}
    else
      _bad -> {:stop, :normal, state}
    end
  end

  def handle_info({:tcp_closed, socket}, %{socket: socket} = state), do: {:stop, :normal, state}

  def handle_info({:tcp_error, socket, _reason}, %{socket: socket} = state),
    do: {:stop, :normal, state}

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, %{monitor: monitor} = state),
    do: {:stop, :normal, state}

  def handle_info(message, state) do
    case outgoing(message) do
      {:ok, wire} -> transmit(state, {:send, wire})
      :error -> :ok
    end

    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, %{socket: socket}), do: :gen_tcp.close(socket)

  defp received({:send, wire}, %{world: world} = state) when world != nil do
    case incoming(wire) do
      {:ok, message} ->
        send(world, message)
        {:ok, state}

      :error ->
        :error
    end
  end

  defp received({:call, ref, wire}, %{side: :host, world: world} = state) when is_integer(ref) do
    case incoming_call(wire) do
      {:ok, request} ->
        reply = GenServer.call(world, request, @call_timeout)
        transmit(state, {:reply, ref, outgoing_reply(reply)})
        {:ok, watched(state, request)}

      :error ->
        :error
    end
  catch
    :exit, _reason -> :error
  end

  defp received({:reply, ref, wire}, %{side: :guest} = state) when is_map_key(state.calls, ref) do
    {from, calls} = Map.pop(state.calls, ref)
    GenServer.reply(from, incoming_reply(wire))
    {:ok, %{state | calls: calls}}
  end

  defp received({:send, wire}, %{side: :guest, world: nil} = state) do
    case incoming(wire) do
      {:ok, _message} -> {:ok, state}
      :error -> :error
    end
  end

  defp received(_message, _state), do: :error

  defp following(%{world: nil} = state, {:rollback, world, _opts}),
    do: %{state | world: world, monitor: Process.monitor(world)}

  defp following(state, _request), do: state

  defp watched(%{side: :host, monitor: nil} = state, {:rollback, _link, _opts}),
    do: %{state | monitor: Process.monitor(state.world)}

  defp watched(state, _request), do: state

  defp transmit(%{socket: socket}, term), do: :gen_tcp.send(socket, :erlang.term_to_binary(term))

  defp stop_link(link) do
    GenServer.stop(link, :normal)
  catch
    :exit, _reason -> :ok
  end

  defp decoded(data) do
    {:ok, :erlang.binary_to_term(data, [:safe])}
  rescue
    ArgumentError -> :error
  end

  defp outgoing({:cauldron_rollback, _pid, actions, through, frame}),
    do: {:ok, {:rollback, actions, through, frame}}

  defp outgoing({:cauldron_rollback_lead, _pid, average}), do: {:ok, {:lead, average}}
  defp outgoing({:cauldron_rollback_check, _pid, frame, sum}), do: {:ok, {:check, frame, sum}}
  defp outgoing(_message), do: :error

  defp incoming({:rollback, actions, through, frame})
       when is_list(actions) and is_integer(through) and is_integer(frame) do
    if Enum.all?(actions, &action?/1),
      do: {:ok, {:cauldron_rollback, self(), actions, through, frame}},
      else: :error
  end

  defp incoming({:lead, average}) when is_number(average),
    do: {:ok, {:cauldron_rollback_lead, self(), average}}

  defp incoming({:check, frame, sum}) when is_integer(frame),
    do: {:ok, {:cauldron_rollback_check, self(), frame, sum}}

  defp incoming(_wire), do: :error

  defp action?({frame, {:join, _id, props}}) when is_integer(frame) and is_map(props), do: true
  defp action?({frame, {:leave, _id}}) when is_integer(frame), do: true
  defp action?({frame, {:input, _id, _input}}) when is_integer(frame), do: true
  defp action?(_action), do: false

  defp outgoing_call(:hz), do: {:ok, :hz}
  defp outgoing_call({:rollback, _pid, opts}) when is_list(opts), do: {:ok, {:rollback, opts}}

  defp outgoing_call({:join, id, props, _pid, _frames?}) when is_map(props),
    do: {:ok, {:join, id, props}}

  defp outgoing_call({:leave, id}), do: {:ok, {:leave, id}}
  defp outgoing_call(_request), do: :error

  defp incoming_call(:hz), do: {:ok, :hz}

  defp incoming_call({:rollback, opts}) when is_list(opts) do
    opts = Keyword.take(opts, [:delay, :window])

    if Enum.all?(opts, fn {_key, value} -> is_integer(value) and value >= 0 and value <= 60 end),
      do: {:ok, {:rollback, self(), opts}},
      else: :error
  end

  defp incoming_call({:join, id, props}) when is_map(props),
    do: {:ok, {:join, id, props, self(), false}}

  defp incoming_call({:leave, id}), do: {:ok, {:leave, id}}
  defp incoming_call(_wire), do: :error

  defp outgoing_reply({pid, %{hz: hz, start: start}}) when is_pid(pid),
    do: {:started, hz, start}

  defp outgoing_reply(reply), do: {:reply, reply}

  defp incoming_reply({:started, hz, start}), do: {self(), %{hz: hz, start: start}}
  defp incoming_reply({:reply, reply}), do: reply
  defp incoming_reply(_wire), do: {:error, :bad_reply}

  defp address(address) when is_tuple(address), do: address

  defp address(address) when is_binary(address) do
    case :inet.parse_address(String.to_charlist(address)) do
      {:ok, parsed} -> parsed
      {:error, _reason} -> String.to_charlist(address)
    end
  end
end
