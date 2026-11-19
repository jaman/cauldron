# On a phone or tablet

`cauldron_native` builds an Elixir project as an iOS, tvOS, macOS or Android app. The app
starts the Erlang runtime inside its own process and boots your release, so your
application's supervision tree runs on the device as it runs anywhere else. A small native
bridge, `CauldronNative`, gives that code the screen: a picture, shapes over it, touches,
the screen's size, game controllers and the app's lifecycle.

The package gives a game two ways to reach a phone or a tablet:

| You have | You use | What the player sees |
| --- | --- | --- |
| A `cauldron_2d` game | `cauldron_2d_native` in this host | The game's own screens, with an on-screen controller |
| An app of your own | `CauldronNative.App` and `CauldronNative.UI` | The platform's native controls |

## A game in a native host

A `cauldron_2d` game needs no phone code of its own. `cauldron_2d_native` plays it in the
host:

* the game's title and summary, and its worlds, at a picture size that follows the
  screen's size in points
* an on-screen controller laid out as phone games lay theirs out: a thumbstick that sets
  down where the thumb lands, buttons fanned in the opposite corner and labelled with the
  game's actions, faint until held, left- or right-handed
* game controllers connected to the device, which hide the on-screen controller
* taps on the picture as clicks
* the app's lifecycle opening the game's menu, and Android's back gesture as Escape

The project names the game only in the phone builds:

```elixir
# config/config.exs, in the phone build
config :cauldron_2d_native, game: MyGame.Client
```

`cauldron_native` is a dependency on every target so that its Mix task exists on the
build machine, and runs only in the phone builds. Desktop-only dependencies are kept off
the phone with `targets:`:

```elixir
defp deps do
  [
    {:cauldron_2d, "~> 0.4"},
    {:cauldron_2d_wx, "~> 0.4", targets: :host},
    {:cauldron_2d_native, "~> 0.4", targets: [:ios, :android]},
    {:cauldron_native, "~> 0.4", runtime: Mix.target() in [:ios, :android]}
  ]
end
```

The project needs a release, described in `mix.exs` with the app's name and id:

```elixir
def project do
  [
    app: :my_game,
    version: "1.2.0",
    releases: [my_game: [include_erts: false, strip_beams: true]],
    cauldron_native: [name: "My Game", id: "com.example.mygame", orientation: :landscape],
    deps: deps()
  ]
end
```

The `:cauldron_native` keys are `CauldronNative.Build.App`'s:

| Key | What it is |
| --- | --- |
| `:name` | The name under the app's icon. Required |
| `:id` | The bundle identifier and application id, reverse-DNS. Required |
| `:release` | The release to put in the app. Default: the project's app |
| `:team` | The Apple development team that signs the iOS app |
| `:orientation` | `:landscape` (default), `:portrait` or `:any` |
| `:emulator_flags` | More flags for the Erlang emulator |
| `:files` | `[{from, to}]`: folders copied into the app beside the release |
| `:env` | Environment variables set before the BEAM starts |

`mix cauldron_native.build` runs itself again with `MIX_TARGET` set to the system and
`MIX_ENV` set to `prod` unless you set one. It builds a release, compiles every
dependency's NIFs for the platform, writes an Xcode or Gradle project, and builds the app.
The first build for a platform downloads and cross-compiles OpenSSL and OTP, which takes
several minutes. Later builds reuse them from `~/.cache/cauldron_native`.

```
mix cauldron_native.build ios --team ABCDE12345 --run
mix cauldron_native.build ios --simulator --run
mix cauldron_native.build android --run
mix cauldron_native.build macos --run
```

The build runs on a Mac. `--install` installs the app on the first ready device;
`--run` installs, starts it, and shows what the device reports. Without `--team` an iOS
app is built unsigned: it compiles and links, but does not install. The
[Mobile releases](building_apps.html) guide covers the tools each platform needs, signing,
simulators, Android, the device's limits and troubleshooting.

## An app with native controls

An app that is not a game shows the platform's own controls. Its screens are written in
Elixir and drawn by SwiftUI on iOS, tvOS and the Mac, and by Jetpack Compose with Material
3 on Android. They take the device's fonts, text size, light or dark appearance, keyboard,
scrolling and accessibility, and the platform does the navigation animations and the back
gesture.

