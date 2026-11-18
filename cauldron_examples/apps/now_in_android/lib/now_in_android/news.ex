defmodule NowInAndroid.News do
  @moduledoc """
  The news resources the app has, kept in one process and saved to a DETS file beside the
  user's data: `NowInAndroid.Content.seed/0` at first, then whatever the news server adds
  (`merge/1`).
  """

  use GenServer

  alias NowInAndroid.Content

  @doc "Start the store, registered under its module's name."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Every news resource, newest first."
  @spec all() :: [map()]
  def all, do: GenServer.call(__MODULE__, :all)

  @doc "The news resource with `id`, or `nil`."
  @spec get(String.t()) :: map() | nil
  def get(id), do: Enum.find(all(), &(&1.id == id))

  @doc "Add `resources` (the server's, decoded with `Content.resource/1`); the ones that were new."
  @spec merge([map()]) :: [map()]
  def merge(resources), do: GenServer.call(__MODULE__, {:merge, resources})

  @impl GenServer
  def init(opts) do
    file = Keyword.get_lazy(opts, :file, &default_file/0)
    File.mkdir_p!(Path.dirname(file))
    {:ok, table} = :dets.open_file(__MODULE__, file: String.to_charlist(file))

    news =
      case :dets.lookup(table, :news) do
        [{:news, news}] -> news
        [] -> Content.seed()
      end

    {:ok, %{table: table, news: news}}
  end

  @impl GenServer
  def handle_call(:all, _from, state), do: {:reply, state.news, state}

  def handle_call({:merge, resources}, _from, state) do
    known = MapSet.new(state.news, & &1.id)
    added = Enum.reject(resources, &MapSet.member?(known, &1.id))
    news = Content.newest_first(added ++ state.news)
    :ok = :dets.insert(state.table, {:news, news})
    :ok = :dets.sync(state.table)
    {:reply, added, %{state | news: news}}
  end

  @impl GenServer
  def terminate(_reason, state), do: :dets.close(state.table)

  defp default_file do
    folder =
      System.get_env("CAULDRON_NATIVE_DATA") || Path.join(System.user_home!(), ".now_in_android")

    Path.join(folder, "news.dets")
  end
end
