defmodule CauldronNative.Background do
  @moduledoc """
  Work the system wakes the app for while it is not on the screen, such as fetching new
  content: Android's WorkManager, iOS's and tvOS's background app refresh
  (`BGTaskScheduler`), and macOS's background activity scheduler.

  The app's config names it (`background_refresh: true`, `CauldronNative.Build.App`).
  `schedule/2` asks for a refresh about every `minutes`; the system chooses the moment,
  no sooner than that, and on iOS only as often as the user's use of the app earns.
  When it comes, the app's subscriber receives `{:cauldron_native, :background,
  :refresh}`, after starting the BEAM if the app was not running, and calls `done/0`
  when the work is finished; the system gives about 25 seconds.

      def handle_info({:cauldron_native, :background, :refresh}, state) do
        state = MyApp.Sync.run(state)
        CauldronNative.Background.done()
        state
      end

  `schedule/2` is answered as `CauldronNative.Device`'s requests are, `{:device, tag,
  {:ok, :scheduled}}`, or `{:error, :not_configured}` when the config does not name it.
  """

  alias CauldronNative.Device.Request

  @doc "Ask for a refresh about every `minutes` (15 at least on Android and iOS)."
  @spec schedule(term(), pos_integer()) :: :ok
  def schedule(tag, minutes) when is_integer(minutes) and minutes > 0,
    do: Request.send(tag, "background_schedule", %{minutes: minutes})

  @doc "Say that the work of the latest refresh is finished."
  @spec done() :: :ok
  def done, do: Request.send(nil, "background_done", %{})

  @doc "Stop the refreshes."
  @spec cancel() :: :ok
  def cancel, do: Request.send(nil, "background_cancel", %{})
end
