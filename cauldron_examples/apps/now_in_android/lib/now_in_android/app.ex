defmodule NowInAndroid.App do
  @moduledoc """
  Now in Android, after Google's Jetpack Compose sample of the same name: news for
  Android developers, chosen by the topics the user follows.

  Three places, For You, Saved and Interests, sit in the navigation bar (a rail or drawer
  on a wide Android screen, a tab bar or sidebar on an iPad). Each is a stack of screens:
  a topic opens from a chip or a row, and Search from the top bar. The settings choose the
  theme, Android's Dynamic colour and dark mode, applied to the whole app.

  The news syncs from the news server (`NowInAndroid.Sync`) when the app comes to the
  front and when the system wakes it for a background refresh, and new resources in the
  followed topics arrive as notifications that open them. Links open the app at a
  resource or a topic: `nowinandroid://news/<id>`, `nowinandroid://topic/<id>`.

  Launched with `NOW_IN_ANDROID_OPEN` set to `saved`, `interests`, `search`, `settings` or
  `topic:<id>`, the app opens there.
  """

  use CauldronNative.App

  alias CauldronNative.{Background, Device}
  alias NowInAndroid.{News, Screens, Store, Sync}

  @android_green "#1B6B3A"

  @impl true
  def mount(_params) do
    state = %{
      tab: :for_you,
      pushed: [],
      query: "",
      settings: false,
      offline: false,
      user: Store.user()
    }

    if Device.system(), do: start_syncing(state.user)
    opened(state, System.get_env("NOW_IN_ANDROID_OPEN"))
  end

  @impl true
  def handle_info({:cauldron_native, :lifecycle, :active}, state) do
    sync(state.user, false)
    state
  end

  def handle_info({:cauldron_native, :background, :refresh}, state) do
    sync(state.user, true)
    state
  end

  def handle_info({:synced, result, background?}, state) do
    if background?, do: Background.done()
    %{state | offline: match?({:error, _reason}, result)}
  end

  def handle_info({:cauldron_native, :url, link}, state), do: linked(state, URI.parse(link))
  def handle_info({:device, {:news, id}, {:ok, :opened}}, state), do: open(id, state)
  def handle_info(_message, state), do: state

  @impl true
  def render(state) do
    theme(
      [
        tabs(
          [
            tab("For you", [stack(state, :for_you, Screens.for_you(state.user, state.offline))],
              id: :for_you,
              icon: :home,
              ios: "newspaper",
              android: "Upcoming"
            ),
            tab("Saved", [stack(state, :saved, Screens.saved(state.user))],
              id: :saved,
              icon: :favorite,
              ios: "bookmark",
              android: "Bookmarks"
            ),
            tab("Interests", [stack(state, :interests, Screens.interests(state.user))],
              id: :interests,
              icon: :list,
              ios: "number",
              android: "Grid3x3"
            )
          ],
          selected: state.tab,
          on_select: :tab
        ),
        dialog("Settings", Screens.settings(state.user), [button("OK", on_tap: :settings_closed)],
          shown: state.settings,
          on_dismiss: :settings_closed
        )
      ],
      scheme: state.user.dark,
      dynamic_color: state.user.brand == :default and state.user.dynamic_color,
      accent: if(state.user.brand == :android, do: @android_green)
    )
  end

  @impl true
  def handle_event(:tab, tab, state), do: %{state | tab: tab, pushed: []}
  def handle_event(:back, keep, state), do: %{state | pushed: Enum.take(state.pushed, keep - 1)}
  def handle_event(:search, _value, state), do: %{state | pushed: state.pushed ++ [:search]}
  def handle_event(:query, text, state), do: %{state | query: text}
  def handle_event(:settings, _value, state), do: %{state | settings: true}
  def handle_event(:settings_closed, _value, state), do: %{state | settings: false}

  def handle_event({:topic, id}, _value, state),
    do: remembered(%{state | pushed: state.pushed ++ [{:topic, id}]})

  def handle_event({:recent, text}, _value, state), do: %{state | query: text}
  def handle_event(:clear_searches, _value, state), do: %{state | user: Store.clear_searches()}
  def handle_event({:follow, id}, _value, state), do: %{state | user: Store.toggle_follow(id)}
  def handle_event({:save, id}, _value, state), do: %{state | user: Store.toggle_saved(id)}
  def handle_event(:onboarded, _value, state), do: %{state | user: Store.finish_onboarding()}
  def handle_event({:setting, key}, value, state), do: %{state | user: Store.set(key, value)}

  def handle_event({:open, id}, _value, state), do: remembered(open(id, state))

  defp open(id, state) do
    with %{url: url} <- News.get(id), do: Device.open_url(url)
    %{state | user: Store.read(id)}
  end

  defp start_syncing(user) do
    Device.permission(:notifications_asked, :notifications)
    Background.schedule(:refresh, 15)
    sync(user, false)
  end

  defp sync(user, background?) do
    runtime = self()

    Task.Supervisor.start_child(NowInAndroid.Tasks, fn ->
      send(runtime, {:synced, Sync.run(user.followed), background?})
    end)
  end

  defp linked(state, %URI{scheme: "nowinandroid", host: "news", path: "/" <> id}),
    do: open(id, %{state | tab: :for_you, pushed: []})

  defp linked(state, %URI{scheme: "nowinandroid", host: "topic", path: "/" <> id}),
    do: %{state | tab: :interests, pushed: [{:topic, id}]}

  defp linked(state, _other), do: state

  defp remembered(%{query: query, pushed: pushed} = state) do
    if :search in pushed and String.trim(query) != "",
      do: %{state | user: Store.searched(String.trim(query))},
      else: state
  end

  defp stack(%{tab: tab} = state, tab, main),
    do: navigation([main | Enum.map(state.pushed, &pushed(&1, state))], on_back: :back)

  defp stack(_state, _tab, main), do: navigation([main], on_back: :back)

  defp pushed(:search, state), do: Screens.search(state.query, state.user)
  defp pushed({:topic, id}, state), do: Screens.topic(id, state.user)

  defp opened(state, "topic:" <> id), do: %{state | tab: :interests, pushed: [{:topic, id}]}
  defp opened(state, "search"), do: %{state | pushed: [:search]}
  defp opened(state, "settings"), do: %{state | settings: true}

  defp opened(state, tab) when tab in ~w(saved interests),
    do: %{state | tab: String.to_existing_atom(tab)}

  defp opened(state, _nothing), do: state
end
