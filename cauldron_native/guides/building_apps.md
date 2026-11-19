# Mobile releases

`cauldron_native` turns an Elixir project into an iOS or an Android app. The app starts the
Erlang runtime inside its own process and boots your release, so your application's
supervision tree runs on the phone exactly as it runs anywhere else. One small native
bridge, `CauldronNative`, connects it to the screen. Your code shows a picture and draws
shapes over it, and receives touches, the screen's size, game controllers and the app's
lifecycle.

A `cauldron_2d` game needs no code of its own for this: `cauldron_2d_native` plays it,
with an on-screen controller, game controllers and touch. Any other application can use
`CauldronNative` directly.

## What you need

The build runs on a Mac.

For iOS:

* an iPhone or iPad on iOS 18 or later
* Xcode, with an Apple ID added under Settings → Accounts. A free Apple ID gives a
  personal team, which signs apps for your own devices
* the iPhone or iPad connected by cable or on the same network, unlocked, trusted, with
  Developer Mode on (Settings → Privacy & Security → Developer Mode)

For Android:

* the Android SDK with an NDK, build tools and a platform (`ANDROID_HOME`, default
  `~/Library/Android/sdk`), for example with Homebrew's `android-commandlinetools` and
  `sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0" "ndk;29.0.14206865"`
* a JDK, 17 or later
* Gradle, for the first build only (`brew install gradle`): it writes the project's
  Gradle wrapper
* a phone with USB debugging on, or an emulator (`sdkmanager "emulator"
  "system-images;android-36;google_apis;arm64-v8a"`, then `avdmanager create avd` and
  `emulator -avd <name>`)

Both platforms use the Erlang/OTP version your Mac runs. The first build for a platform
downloads and cross-compiles OpenSSL and that OTP version, which takes several minutes;
later builds reuse them from `~/.cache/cauldron_native`.

## Setting up a project

Describe the app in `mix.exs`, keep desktop-only dependencies off the phone with
`targets:`, and give the project a release:

```elixir
def project do
  [
    app: :my_game,
    version: "1.2.0",
    elixirc_paths: elixirc_paths(Mix.target()),
    releases: [my_game: [include_erts: false, strip_beams: true]],
    cauldron_native: [name: "My Game", id: "com.example.mygame", orientation: :landscape],
    deps: deps()
  ]
end

defp elixirc_paths(:host), do: ["lib"]
defp elixirc_paths(_phone), do: ["lib/my_game"]

defp deps do
  [
    {:cauldron_2d, "~> 0.4"},
    {:cauldron_2d_wx, "~> 0.4", targets: :host},
    {:cauldron_2d_native, "~> 0.4", targets: [:ios, :android]},
    {:cauldron_native, "~> 0.4", runtime: Mix.target() in [:ios, :android]}
  ]
end
```

`cauldron_native` is a dependency on every target so that its Mix task exists on your
Mac; it runs only in the phone builds. Code that names a desktop-only module, such as a
Mix task that opens a window, belongs where the phone build does not compile it, hence the
`elixirc_paths` above.

The `:cauldron_native` keys are `CauldronNative.Build.App`'s:

| Key | What it is |
| --- | --- |
| `:name` | The name under the app's icon. Required |
| `:id` | The bundle identifier and application id, reverse-DNS. Required |
| `:release` | The release to put in the app. Default: the project's app |
| `:team` | The Apple development team that signs the iOS app |
| `:orientation` | `:landscape` (default), `:portrait` or `:any` |
| `:emulator_flags` | More flags for the Erlang emulator, as `erl` passes them to it |
| `:files` | `[{from, to}]`: folders of this machine copied into the app beside the release, such as downloaded models |
| `:env` | Environment variables set before the BEAM starts; `$ROOT` and `$HOME` stand for the release's folder and the app's writable folder |

A `cauldron_2d` game then names itself for `cauldron_2d_native`, only in the phone builds:

