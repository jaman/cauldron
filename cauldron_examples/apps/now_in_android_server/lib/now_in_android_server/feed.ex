defmodule NowInAndroidServer.Feed do
  @moduledoc """
  The news the server has published: Now in Android's resources oldest first, all but
  the newest ten at start, and one more each `publish_every` seconds until all are out,
  as a backend whose writers keep publishing.
  """

  use GenServer

  @held_back 10

  @doc "Start the feed from the JSON in the `:data` folder, registered under its module's name."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "The published resources, as the sample's JSON maps, newest first."
  @spec published() :: [map()]
  def published, do: GenServer.call(__MODULE__, :published)

  @doc "The topics, as the sample's JSON maps."
  @spec topics() :: [map()]
  def topics, do: GenServer.call(__MODULE__, :topics)

  @impl GenServer
  def init(opts) do
    data = Keyword.fetch!(opts, :data)

    news =
      data
      |> Path.join("news.json")
      |> File.read!()
      |> JSON.decode!()
      |> Enum.sort_by(& &1["publishDate"])

    topics = data |> Path.join("topics.json") |> File.read!() |> JSON.decode!()
    every = Keyword.fetch!(opts, :publish_every) * 1000
    :timer.send_interval(every, :publish)
    {:ok, %{news: news, topics: topics, count: max(length(news) - @held_back, 0)}}
  end

  @impl GenServer
  def handle_call(:published, _from, state),
    do: {:reply, state.news |> Enum.take(state.count) |> Enum.reverse(), state}

  def handle_call(:topics, _from, state), do: {:reply, state.topics, state}

  @impl GenServer
  def handle_info(:publish, state),
    do: {:noreply, %{state | count: min(state.count + 1, length(state.news))}}
end
