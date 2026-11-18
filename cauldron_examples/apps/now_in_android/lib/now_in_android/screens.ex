defmodule NowInAndroid.Screens do
  @moduledoc """
  Now in Android's screens: For You (the topic picker until the user has chosen, then the
  feed of the topics they follow), Saved, Interests, a topic's own screen, Search, and
  the settings.
  """

  import CauldronNative.UI

  alias NowInAndroid.{Cards, Content, News}

  @doc """
  For You: the topic picker while the user is choosing, then their feed, under a notice
  while the news server cannot be reached (`offline?`).
  """
  @spec for_you(map(), boolean()) :: CauldronNative.UI.Node.t()
  def for_you(user, offline?) do
    items = Enum.filter(News.all(), &followed?(&1, user))

    main("Now in Android", [
      if(offline?,
        do:
          label("You aren't connected to the news server",
            icon: :warning,
            ios: "wifi.exclamationmark",
            android: "CloudOff",
            modifiers: [foreground: :destructive]
          )
      ),
      unless(user.onboarded, do: onboarding(user)),
      if(items == [] and user.onboarded,
        do: empty("Nothing here yet", "Follow some topics in Interests to fill your feed.")
      ),
      Cards.feed(items, user)
    ])
  end

  @doc "Saved: the news the user bookmarked."
  @spec saved(map()) :: CauldronNative.UI.Node.t()
  def saved(user) do
    items = Enum.filter(News.all(), &MapSet.member?(user.saved, &1.id))

    main("Saved", [
      if(items == [],
        do: empty("No saved updates", "Updates you save will be stored here to read later.")
      ),
      Cards.feed(items, user)
    ])
  end

  @doc "Interests: every topic, with its follow button."
  @spec interests(map()) :: CauldronNative.UI.Node.t()
  def interests(user) do
    screen("Interests", [
      list(Enum.map(Content.topics(), &Cards.topic_row(&1, user))),
      bar()
    ])
  end

  @doc "The topic with `id`: what it covers, its follow button, and its news."
  @spec topic(String.t(), map()) :: CauldronNative.UI.Node.t()
  def topic(id, user) do
    topic = Content.topic(id)
    following? = MapSet.member?(user.followed, id)

    screen(topic.name, [
      scroll([
        vstack(
          [
            icon(:star,
              ios: topic.ios_icon,
              android: topic.android_icon,
              modifiers: [font: :large_title, foreground: :accent]
            ),
            text(topic.long, modifiers: [font: :body]),
            button(if(following?, do: "Following", else: "Follow"),
              style: if(following?, do: :bordered, else: :prominent),
              icon: if(following?, do: :check, else: :add),
              on_tap: {:follow, id}
            ),
            Cards.feed(Enum.filter(News.all(), &(id in &1.topics)), user)
          ],
          alignment: :leading,
          spacing: 16,
          modifiers: [padding: 16]
        )
      ])
    ])
  end

  @doc "Search: recent searches while the field is empty, then the topics and news that match."
  @spec search(String.t(), map()) :: CauldronNative.UI.Node.t()
  def search(query, user) do
    screen("Search", search_results(String.trim(query), user),
      search: query,
      on_search: :query,
      search_prompt: "Search for topics or updates",
      large_title: false
    )
  end

  @doc "The settings' sections: the theme, Dynamic colour on Android, dark mode, and the app's links."
  @spec settings(map()) :: [CauldronNative.UI.child()]
  def settings(user) do
    [
      section("Theme", [
        picker("", [default: "Default", android: "Android"],
          label: "Theme",
          value: user.brand,
          style: :inline,
          on_change: {:setting, :brand}
        )
      ]),
      if(user.brand == :default and CauldronNative.Device.system() == :android,
        do:
          section("Use Dynamic Color", [
            picker("", [{true, "Yes"}, {false, "No"}],
              label: "Dynamic Color",
              value: user.dynamic_color,
              style: :inline,
              on_change: {:setting, :dynamic_color}
            )
          ])
      ),
      section("Dark mode preference", [
        picker("", [system: "System default", light: "Light", dark: "Dark"],
          label: "Dark mode",
          value: user.dark,
          style: :inline,
          on_change: {:setting, :dark}
        )
      ]),
      section("About", [
        link("Privacy policy", "https://policies.google.com/privacy"),
        link("Licenses", "https://github.com/android/nowinandroid/blob/main/LICENSE"),
        link(
          "Brand guidelines",
          "https://developer.android.com/distribute/marketing-tools/brand-guidelines"
        )
      ])
    ]
  end

  defp search_results("", user) do
    [
      list([
        section(
          "Recent searches",
          for(
            text <- user.searches,
            do: label(text, icon: :refresh, id: text, on_tap: {:recent, text})
          )
        ),
        if(user.searches != [],
          do: section(nil, [button("Clear searches", on_tap: :clear_searches)])
        )
      ])
    ]
  end

  defp search_results(query, user) do
    wanted = String.downcase(query)
    topics = Enum.filter(Content.topics(), &String.contains?(String.downcase(&1.name), wanted))
    items = Enum.filter(News.all(), &matches?(&1, wanted))

    [
      scroll([
        vstack(
          [
            if(topics != [], do: text("Topics", modifiers: [font: :headline])),
            Enum.map(topics, &Cards.topic_row(&1, user)),
            if(items != [], do: text("Updates", modifiers: [font: :headline])),
            Cards.feed(items, user),
            if(topics == [] and items == [],
              do: empty("No results", "Nothing matches “#{query}”.")
            )
          ],
          alignment: :leading,
          spacing: 16,
          modifiers: [padding: 16]
        )
      ])
    ]
  end

  defp onboarding(user) do
    card([
      text("What are you interested in?", modifiers: [font: :title2, bold: true]),
      text("Updates from topics you follow will appear here. Follow some things to get started.",
        modifiers: [foreground: :secondary]
      ),
      grid(
        for topic <- Content.topics() do
          chip(topic.name,
            id: topic.id,
            selected: MapSet.member?(user.followed, topic.id),
            on_tap: {:follow, topic.id}
          )
        end,
        min_width: 150,
        spacing: 8
      ),
      button("Done",
        style: :prominent,
        on_tap: :onboarded,
        disabled: MapSet.size(user.followed) == 0
      )
    ])
  end

  defp main(title, content) do
    screen(title, [
      scroll([vstack(content, spacing: 16, modifiers: [padding: 16])]),
      bar()
    ])
  end

  defp bar do
    toolbar([
      button("Search", icon: :search, on_tap: :search),
      button("Settings", icon: :settings, on_tap: :settings)
    ])
  end

  defp empty(title, line) do
    vstack(
      [
        text(title, modifiers: [font: :title3, bold: true]),
        text(line, modifiers: [foreground: :secondary])
      ],
      spacing: 6,
      modifiers: [padding: [vertical: 48], frame: [max_width: :infinity]]
    )
  end

  defp followed?(item, user), do: Enum.any?(item.topics, &MapSet.member?(user.followed, &1))

  defp matches?(item, wanted),
    do:
      String.contains?(String.downcase(item.title), wanted) or
        String.contains?(String.downcase(item.content), wanted)
end
