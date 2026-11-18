defmodule NowInAndroid.Cards do
  @moduledoc """
  The pieces the screens share, laid out as Now in Android lays them out: the news card
  (header picture, title with its bookmark, date and kind, summary, and the chips of its
  topics), a grid of them, and a topic's row with its follow button.
  """

  import CauldronNative.UI

  alias NowInAndroid.Content

  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

  @doc "The news `items` as cards in a grid of as many columns as fit."
  @spec feed([map()], map()) :: CauldronNative.UI.Node.t()
  def feed(items, user),
    do: grid(Enum.map(items, &news(&1, user)), min_width: 340, spacing: 16)

  @doc "One news resource's card; tapping it opens the resource."
  @spec news(map(), map()) :: CauldronNative.UI.Node.t()
  def news(item, user) do
    saved? = MapSet.member?(user.saved, item.id)
    unread = if MapSet.member?(user.viewed, item.id), do: "", else: "● "

    card(
      [
        image(item.image,
          fit: :fill,
          modifiers: [frame: [max_width: :infinity, height: 168], corner_radius: 12]
        ),
        hstack(
          [
            text(item.title, modifiers: [font: :title3, bold: true]),
            spacer(),
            bookmark(item.id, saved?)
          ],
          alignment: :top
        ),
        text("#{unread}#{date(DateTime.to_date(item.published))} • #{item.type}",
          modifiers: [font: :footnote, foreground: :secondary]
        ),
        text(item.content, modifiers: [font: :body]),
        scroll([hstack(Enum.map(item.topics, &topic_chip(&1, user)), spacing: 8)],
          axis: :horizontal
        )
      ],
      id: item.id,
      on_tap: {:open, item.id},
      label: item.title,
      hint: "open the article"
    )
  end

  @doc "A topic's row: its icon, name and line, and the button that follows it."
  @spec topic_row(map(), map()) :: CauldronNative.UI.Node.t()
  def topic_row(topic, user) do
    hstack(
      [
        icon(:star,
          ios: topic.ios_icon,
          android: topic.android_icon,
          modifiers: [foreground: :accent, frame: [width: 32]]
        ),
        vstack(
          [
            text(topic.name, modifiers: [font: :headline]),
            text(topic.short, modifiers: [font: :footnote, foreground: :secondary])
          ],
          alignment: :leading,
          spacing: 2
        ),
        spacer(),
        follow(topic, user)
      ],
      spacing: 16,
      id: topic.id,
      on_tap: {:topic, topic.id},
      label: topic.name,
      hint: "show the topic"
    )
  end

  @doc "The icon button that follows `topic`, or stops following it."
  @spec follow(map(), map()) :: CauldronNative.UI.Node.t()
  def follow(topic, user) do
    if MapSet.member?(user.followed, topic.id) do
      button("Unfollow #{topic.name}",
        style: :icon,
        icon: :check_circle,
        ios: "checkmark.circle.fill",
        android: "CheckCircle",
        on_tap: {:follow, topic.id}
      )
    else
      button("Follow #{topic.name}",
        style: :icon,
        icon: :add_circle,
        ios: "plus.circle",
        android: "AddCircleOutline",
        on_tap: {:follow, topic.id}
      )
    end
  end

  @doc "A date as \"Oct 22, 2026\"."
  @spec date(Date.t()) :: String.t()
  def date(%Date{} = day), do: "#{Enum.at(@months, day.month - 1)} #{day.day}, #{day.year}"

  defp bookmark(id, true),
    do:
      button("Remove from saved",
        style: :icon,
        icon: :favorite,
        ios: "bookmark.fill",
        android: "Bookmark",
        on_tap: {:save, id}
      )

  defp bookmark(id, false),
    do:
      button("Save",
        style: :icon,
        icon: :favorite_border,
        ios: "bookmark",
        android: "BookmarkBorder",
        on_tap: {:save, id}
      )

  defp topic_chip(id, user) do
    topic = Content.topic(id)

    chip(String.upcase(topic.name),
      id: id,
      selected: MapSet.member?(user.followed, id),
      on_tap: {:topic, id}
    )
  end
end
