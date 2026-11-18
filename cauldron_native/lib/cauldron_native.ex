defmodule CauldronNative do
  @moduledoc """
  The screen of a phone or tablet app whose BEAM runs inside it: the picture shown on
  it, shapes drawn over the picture, and the touches, size and lifecycle it reports.

  An app built with `mix cauldron_native.build` boots its release on launch, so the
  application's own supervision tree is what runs; one of its processes subscribes and
  then draws:

      if CauldronNative.available?() do
        :ok = CauldronNative.subscribe()
        :ok = CauldronNative.present(320, 180, rgba)
      end

  ## Events

  The subscriber receives, each as `{:cauldron_native, kind, payload}`:

    * `{:cauldron_native, :screen, %{width, height, scale, insets}}` — the drawable
      area in pixels, the pixels a point holds, and the insets `{top, right, bottom,
      left}` in pixels that a camera cutout or rounded corner takes: iOS's safe area,
      Android's display cutout. Sent on subscribing when the size is already known, and
      whenever it changes
    * `{:cauldron_native, :touches, [%{id, phase, x, y}]}` — the touches that changed
      together, `phase` one of `:began`, `:moved`, `:ended` or `:cancelled`, `x` and `y`
      in pixels from the top left; `id` stays the same for one finger from `:began`
      until `:ended` or `:cancelled`
    * `{:cauldron_native, :lifecycle, :active | :inactive | :background}` — the app came
      to the front, lost the focus (a call, the app switcher), or left the screen
    * `{:cauldron_native, :posture, %{fold, angle, hinge}}` — how a foldable is folded
      (the iPhone Duo, Android foldables): `fold` one of `:closed`, `:half_open`,
      `:open` or `:unknown`; `angle` the hinge's angle in degrees, `0.0` shut and
      `180.0` flat, or `nil` when the device does not say; `hinge` `nil`, or where the
      fold crosses the app's window, `%{x, y, width, height, vertical, separating}` in
      pixels, `vertical` when it runs top to bottom and `separating` when it splits the
      window into two areas to lay out apart (half open, or a hinge with a gap). iOS
      reports no `hinge`. A device that does not fold sends none. Sent on subscribing
      when the fold is already known, and whenever it changes. On Android, `fold` is
      the system's `:half_open` or `:open` while the fold crosses the window, `:closed`
      while it does not and the hinge is within 10 degrees of shut, `:unknown` otherwise
    * `{:cauldron_native, :window, %{width, height, compact}}` — the size in points (dp
      on Android) of a `CauldronNative.App`'s window, given to its `handle_info/2` when
      it first shows and whenever it changes; `compact` is true for iOS's compact
      horizontal size class and an Android window narrower than 600 dp, a phone held
      upright
    * `{:cauldron_native, :back, :pressed}` — Android's back gesture or button
    * `{:cauldron_native, :url, url}` — a link with one of the app's `:url_schemes`
      (`CauldronNative.Build.App`) opened the app, `url` the whole link as text; a link
      that started the app arrives once the app subscribes
    * `{:cauldron_native, :pad, event}` — a game controller connected to the device
      (Bluetooth or USB), `event` a `Gamepad.Wire` event map: `%{type: :connected,
      device, name}`, `%{type: :disconnected, device}`, `%{type: :button, device, button,
      pressed}` or `%{type: :axis, device, axis, value}`, buttons and axes named in the
      Xbox layout whatever the controller. A device is the platform's own number for the
      controller

  There is one subscriber; subscribing again moves the events to the new process.

  ## Drawing

  `present/3` shows a picture scaled to fit the screen by whole pixels where it can,
  centred, nearest-neighbour, the rest of the screen black. `overlay/1` replaces the
  shapes drawn over it. Both may be called from any process.

  ## Files

  `data_dir/0` is the app's own writable folder. The app also sets `HOME`,
  `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME`, `XDG_CACHE_HOME` and `TMPDIR`
  inside it before the BEAM starts, so code that keeps files under those finds them
  writable.

  ## Logging

  An app keeps no log: the release starts with Elixir's default log handler off
  (`CauldronNative.Build.Release`), the BEAM's output goes nowhere, and a crash writes
  no dump. A development build made with `mix cauldron_native.build --log` keeps the
  handler on; on Android its output goes to logcat under the tag `cauldron`.

  ## Limits

  The app is one OS process: `System.cmd/3`, `:os.cmd/1` and ports that run programs
  are not available. On iOS the BEAM runs without the JIT.
  """

  alias CauldronNative.Native

  @type shape :: %{
          required(:x) => number(),
          required(:y) => number(),
          required(:radius) => number(),
          optional(:label) => String.t(),
          optional(:held?) => boolean(),
          optional(:alpha) => number()
        }

  @doc "Whether this BEAM runs inside a mobile app."
  @spec available?() :: boolean()
  def available?, do: Native.loaded()

  @doc "Send the screen's events to `pid` (see Events)."
  @spec subscribe(pid()) :: :ok
  def subscribe(pid \\ self()), do: Native.subscribe(pid)

  @doc "Show `rgba`, `width` by `height` pixels, four bytes a pixel, rows from the top."
  @spec present(pos_integer(), pos_integer(), binary()) :: :ok
  def present(width, height, rgba)
      when is_integer(width) and is_integer(height) and byte_size(rgba) == width * height * 4,
      do: Native.present(width, height, rgba)

  @doc """
  Draw `shapes` over the picture, replacing those drawn before: each a circle at `{x,
  y}` of `radius`, all in pixels, outlined, filled when `held?`, with `label` written in
  its middle, at `alpha` opacity (`0.0` to `1.0`, default `1.0`).
  """
  @spec overlay([shape()]) :: :ok
  def overlay(shapes) when is_list(shapes),
    do: shapes |> Enum.map(&pack/1) |> IO.iodata_to_binary() |> Native.overlay()

  @doc "The screen as last reported (see Events), or `nil` before the app has laid out."
  @spec screen() :: map() | nil
  def screen, do: Native.screen()

  @doc "The fold as last reported (see Events), or `nil` on a device that does not fold."
  @spec posture() :: map() | nil
  def posture, do: Native.posture()

  @doc """
  Close the app. Android finishes it and ends its process; iOS, where an app may not
  close itself, does nothing.
  """
  @spec quit() :: :ok
  def quit, do: Native.quit()

  @doc """
  A surface covering the screen, under the overlay and over any picture `present/3`
  shows, for a renderer that draws with the graphics card (such as `cauldron_gpu`):
  `{:ok, handle}`, a pointer as an integer, which the renderer takes over.

  * iOS: a `CAMetalLayer *`, for Metal. It exists once the app's view does, so ask once
    the first `:screen` event has arrived.
  * Android: an `ANativeWindow *`, for Vulkan, on a view of its own. The first call
    shows that view, and its window arrives a moment later; until then, and while the
    app is off the screen, the answer is `{:error, :unavailable}`. Ask again on a later
    frame.

  The surface stays shown until `hide_gpu_surface/0`. A renderer must close, and the
  app call `hide_gpu_surface/0`, when the app leaves the screen (a `:lifecycle` event
  other than `:active`): Android takes the window away then. Ask again for a surface
  once the app is back.
  """
  @spec gpu_surface() :: {:ok, non_neg_integer()} | {:error, :unavailable}
  def gpu_surface, do: Native.gpu_surface()

  @doc """
  Hide the surface `gpu_surface/0` showed, once its renderer has closed, so pictures
  from `present/3` show again. `gpu_surface/0` shows it again.
  """
  @spec hide_gpu_surface() :: :ok
  def hide_gpu_surface, do: Native.hide_gpu_surface()

  @doc "The app's own writable folder, or `nil` outside a mobile app."
  @spec data_dir() :: String.t() | nil
  def data_dir, do: System.get_env("CAULDRON_NATIVE_DATA")

  defp pack(%{x: x, y: y, radius: radius} = shape) do
    label = Map.get(shape, :label, "")
    held = if Map.get(shape, :held?, false), do: 1, else: 0
    alpha = shape |> Map.get(:alpha, 1.0) |> max(0.0) |> min(1.0) |> Kernel.*(255) |> round()

    <<x / 1::float-32-little, y / 1::float-32-little, radius / 1::float-32-little, held::8,
      alpha::8, byte_size(label)::16-little, label::binary>>
  end
end
