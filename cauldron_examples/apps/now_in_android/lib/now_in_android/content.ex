defmodule NowInAndroid.Content do
  @moduledoc """
  Now in Android's content: the topics and news resources of Google's sample
  (`priv/data`, Apache 2.0), as maps the screens read.

  A topic is `%{id, name, short, long, ios_icon, android_icon}`; a news resource is
  `%{id, title, content, url, image, published, type, topics}`, `published` a
  `DateTime` and `topics` topic ids. The app starts with every resource but the newest
  ten (`seed/0`); the rest arrive from the news server (`NowInAndroid.Sync`).
  """

  @data Path.expand("../../priv/data", __DIR__)
  @external_resource Path.join(@data, "topics.json")
  @external_resource Path.join(@data, "news.json")

  @icons %{
    "1" => {"newspaper", "Newspaper"},
    "2" => {"paintbrush", "Brush"},
    "3" => {"square.stack.3d.up", "Layers"},
    "4" => {"building.columns", "AccountBalance"},
    "5" => {"hammer", "Build"},
    "6" => {"checkmark.seal", "Verified"},
    "7" => {"gauge.high", "Speed"},
    "8" => {"shippingbox", "NewReleases"},
    "9" => {"externaldrive", "Storage"},
    "10" => {"chevron.left.forwardslash.chevron.right", "Code"},
    "11" => {"lock.shield", "Security"},
    "12" => {"paperplane", "Publish"},
    "13" => {"sparkles", "AutoAwesome"},
    "14" => {"accessibility", "Accessibility"},
    "15" => {"car", "DirectionsCar"},
    "16" => {"tv", "Tv"},
    "17" => {"gamecontroller", "SportsEsports"},
    "18" => {"camera", "PhotoCamera"},
    "19" => {"applewatch", "Watch"}
  }

  @topics @data |> Path.join("topics.json") |> File.read!() |> JSON.decode!()
  @news @data |> Path.join("news.json") |> File.read!() |> JSON.decode!()
  @held_back 10

  @doc "Every topic, in the sample's order."
  @spec topics() :: [map()]
  def topics do
    for topic <- @topics do
      {ios, android} = Map.get(@icons, topic["id"], {"tag", "Tag"})

      %{
        id: topic["id"],
        name: topic["name"],
        short: blank(topic["shortDescription"], topic["name"]),
        long: blank(topic["longDescription"], ""),
        ios_icon: ios,
        android_icon: android
      }
    end
  end

  @doc "The topic with `id`, or `nil`."
  @spec topic(String.t()) :: map() | nil
  def topic(id), do: Enum.find(topics(), &(&1.id == id))

  @doc "The news resources the app starts with, newest first."
  @spec seed() :: [map()]
  def seed, do: @news |> Enum.map(&resource/1) |> newest_first() |> Enum.drop(@held_back)

  @doc "A news resource from the server's JSON, which is the sample's."
  @spec resource(map()) :: map()
  def resource(json) do
    {:ok, published, _offset} = DateTime.from_iso8601(json["publishDate"])

    %{
      id: json["id"],
      title: json["title"],
      content: json["content"],
      url: json["url"],
      image: json["headerImageUrl"],
      published: published,
      type: json["type"] |> String.replace(~r/[^\p{L}\p{N} &-]/u, "") |> String.trim(),
      topics: json["topics"]
    }
  end

  @doc "`resources` newest first."
  @spec newest_first([map()]) :: [map()]
  def newest_first(resources), do: Enum.sort_by(resources, & &1.published, {:desc, DateTime})

  defp blank(text, otherwise) when text in [nil, ""], do: otherwise
  defp blank(text, _otherwise), do: text
end