```elixir
# config/config.exs
if config_target() in [:ios, :android] do
  config :cauldron_2d_native, game: MyGame.Client
end
```

## Building and running

```
mix cauldron_native.build ios --team ABCDE12345 --run
mix cauldron_native.build ios --simulator --device "iPhone Duo" --run
mix cauldron_native.build tvos --simulator --run
mix cauldron_native.build macos --run
mix cauldron_native.build android --run
```

The task runs itself again with `MIX_TARGET` set to the system (`ios`, `tvos`, `macos`
or `android`) and `MIX_ENV` set to `prod` unless you set one. Each system's build then has
its own `_build/<system>_prod`. It then:

1. builds OpenSSL and OTP for the platform, once
2. assembles your release, with the OTP applications it needs and without this
   machine's native libraries
3. compiles every dependency's NIFs for the platform and links them into the runtime
4. writes an Xcode or Gradle project under `_build/<system>_prod/cauldron_native/<platform>`
   (a device's and a simulator's builds apart), builds the app, and with `--install` or
   `--run` installs it on the first ready device

| Option | What it does |
| --- | --- |
| `--install` | Install the app on the first connected device; a Mac app is copied into `~/Applications` |
| `--run` | Install it, start it, and show here what the device reports when it ends; a Mac app starts from the build folder |
| `--simulator` | Build for Apple's iOS or tvOS simulator on this Mac |
| `--team` | The Apple development team (also `CAULDRON_NATIVE_TEAM`, or `:team`) |
| `--device` | The device: an Apple device's identifier, a simulator's name or identifier, or an `adb` serial |
| `--log` | Keep Elixir's log on, for a development build; `--run` shows it (on Android through logcat, tag `cauldron`). Without it the app logs nothing |

Without `--team` the iOS app is built unsigned: it compiles and links, which is enough to
check a build, but does not install.

### Signing for iOS

Xcode's automatic signing does the work. The team ID is ten characters; for a personal
team Xcode does not show it, but keeps it where this command prints it:

```
defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier
```

A personal team makes a profile only for a device it has seen, so the device must be
connected while the app is built. The build targets that device and registers it. The
first time an app from a new team is opened on the device, iOS asks for that developer to
be trusted: Settings → General → VPN & Device Management → your Apple ID → Trust.

When no device is ready, the task says which devices it found and what each lacks: not
paired, not connected, or Developer Mode off.

### Simulators, Apple TV and the Mac

`--simulator` builds for the iOS or tvOS simulator of this Mac; OpenSSL and OTP are built
for it once, as for a device. It installs into the simulator running, or the one `--device`
names, starting it first. A simulator build needs no team. Simulators are added in Xcode
under Window → Devices and Simulators, after their runtime under Settings → Components; the
iPhone Duo's simulator shows the fold through `:posture` events.

`tvos` builds an Apple TV app: the same screens, with tvOS's own controls where it lacks
iOS's, moved through with the remote's focus. Apple TV has no photo or file picker,
camera, recording or notifications shown; those requests answer `{:error, :unsupported}`.
The app's `:icon` becomes Apple TV's layered icon and top shelf images.

`macos` builds a Mac app: the same screens in a window with the standard menus, or a
game's screen. Without `--team` it is signed to run on this Mac. It runs programs
(`System.cmd/3`) as a Mac app may, and keeps its files under
`~/Library/Application Support/<the app's id>`.

### Android

The APK is a debug build, signed with the SDK's debug key. `adb devices` lists what it
installs on. The app unpacks the release from the APK into its own files the first time it
starts after an install or update.

## On the device

* **The runtime.** The app starts the BEAM on a thread of its own and hands the platform's
  main thread to UIKit or the Android activity. The release boots with `-mode embedded`.
  On iOS the emulator has no JIT, as Apple does not allow one; on Android it has it.
