defmodule CauldronNative.Device do
  @moduledoc """
  What an app asks of the phone beyond its screen: haptics, the camera, the photo
  library, files, the microphone, permissions, sharing, links, and audio that plays on
  with the screen off. Each is the platform's own: the system camera and pickers, the
  share sheet, the lock screen's playing controls.

  A request that has an answer is given a `tag`, any term, and the answer arrives as a
  message to the process that runs the app (`CauldronNative.App.Runtime`), so a
  `CauldronNative.App` gets it in `c:CauldronNative.App.handle_info/2`:

      def handle_event(:add_photos, _value, state) do
        CauldronNative.Device.pick_photos(:photos, limit: 3)
        state
      end

      def handle_info({:device, :photos, {:ok, paths}}, state), do: %{state | photos: paths}
      def handle_info({:device, :photos, :cancelled}, state), do: state

  Answers are `{:device, tag, answer}`, `answer` one of `{:ok, value}`, `:cancelled` or
  `{:error, reason}`. Files the phone hands over (photos, videos, recordings, picked
  documents) are copied into the app's own storage first, and `value` holds their paths.

  Permissions the app uses are named in its config, each with the text the phone shows
  when it asks (`CauldronNative.Build.App`'s `:permissions`); a request needing one the app
  does not name answers `{:error, :not_declared}`.

  The phone's position is `CauldronNative.Location`, and notifications are
  `CauldronNative.Notifications`; their answers arrive the same way.
  """

  alias CauldronNative.Device.Request

  @typedoc "A system a native app runs on."
  @type system :: :ios | :tvos | :macos | :android

  @type tag :: term()
  @type haptic ::
          :selection | :light | :medium | :heavy | :soft | :rigid | :success | :warning | :error
  @type permission :: :camera | :microphone | :photos | :location | :notifications

  @doc """
  A haptic: `:selection` (a tick, as a picker's), `:light`, `:medium`, `:heavy`, `:soft`,
  `:rigid` (impacts), `:success`, `:warning` or `:error` (notifications). Nothing on a
  device without a haptic engine.
  """
  @spec haptic(haptic()) :: :ok
  def haptic(style), do: Request.send(nil, "haptic", %{style: style})

  @doc """
  The system's photo picker; answers `{:ok, paths}`. Options: `limit` (default 1, `0` for
  any number), `videos` (`true` to offer videos as well as photos). Needs no permission:
  the picker shows the library only to the player.
  """
  @spec pick_photos(tag(), keyword()) :: :ok
  def pick_photos(tag, opts \\ []),
    do:
      Request.send(tag, "pick_photos", %{
        limit: Keyword.get(opts, :limit, 1),
        videos: Keyword.get(opts, :videos, false)
      })

  @doc "The system camera taking a photo; answers `{:ok, path}` of a JPEG. Needs `:camera`."
  @spec take_photo(tag()) :: :ok
  def take_photo(tag), do: Request.send(tag, "take_photo", %{})

  @doc "The system camera recording a video; answers `{:ok, path}`. Needs `:camera` and `:microphone`."
  @spec record_video(tag()) :: :ok
  def record_video(tag), do: Request.send(tag, "record_video", %{})

  @doc """
  The system's document picker; answers `{:ok, paths}`. Option `types`: any of `:any`
  (default), `:image`, `:video`, `:audio`, `:pdf`, `:text`; option `many` (`true` for more
  than one).
  """
  @spec pick_files(tag(), keyword()) :: :ok
  def pick_files(tag, opts \\ []),
    do:
      Request.send(tag, "pick_files", %{
        types: Keyword.get(opts, :types, [:any]),
        many: Keyword.get(opts, :many, false)
      })

  @doc "Start recording from the microphone. Needs `:microphone`; `stop_recording/0` ends it, and `tag` is then answered `{:ok, path}` of an M4A file."
  @spec start_recording(tag()) :: :ok
  def start_recording(tag), do: Request.send(tag, "record_start", %{})

  @doc "Stop the recording `start_recording/1` began."
  @spec stop_recording() :: :ok
  def stop_recording, do: Request.send(nil, "record_stop", %{})

  @doc "Ask for a permission, showing the system's prompt the first time; answers `{:ok, :granted}` or `{:ok, :denied}`."
  @spec permission(tag(), permission()) :: :ok
  def permission(tag, name), do: Request.send(tag, "permission", %{name: name})

  @doc "The system's share sheet with `text`, a URL, or a file's path (`file: path`)."
  @spec share(String.t() | [file: String.t()]) :: :ok
  def share(file: path), do: Request.send(nil, "share", %{file: path})
  def share(text) when is_binary(text), do: Request.send(nil, "share", %{text: text})

  @doc """
  The system the app runs on: `:ios` (iPhone and iPad, and their simulator), `:tvos`,
  `:macos` or `:android`; `nil` outside a native app.
  """
  @spec system() :: system() | nil
  def system,
    do: system(CauldronNative.available?(), to_string(:erlang.system_info(:system_architecture)))

  @doc """
  Ask the system to show its rating prompt for the app: the App Store's on iOS and the
  Mac, Google Play's in-app review on Android. The system decides whether to show it, at
  most a few times a year, so the app asks at a natural pause and never on a button.
  """
  @spec request_review() :: :ok
  def request_review, do: Request.send(nil, "request_review", %{})

  @doc "Open `url` with the app that handles it: the browser, Maps, Mail, the phone."
  @spec open_url(String.t()) :: :ok
  def open_url(url), do: Request.send(nil, "open_url", %{url: url})

  @doc """
  Play audio from `source` (a path or an `http(s)` URL) in the background: it goes on when
  the app leaves the screen or the phone locks, and the lock screen and control centre
  show `title` and `artist` with play and pause. Answers `tag` with `{:ok, :finished}`
  when it ends. Options: `title`, `artist`.
  """
  @spec play(tag(), String.t(), keyword()) :: :ok
  def play(tag, source, opts \\ []),
    do:
      Request.send(tag, "play", %{
        source: source,
        title: Keyword.get(opts, :title, ""),
        artist: Keyword.get(opts, :artist, "")
      })

  @doc "Pause, resume or stop what `play/3` plays."
  @spec playback(:pause | :resume | :stop) :: :ok
  def playback(action) when action in [:pause, :resume, :stop],
    do: Request.send(nil, "playback", %{command: action})

  defp system(false, _architecture), do: nil

  defp system(true, architecture) do
    cond do
      String.contains?(architecture, "-tvos") -> :tvos
      String.contains?(architecture, "-ios") -> :ios
      String.contains?(architecture, "android") -> :android
      String.contains?(architecture, "-darwin") -> :macos
    end
  end
end
