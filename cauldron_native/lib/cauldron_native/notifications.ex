defmodule CauldronNative.Notifications do
  @moduledoc """
  Notifications: the app's own, shown now or at a time, and push notifications sent by
  the app's server through Apple's push service (APNs) or Firebase Cloud Messaging.

  Showing a notification needs the `:notifications` permission
  (`CauldronNative.Device.permission/2` asks for it); without it `schedule/4` answers
  `{:error, :denied}`.

  Answers arrive as `CauldronNative.Device`'s do, `{:device, tag, answer}`:

    * `schedule/4`: `{:ok, :scheduled}`, then `{:ok, :opened}` when the user taps the
      notification, even when the tap started the app
    * `register_push/1`: `{:ok, {:token, :apns | :fcm, token}}`, the token the app's
      server sends pushes to (again whenever the platform changes it); then
      `{:ok, {:received, data}}` for a push that arrives while the app is open and
      `{:ok, {:opened, data}}` when the user taps one, `data` the push's payload

  Push needs the app's config to name it (`CauldronNative.Build.App`'s `:push`); without
  that `register_push/1` answers `{:error, :not_configured}`.

  Apple TV shows no notifications: on tvOS `schedule/4` answers `{:error, :unsupported}`,
  and pushes arrive as `{:ok, {:received, data}}` while the app is open, never as
  `:opened`.
  """

  alias CauldronNative.Device.Request

  @doc """
  Show a notification with `title` and `body`, answered as the module describes; `tag`
  also names it for `cancel/1`, and scheduling another with the same tag replaces it.
  Options: `at` (a `DateTime`) or `after` (seconds from now) to show it later rather than
  now, and `sound` (`true` by default).
  """
  @spec schedule(term(), String.t(), String.t(), keyword()) :: :ok
  def schedule(tag, title, body, opts \\ []),
    do:
      Request.send(tag, "notify", %{
        title: title,
        body: body,
        after: delay(opts),
        sound: Keyword.get(opts, :sound, true)
      })

  @doc "Take back the notification scheduled with `tag`, shown or still to come."
  @spec cancel(term()) :: :ok
  def cancel(tag), do: Request.send(tag, "notify_cancel", %{})

  @doc "Register for push notifications, answered as the module describes."
  @spec register_push(term()) :: :ok
  def register_push(tag), do: Request.send(tag, "push_register", %{})

  defp delay(opts), do: delay(Keyword.get(opts, :at), Keyword.get(opts, :after))

  defp delay(%DateTime{} = at, _after),
    do: max(DateTime.diff(at, DateTime.utc_now(), :millisecond), 0) / 1000

  defp delay(nil, seconds) when is_number(seconds), do: max(seconds, 0)
  defp delay(nil, nil), do: 0
end