* **The screen.** `CauldronNative.present/3` shows a picture, scaled by whole pixels where
  it fits, centred, nearest-neighbour; `CauldronNative.overlay/1` draws circles with
  labels over it. Events arrive as `{:cauldron_native, kind, payload}`: `:screen`,
  `:touches`, `:lifecycle`, `:back` (Android) and `:pad` (game controllers). `CauldronNative`
  documents each.
* **Files.** The release is read-only. `HOME`, the XDG folders and `TMPDIR` point into the
  app's own storage before the BEAM starts, so code that keeps files under them works;
  `CauldronNative.data_dir/0` is that folder.
* **No logging.** Elixir's default log handler is off (unless the build was made with
  `--log`), the runtime's output goes nowhere, and a crash writes no dump.
* **The graphics card.** `CauldronNative.gpu_surface/0` gives a surface over the
  picture, a Metal layer on iOS and a Vulkan window on Android, and
  `CauldronGPU.open(surface: handle)` draws into it with `cauldron_gpu`. A renderer
  closes when the app leaves the screen and opens again when it returns. A
  `cauldron_2d` game whose scenes have a `:gpu` is drawn that way by
  `cauldron_2d_native`. Android needs a device or emulator with Vulkan 1.3.
* **No processes.** The app is one process: `System.cmd/3`, `:os.cmd/1` and ports that
  run programs are not available.
* **The network.** An Android app may use the network (the `INTERNET` permission). Elixir
  resolves host names with its own resolver, against the DNS servers of the network the
  phone was on when the app started, written to the app's `inetrc` (`ERL_INETRC`). iOS
  resolves them as the system does.
* **Quitting.** `CauldronNative.quit/0` closes an Android app. An iOS app does not close
  itself.
* **Idle.** Schedulers do not spin while idle, so a game at rest does not keep the phone
  awake.

## Native code in dependencies

An app links every NIF statically, so a dependency with native code takes part by adding a
`static` target to its `Makefile`. The build runs it with `CC`, `AR`, `CFLAGS`,
`ERTS_INCLUDE_DIR`, `STATIC_DIR` and `CAULDRON_TARGET` (`ios`, `tvos`, `macos` or
`android`) set. On Apple's systems it also sets `APPLE_SDK` and `APPLE_TARGET`, for
`xcrun -sdk` and a Swift or Metal compile's `-target`. For each
NIF it writes `<name>.a` into `STATIC_DIR`, compiled with
`-DSTATIC_ERLANG_NIF_LIBNAME=<name>`, and may write `<name>.ldflags` with the frameworks or
system libraries the link needs:

```make
STATIC_DIR ?= priv/static

static: $(STATIC_DIR)/my_nif.a

$(STATIC_DIR)/%.a: c_src/%.c | $(STATIC_DIR)
	$(CC) $(CFLAGS) -DSTATIC_ERLANG_NIF_LIBNAME=$* -I$(ERTS_INCLUDE_DIR) -c -o $(STATIC_DIR)/$*.o $<
	$(AR) rcs $@ $(STATIC_DIR)/$*.o

$(STATIC_DIR):
	mkdir -p $(STATIC_DIR)
```

The module that loads the NIF keeps calling `:erlang.load_nif/2` with any path: the runtime
finds a static NIF by the module that loads it. A dependency with a `c_src` folder and no
`static` target is named in the build's output and left out; its module must run without
its NIF. `CauldronNative.Build.Nifs` documents the convention.

## Apps with native controls

An app that is not a game is written as a `CauldronNative.App` and named in the config:
`config :cauldron_native, app: MyApp.App`. Its screens are SwiftUI on iOS and Jetpack
Compose with Material 3 on Android, drawn by the platform. They take the device's fonts,
text size, light or dark appearance, keyboard, scrolling and accessibility. The window
keeps the status bar and draws under it, as the platform's own apps do.