```elixir
defmodule Counter.App do
  use CauldronNative.App

  @impl true
  def mount(_params), do: %{count: 0}

  @impl true
  def render(state) do
    navigation([
      screen("Counter", [
        vstack([
          text("Pressed #{state.count} times", modifiers: [font: :title]),
          button("Press", style: :prominent, on_tap: :press)
        ])
      ])
    ])
  end

  @impl true
  def handle_event(:press, _value, state), do: %{state | count: state.count + 1}
end
```

Name the module in the config:

```elixir
config :cauldron_native, app: Counter.App
```

`mount/1` gives the first state, `render/1` the screen as `CauldronNative.UI` nodes, and
`handle_event/3` the state after a control's event, with the control's value. Any other
message, such as a timer or the app's lifecycle, goes to `handle_info/2`. After each,
only the controls that changed go to the platform.

| Part | What it gives |
| --- | --- |
| Controls | Text, images, labels, links, buttons, chips, menus, fields, toggles, sliders, steppers, pickers, progress |
| Layout | Stacks, scroll views, grids, cards, expandable sections, lists and forms |
| Screens | A navigation stack with titles, toolbar buttons and search; tabs, sheets, alerts and action sheets |
| Modifiers | Padding, text style, colour role, frame, corners, opacity, bold, and per-platform ones |
| Media | `video/2` in the platform's player, `camera_preview/1` for the camera |
| Charts and maps | `chart/2` with Swift Charts or Vico; `map/1` with MapKit or Google Maps |
| Your own views | A SwiftUI or Kotlin view under `native/ios` or `native/android`, placed with `CauldronNative.UI.native/2` |

The package's other modules reach the phone's services: `CauldronNative.Device` for
photos, files, the camera, recording, permissions, sharing and audio;
`CauldronNative.Location` for the phone's position; `CauldronNative.Notifications` for
local and push notifications; `CauldronNative.Purchases` for StoreKit and Google Play
Billing; `CauldronNative.Widget`, `CauldronNative.LiveActivity` and
`CauldronNative.Background` for the system's surfaces outside the app;
`CauldronNative.Weather` for a forecast. Each is switched on in the
app's config, and each answers through `handle_info/2`.

## The screen both ways share

One bridge sits under both uses. `CauldronNative.subscribe/1` sends the calling process
the screen's events:

| Event | What it reports |
| --- | --- |
| `{:cauldron_native, :screen, %{width, height, scale, insets}}` | The drawable area, its pixel scale and its insets |
| `{:cauldron_native, :touches, [%{id, phase, x, y}]}` | The touches that changed together |
| `{:cauldron_native, :lifecycle, state}` | The app came forward, lost focus, or left; `state` is `:active`, `:inactive` or `:background` |
| `{:cauldron_native, :posture, %{fold, angle, hinge}}` | How a foldable is folded |
| `{:cauldron_native, :back, :pressed}` | Android's back gesture or button |
| `{:cauldron_native, :pad, event}` | A game controller's buttons and sticks |

`CauldronNative.present/3` shows a picture, scaled by whole pixels where it fits,
centred; `CauldronNative.overlay/1` replaces the circles drawn over it. A game that draws
with the graphics card asks for a surface with `CauldronNative.gpu_surface/0` and gives
it to `CauldronGPU.open(surface: handle)`; `hide_gpu_surface/0` gives the picture back.

The release is read-only. `HOME`, the XDG folders and `TMPDIR` point into the app's own
storage before the BEAM starts, and `CauldronNative.data_dir/0` is that folder. The app is
one OS process: `System.cmd/3`, `:os.cmd/1` and ports that run programs are not available.
Elixir's log handler is off unless the build was made with `--log`, and a crash writes no
dump. On iOS the BEAM runs without a JIT; on Android it uses one. The builds are for
arm64.

## Publishing

`--release` builds what the stores take: an `.ipa` for App Store Connect and an Android
App Bundle for Google Play. The icon, launch screen, privacy manifest, build number and
signing are described in the app's config, and the
[Publishing](publishing.html) guide covers the accounts, the config each store requires,
and each store's review.

## Where to go next

| You want to | Read |
| --- | --- |
| Build and run on a device | [Mobile releases](building_apps.html) |
| Send a build to a store | [Publishing](publishing.html) |
| Play a game on a phone | [`Cauldron2D.Native.Client`](https://hexdocs.pm/cauldron_2d_native/Cauldron2D.Native.Client.html) |
| Draw with Metal or Vulkan | [`cauldron_gpu`](https://hexdocs.pm/cauldron_gpu/CauldronGPU.html) |
