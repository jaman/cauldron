defmodule CauldronNative.LiveActivity do
  @moduledoc """
  Something under way that the user follows outside the app, such as an order being made:
  a Live Activity on iOS (the Lock Screen and the Dynamic Island) and a Live Update on
  Android (an ongoing notification the system promotes, with its progress).

  An activity is `%{title, detail, progress, icon}`: `progress` from 0.0 to 1.0, or `nil`;
  `icon` a name as `CauldronNative.UI.icon/2` takes it, with `ios:` and `android:` names
  of its own (`ios_icon`, `android_icon`). The app's config allows them
  (`live_activities: true`, `CauldronNative.Build.App`).

  Optional keys: `ends_at`, a `DateTime` the activity counts down to in place of its
  progress, with `ends_label` under the time ("Remaining"); `image` and `compact_image`,
  pictures of the app's `:assets` catalog in place of the icon (the compact one in the
  Dynamic Island's compact and minimal views, on a `badge` colour); `background` and
  `tint`, colours of the catalog for the Lock Screen's background and the Dynamic
  Island's text; and `url`, a link the activity opens when tapped
  (`{:cauldron_native, :url, url}` with one of the app's `:url_schemes`). Android shows
  the countdown as the notification's timer and the image as its large icon.

      CauldronNative.LiveActivity.start({:order, 1120}, %{
        title: "Order #1120",
        detail: "Preparing your donuts",
        progress: 0.4,
        ios_icon: "takeoutbag.and.cup.and.straw",
        android_icon: "Fastfood"
      })

  `start/2` is answered as `CauldronNative.Device`'s requests are: `{:device, tag, {:ok,
  :started}}`, or `{:error, :unavailable}` when the user turned them off or the system
  has none. The tag names the activity for `update/2` and `finish/2`.
  """

  alias CauldronNative.Device.Request

  @type activity :: %{
          required(:title) => String.t(),
          required(:detail) => String.t(),
          optional(:progress) => float() | nil,
          optional(:ios_icon) => String.t(),
          optional(:android_icon) => String.t(),
          optional(:ends_at) => DateTime.t(),
          optional(:ends_label) => String.t(),
          optional(:image) => String.t(),
          optional(:compact_image) => String.t(),
          optional(:background) => String.t(),
          optional(:tint) => String.t(),
          optional(:badge) => String.t(),
          optional(:url) => String.t()
        }

  @optional [:ends_label, :image, :compact_image, :background, :tint, :badge, :url]

  @doc "Start an activity named by `tag`."
  @spec start(term(), activity()) :: :ok
  def start(tag, activity), do: Request.send(tag, "activity_start", activity(activity))

  @doc "Change the activity `tag` to `activity`."
  @spec update(term(), activity()) :: :ok
  def update(tag, activity), do: Request.send(tag, "activity_update", activity(activity))

  @doc "End the activity `tag`, showing `activity` as it ends."
  @spec finish(term(), activity()) :: :ok
  def finish(tag, activity), do: Request.send(tag, "activity_finish", activity(activity))

  defp activity(activity) do
    %{
      title: Map.fetch!(activity, :title),
      detail: Map.fetch!(activity, :detail),
      progress: Map.get(activity, :progress),
      ios_icon: Map.get(activity, :ios_icon, "bolt.circle"),
      android_icon: Map.get(activity, :android_icon, "Bolt"),
      ends_at: activity |> Map.get(:ends_at) |> unix()
    }
    |> Map.merge(Map.take(activity, @optional))
  end

  defp unix(nil), do: nil
  defp unix(%DateTime{} = at), do: DateTime.to_unix(at, :millisecond) / 1000
end