* **State and events.** `mount/1` gives the first state, `render/1` the screen as
  `CauldronNative.UI` nodes, and `handle_event/3` the state after a control's event, with
  the control's value. Any other message, such as a timer or the app's lifecycle, goes to
  `handle_info/2`. After each, only the controls that changed go to the platform.
* **Controls.** Text, icons and images (from the app or the web), labels, links,
  buttons, chips and menus; text, password and many-line fields; toggles, sliders,
  steppers, pickers (a menu, segments, a wheel or rows) and date and time pickers;
  progress; stacks, scroll views, grids, cards, expandable sections, lists and forms with
  sections. Each is the platform's own: a Material exposed dropdown on Android where iOS
  shows a menu, a list item where iOS shows a list row.
* **Screens.** A navigation stack of screens, each with its bar's title, toolbar buttons
  and menus, and a search field. Tabs are a tab bar on a phone, a tab bar that opens into a
  sidebar on an iPad, and a navigation rail on a large Android screen. Sheets, alerts and
  action sheets sit over a screen while the app's state says so. The platform does the back
  gesture and the push and pop animations. The app is told how many screens remain
  (`on_back`) and when a sheet or alert is swiped or tapped away (`on_dismiss`).
* **Values.** A picker's options and tabs' ids are any terms, and a date picker's value is
  a `Date`, `Time` or `NaiveDateTime`. The platform is sent positions and ISO 8601 text,
  and the app gets its own terms back (`CauldronNative.UI.Value`).
* **Icons** have names both platforms share (`:home`, `:search`, `:share`, …), drawn as
  SF Symbols on iOS and Material icons on Android; `ios:` and `android:` name a
  platform's own.
* **Text fields** keep their own text, cursor and selection while the user types. The app
  is sent each edit, and may still replace the text, such as clearing it after a send.
* **Modifiers.** `modifiers:` adjusts a control with the platform's own adjustments:
  padding, a text style, a colour role, a frame, rounded corners, opacity, bold, and any
  under `ios:` or `android:` for one platform.
* **Video and the camera.** `video/2` plays a file or a web address in the platform's
  player (AVKit on iOS, Media3 on Android), with its controls, full screen and picture in
  picture. `camera_preview/1` shows what the camera sees, once the app has the camera
  permission.
* **Charts and maps.** `chart/2` draws bars, lines, areas, points, pies and rings with
  Swift Charts on iOS and Vico, a Material chart library, on Android. `map/1` is MapKit
  on iOS and Google Maps on Android, which needs the app's `maps: [android_key: …]`.
  Markers, the phone's position, the marker tapped and the view moved arrive as events.
* **Views of the app's own.** A SwiftUI view in the project's `native/ios` folder that
  conforms to `CauldronNativeView`, or a Kotlin object in `native/android` that
  implements it, is placed with `CauldronNative.UI.native/2` under the name it gives. The
  build compiles them into the app; `CauldronNative.Build.NativeViews` shows both forms.
  The generated projects under `_build/<target>_dev/cauldron_native/` open in Xcode and
  Android Studio for previews, the inspectors and the debugger.

### The phone's services

`CauldronNative.Device` asks the phone for what lies beyond the app's screen, each through
the platform's own interface:

| Ask | iOS | Android |
| --- | --- | --- |
| `haptic/1` | UIKit feedback generators | the view's haptic feedback |
| `pick_photos/2` | the photo picker | the photo picker |
| `take_photo/1`, `record_video/1` | the system camera | the system camera app |
| `pick_files/2` | the document picker | the document picker |
| `start_recording/1`, `stop_recording/0` | the microphone, to AAC in M4A | the microphone, to AAC in M4A |
| `permission/2` | the system's prompt | the system's prompt |
| `share/1` | the share sheet | the share sheet |
| `open_url/1` | the app that opens the address | the app that opens the address |
| `play/3`, `playback/1` | audio that plays on with the screen locked, with the lock screen's controls | the same, through a media session |

