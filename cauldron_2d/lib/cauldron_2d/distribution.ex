defmodule Cauldron2D.Distribution do
  @moduledoc """
  Play across machines over BEAM distribution: one machine hosts, the other joins its
  worlds (`Cauldron2D.Worlds.world_name/2`).

      {:ok, host} = Cauldron2D.Distribution.host("nidhox", game: "NidhOX")
      host.address
      host.code

      {:ok, node} = Cauldron2D.Distribution.join("nidhox", "192.168.1.5", "K7QMW2ZD")

  `host/2` names this VM `<name>@cauldron.host`, a name tied to none of the machine's
  addresses, gives it a fresh join code (`code_length/0` characters of `alphabet/0`) as
  its cookie, and calls on the local network (`Cauldron2D.Beacon`) with the node's name
  and `address`, this machine's first address (`addresses/0`). The code never goes over
  the air: the host shows it, and whoever joins types it.

  `join/3` names this VM too when it is not yet distributed, at this machine's address on
  the host's network (`address_toward/1`), points the host's name at
  the address given, in this VM's own host table (looked up before the system's), and
  connects to the host's node with the code as the cookie for that node alone. Any of
  the host's addresses joins it — its home network's, a VPN's, or `127.0.0.1` from the
  same machine.

  Rules a caller must respect:

    * a connected node can run any code in this VM, so the join code is to be shown
      only to the player joining, and a host stopped (`stop/1`) once play is over
    * distribution traffic is not encrypted; play across the internet needs the host's
      ports `4369` (the node name service) and the `:port` given to `host/2` open to
      the joining machine; without `:port` the host listens on any free port
    * a VM that is already distributed hosts under its own name, with its cookie as
      the code, and `stop/1` leaves its distribution running
    * a node needs the node name service (`epmd`) on its own machine; when none answers
      it is started the way `erl -sname` starts it: `epmd -daemon` on Unix, and on
      Windows through a short-lived `erl -sname`, whose launcher starts it as a
      detached process. It outlives this VM and its console, and starting it while one
      already runs changes nothing
  """

  alias Cauldron2D.Beacon

  @alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  @code_length 8
  @host_name "cauldron.host"
  @lookup_ms 5_000
  @name_service_waits 40
  @name_service_wait_ms 50

  @type host :: %{
          node: node(),
          address: String.t(),
          code: String.t(),
          beacon: pid(),
          started?: boolean()
        }

  @doc "The characters a join code is made of."
  @spec alphabet() :: charlist()
  def alphabet, do: @alphabet

  @doc "How many characters a join code has."
  @spec code_length() :: pos_integer()
  def code_length, do: @code_length

  @doc """
  Host as `name`: this VM distributed as `<name>@cauldron.host` with a fresh join code, and
  calling on the local network as `:game` (default `name`). `:port` is the port other
  nodes connect on (default any free port). The beacon is linked to the caller.
  """
  @spec host(String.t(), keyword()) :: {:ok, host()} | {:error, term()}
  def host(name, opts \\ []) do
    with {:ok, address} <- address(),
         {:ok, node, started?} <- distribute(name, @host_name, Keyword.get(opts, :port)) do
      code = if started?, do: code(), else: Atom.to_string(Node.get_cookie())
      if started?, do: Node.set_cookie(String.to_atom(code))

      {:ok, beacon} =
        Beacon.start_link(game: Keyword.get(opts, :game, name), host: address, node: node)

      {:ok, %{node: node, address: address, code: code, beacon: beacon, started?: started?}}
    end
  end

  @doc "Stop hosting: no more calls on the network, and the distribution `host/2` started stopped."
  @spec stop(host()) :: :ok
  def stop(%{beacon: beacon, started?: started?}) do
    if Process.alive?(beacon), do: GenServer.stop(beacon)
    if started?, do: Node.stop()
    :ok
  end

  @doc """
  Join the node `<name>@<address>` with join code `code`: `{:ok, node}` once connected,
  else why not —

    * `{:error, :bad_address}` — `address` is not an IPv4 address
    * `{:error, :unreachable}` — nothing answers at `address` (its port 4369, where
      nodes are looked up, is closed or blocked)
    * `{:error, :not_hosting}` — the machine answers, but no node `name` runs there
    * `{:error, :refused}` — the node runs, but the connection fails: the code is not
      its code, or its own port is blocked
    * `{:error, :no_network}` and `Node.start/2`'s errors — this machine cannot be a node
  """
  @spec join(String.t(), String.t(), String.t()) :: {:ok, node()} | {:error, term()}
  def join(name, address, code) do
    node = :"#{name}@#{@host_name}"

    with {:ok, ip} <- parse_address(address),
         :ok <- running(name, ip),
         :ok <- point_host_at(ip),
         {:ok, own} <- address_toward(ip),
         {:ok, _node, _started?} <-
           distribute("#{name}_#{System.unique_integer([:positive])}", own, nil) do
      Node.set_cookie(node, String.to_atom(code))
      if Node.connect(node) == true, do: {:ok, node}, else: {:error, :refused}
    end
  end

  defp point_host_at(ip) do
    :ok = :inet_db.set_lookup([:file | :inet_db.res_option(:lookup) -- [:file]])
    :ok = :inet_db.del_host(ip)
    :ok = :inet_db.add_host(ip, [String.to_charlist(@host_name)])
  end

  defp parse_address(address) do
    case :inet.parse_ipv4strict_address(String.to_charlist(address)) do
      {:ok, ip} -> {:ok, ip}
      {:error, _reason} -> {:error, :bad_address}
    end
  end

  defp running(name, ip) do
    case :erl_epmd.port_please(String.to_charlist(name), ip, @lookup_ms) do
      {:port, _port, _version} -> :ok
      :noport -> {:error, :not_hosting}
      _closed -> {:error, :unreachable}
    end
  end

  @doc "A fresh join code."
  @spec code() :: String.t()
  def code,
    do:
      for(
        <<byte <- :crypto.strong_rand_bytes(@code_length)>>,
        into: "",
        do: <<Enum.at(@alphabet, rem(byte, length(@alphabet)))>>
      )

  @doc """
  This machine's IPv4 address on its local network, the first of `addresses/0`;
  `{:error, :no_network}` when it has none.
  """
  @spec address() :: {:ok, String.t()} | {:error, :no_network}
  def address do
    case addresses() do
      [address | _others] -> {:ok, address}
      [] -> {:error, :no_network}
    end
  end

  @doc """
  This machine's IPv4 address on the network `peer` is on: the address of an interface
  that is up and whose subnet holds `peer`, else `address/0`.
  """
  @spec address_toward(:inet.ip4_address()) :: {:ok, String.t()} | {:error, :no_network}
  def address_toward(peer) do
    case Enum.find(subnets(), fn {ip, mask} -> same_subnet?(ip, peer, mask) end) do
      {ip, _mask} -> {:ok, ip |> :inet.ntoa() |> to_string()}
      nil -> address()
    end
  end

  defp subnets do
    case :inet.getifaddrs() do
      {:ok, interfaces} -> Enum.flat_map(interfaces, &interface_subnets/1)
      {:error, _reason} -> []
    end
  end

  defp interface_subnets({_name, opts}) do
    if :up in Keyword.get(opts, :flags, []), do: with_masks(opts), else: []
  end

  defp with_masks([{:addr, {_, _, _, _} = ip}, {:netmask, {_, _, _, _} = mask} | rest]),
    do: [{ip, mask} | with_masks(rest)]

  defp with_masks([_other | rest]), do: with_masks(rest)
  defp with_masks([]), do: []

  defp same_subnet?(ip, peer, mask) do
    [ip, peer, mask]
    |> Enum.map(&Tuple.to_list/1)
    |> Enum.zip_with(fn [own, theirs, bits] ->
      Bitwise.band(own, bits) == Bitwise.band(theirs, bits)
    end)
    |> Enum.all?()
  end

  @doc """
  Every IPv4 address of this machine's interfaces that are up, loopback aside: private
  network addresses before others, and within each, those of physical interfaces
  (named `en…`, `eth…` or `wl…`) before virtual ones such as a VPN's or a virtual
  machine's bridge. A machine on several networks is reached at the one its peer shares.
  """
  @spec addresses() :: [String.t()]
  def addresses do
    case :inet.getifaddrs() do
      {:ok, interfaces} ->
        interfaces
        |> Enum.flat_map(&interface_addresses/1)
        |> Enum.sort_by(fn {name, ip} -> {not private?(ip), not physical?(name)} end)
        |> Enum.map(fn {_name, ip} -> ip |> :inet.ntoa() |> to_string() end)

      {:error, _reason} ->
        []
    end
  end

  defp interface_addresses({name, opts}) do
    flags = Keyword.get(opts, :flags, [])

    if :up in flags and :loopback not in flags,
      do: for({:addr, {_, _, _, _} = ip} <- opts, do: {to_string(name), ip}),
      else: []
  end

  defp physical?(name), do: String.starts_with?(name, ["en", "eth", "wl"])

  defp private?({10, _, _, _}), do: true
  defp private?({172, second, _, _}) when second in 16..31, do: true
  defp private?({192, 168, _, _}), do: true
  defp private?(_ip), do: false

  defp distribute(name, address, port) do
    if Node.alive?() do
      {:ok, node(), false}
    else
      start_name_service()
      if port, do: listen_on(port)

      case Node.start(:"#{name}@#{address}", :longnames) do
        {:ok, _pid} -> {:ok, node(), true}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp listen_on(port) do
    Application.put_env(:kernel, :inet_dist_listen_min, port)
    Application.put_env(:kernel, :inet_dist_listen_max, port)
  end

  defp start_name_service do
    with {:error, _reason} <- :erl_epmd.names() do
      launch_name_service(:os.type())
      await_name_service(@name_service_waits)
    end
  end

  defp launch_name_service({:unix, _name}), do: run(epmd(), ["-daemon"])

  defp launch_name_service({:win32, _name}),
    do:
      run(erl(), ["-sname", "cauldron_epmd_#{:os.getpid()}", "-noshell", "-s", "erlang", "halt"])

  defp run(nil, _args), do: :ok

  defp run(path, args) do
    System.cmd(path, args, stderr_to_stdout: true)
    :ok
  end

  defp await_name_service(0), do: :ok

  defp await_name_service(waits) do
    case :erl_epmd.names() do
      {:ok, _names} ->
        :ok

      {:error, _reason} ->
        Process.sleep(@name_service_wait_ms)
        await_name_service(waits - 1)
    end
  end

  defp epmd, do: installed("epmd", ["erts-*", "bin", "epmd"])

  defp erl, do: installed("erl", ["bin", "erl{,.exe}"])

  defp installed(name, under_root) do
    System.find_executable(name) ||
      [:code.root_dir() | under_root]
      |> Path.join()
      |> Path.wildcard()
      |> List.first()
  end
end
