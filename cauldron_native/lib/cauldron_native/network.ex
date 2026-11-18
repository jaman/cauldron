defmodule CauldronNative.Network do
  @moduledoc """
  Keeps Erlang's resolver on the phone's current DNS servers. The platform reports the
  default network's servers as they change (moving from Wi-Fi to mobile data, joining
  another network), and each report replaces the resolver's servers.

  Started by `CauldronNative.Application` inside a mobile app; the report is JSON,
  `{"nameservers": ["192.168.1.1", "fe80::1"]}`.
  """

  use GenServer

  alias CauldronNative.Native

  @doc "Start watching the network, registered under this module's name."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "The addresses in a report, as `:inet` addresses, leaving out any that do not parse."
  @spec nameservers(binary()) :: [:inet.ip_address()]
  def nameservers(json) do
    case JSON.decode(json) do
      {:ok, %{"nameservers" => servers}} when is_list(servers) ->
        for server <- servers,
            {:ok, address} <- [server |> to_charlist() |> :inet.parse_address()],
            do: address

      _invalid ->
        []
    end
  end

  @impl GenServer
  def init(nil) do
    Native.watch_system(self())
    {:ok, nil}
  end

  @impl GenServer
  def handle_info({:cauldron_native, :network, json}, state) do
    use_servers(nameservers(json))
    {:noreply, state}
  end

  defp use_servers([]), do: :ok

  defp use_servers(servers),
    do: :inet_db.res_option(:nameservers, Enum.map(servers, &{&1, 53}))
end