`CauldronNative.Location` gives the phone's position, once or as it moves, and
`CauldronNative.Notifications` shows the app's own notifications now or later and
registers for push (Apple's push service with `push: [ios: true]`, Firebase Cloud
Messaging with `push: [android: "google-services.json"]`). A notification the user taps
answers the app, even when the tap starts it.

A request with an answer takes a tag, and the answer comes to `handle_info/2` as
`{:device, tag, {:ok, value} | :cancelled | {:error, reason}}`. Files the phone hands
over are copied into the app's own storage, and their paths are the value.

Permissions are named in the app's config with the reason the phone shows, and
`background_audio: true` lets `play/3` go on in the background:

```elixir
cauldron_native: [
  name: "Notes",
  id: "com.example.notes",
  permissions: [camera: "Takes photos for your notes", microphone: "Records voice notes"],
  background_audio: true
]
```

The build writes them where each platform looks: usage descriptions and the audio
background mode in iOS's `Info.plist`, permissions and a media playback service in
Android's manifest. A request that needs a permission the app does not name answers
`{:error, :not_declared}`.

### The app's own art and size

An app's images, colours and symbols are an Xcode asset catalog, named by `assets:` in
its config. Apple's systems use it as an Xcode project's own catalog (its `AccentColor`
is the app's accent), and Android takes it converted into drawables, colours and vector
drawables (`CauldronNative.Build.Assets`). Elixir shows an image of it with
`image({:asset, "dough/blue-full"})`, a label or icon with `asset:`, and a colour with
`{:asset, "AccentColorDimmed"}`. The app's own Swift reads `Image("dough/blue-full")`; its
Kotlin reads `cauldronAsset("dough/blue-full")`.

The app learns its window's size, and whether it is a phone's narrow one, from
`{:cauldron_native, :window, %{width, height, compact}}` in `handle_info/2`. It can lay out
for that as SwiftUI's size classes do. The Mac window's first and least size is
`window: [width: 1000, height: 650, min_width: 600, min_height: 450]`, and
`menu_bar_extra/3` adds an item to the Mac's menu bar.

### Outside the app

| Module | Apple | Android |
| --- | --- | --- |
| `CauldronNative.Weather` | WeatherKit, or Open-Meteo without its capability | Open-Meteo |
| `CauldronNative.Widget` | a WidgetKit extension, sharing an App Group with the app | Glance widgets |
| `CauldronNative.LiveActivity` | a Live Activity (Lock Screen, Dynamic Island) | a Live Update: an ongoing notification promoted to the status bar chip on Android 16 QPR1 and later |
| `CauldronNative.Background` | `BGTaskScheduler` (iOS, tvOS), `NSBackgroundActivityScheduler` (macOS) | WorkManager, which starts the app's BEAM without its activity |
| `CauldronNative.Purchases` | StoreKit | Google Play Billing |
| Links (`url_schemes:`) | the app's URL types | an intent filter |

Each is switched on in the app's config:

```elixir
cauldron_native: [
  name: "Food Truck",
  id: "com.example.foodtruck",
  weatherkit: true,
  url_schemes: ["foodtruck"],
  background_refresh: true,
  widgets: [orders: [name: "Orders", description: "Orders waiting", sizes: [:small, :medium]]],
  live_activities: true,
  purchases: [pro: [type: :non_consumable, name: "Food Truck Pro", price: "4.99"]]
]
```

A link the app opens arrives as `{:cauldron_native, :url, url}`, and a background
refresh as `{:cauldron_native, :background, :refresh}`, to be ended with
`CauldronNative.Background.done/0`.

A widget kind's sizes may include the Lock Screen's `:circular`, `:rectangular` and
`:inline` on iOS. Its content may differ per size (`%{small: …, circular: …}`) and change on
a timeline (`CauldronNative.Widget.timeline/2`). A Live Activity can count down to a time
and show the app's own pictures and colours, and open a link when tapped.

WeatherKit needs a paid Apple Developer Program membership; App Groups (which the
widget extension needs) and in-app purchases work with a personal team too. `xcodebuild`
does not register a new App Group with the team, so the first device build of an app
with widgets fails with a profile that "doesn't match the entitlements file's value for
the com.apple.security.application-groups entitlement". Open `App.xcodeproj` in the build
folder, choose the device and Product ▸ Build once, and Xcode registers `group.<app id>`.
Builds from the task work from then on.

A purchase's id in App Store Connect and the Play Console is the app's id, a dot and
the product's key. The Xcode project carries a StoreKit
configuration of the products and a scheme that uses it, so the app run from Xcode
(open `App.xcodeproj` in the build folder, then Product ▸ Run) buys from it without
App Store Connect; Debug ▸ StoreKit ▸ Manage Transactions shows and refunds them.
Google Play Billing answers only on a device or emulator signed in to Google Play, and
only for an app uploaded to the Play Console.

On the computer, `CauldronNative.App.Runtime.start_link(app: MyApp.App, send: fun)` runs
the app with each patch given to `fun`, for tests.

## Games: `cauldron_2d_native`

With `config :cauldron_2d_native, game: MyGame.Client` the app plays the game:

* the game's own title and summary, and its worlds, at a picture size that follows the
  screen's size in points (`:point_size`, default `0.75`), so a tablet shows more of the
  world rather than a larger picture
* an on-screen controller laid out as phone games lay theirs out: a thumbstick that sets
  down where the thumb lands, the buttons fanned in the opposite bottom corner and
  labelled with the game's actions, faint until held, left- or right-handed
* game controllers connected to the device, which hide the on-screen controller
* taps on the picture as clicks, the app's lifecycle opening the game's menu, Android's
  back gesture as Escape

`Cauldron2D.Native.Settings.menu_items/1` gives the rows a game's options page shows for
the controller (which hand, and whether the buttons stay put). See `cauldron_2d_native`.

## Size

The app carries your release as it is: what is in your applications' `priv` folders is in
the app. Music is the usual weight; compressed audio, such as MP3 decoded on the device by
`Cauldron.Audio.Decoder`, keeps an app small.

## Troubleshooting

| What you see | What it means |
| --- | --- |
| `No iOS device is ready to install on` and a list | Each device's line says what it lacks: connect and unlock it, pair it, or turn on Developer Mode |
| `Your team has no devices from which to generate a provisioning profile` | The device was not connected and ready while building; connect it and build again |
| `<dependency> has native code but no static target` | That dependency's NIF is not in the app; add a `static` target to its Makefile |
| The app closes as it starts | Build without `--run`, then start it with `--run` to see what the device reports. Missing OTP applications or a module that needs a program on the machine are the usual causes |
| `adb lists no device or emulator` | Start the emulator, or connect a phone with USB debugging on and accept the prompt on it |
| A `cauldron_gpu` app shows black on an Android emulator on a Mac, and a `--log` build reports `pipeline_create failed` | The emulator's default Vulkan driver (MoltenVK) cannot place `cauldron_gpu`'s texture arrays. Start the emulator with Mesa's KosmicKrisp driver: `ANDROID_EMU_VK_SELECT_ICD=kosmickrisp emulator -avd <name> -gpu host`. Phones are not affected |

## Publishing

`--release` builds what the stores take: an `.ipa` for App Store Connect and an Android
App Bundle for Google Play. The guide "Publishing" covers the accounts, the config the
stores require (icon, launch screen, privacy, build number, upload key) and each store's
review.

## Not covered yet

* An app inside an existing Xcode or Android Studio project, and a game view inside an
  app's native screens
* x86_64 Android and Intel Macs: the builds are for arm64
* Keyboard input for a game on the Mac: a game's screen takes the mouse as a touch and
  game controllers
