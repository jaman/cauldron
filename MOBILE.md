# Mobile targets on Cauldron

Status: built, 2026-10-23. Two packages exist: `cauldron_native` (an Elixir release
as an iOS or Android app) and `cauldron_2d_native` (a `cauldron_2d` game on a phone
or tablet). `cauldron_examples/games/beast` builds for both with `mix cauldron_native.build`. What
has and has not been run on hardware is under [Where it stands](#where-it-stands).

How to use it is in the [Mobile releases guide](cauldron_native/guides/building_apps.md), published
with `cauldron_native`'s documentation; this file is the design and why it is so.

Paths are relative to this directory.

## Revisions to the first plan

The first plan (2026-10-22) proposed `cauldron_ios` and `cauldron_android`, each an
embedded runtime, generated bindings to the platform SDK, a native-widget renderer for
business apps, and packaging, with the first test being beast drawn by Metal on an
iPad. Reading the code changed most of that.

1. **Beast does not draw with the GPU.** `mix beast.desktop` never loads
   `cauldron_gpu`: `Cauldron2D.Draw` paints a `FrenchCurve.Raster` on the CPU (with C
   NIFs for the inner loops) and wx shows it as a bitmap. So the games path needs
   no Metal or Vulkan port: the phone shows an RGBA buffer, through a `CALayer` on iOS
   and an `ANativeWindow` on Android. Porting `cauldron_gpu` (its SDL3 windowing to
   UIKit and Android, an iphoneos metallib, Vulkan on Android) is needed only by games
   with `:gpu` scenes, and is its own piece of work.
2. **The native-code inventory was short.** Beast loads four NIFs from `cauldron_2d`,
   one from `french_curve` (its `deflate` NIF falls back to zlib), the speaker NIF,
   and, through `tuning_fork`, `cauldron_2d_net` and `linocut`, OTP's `crypto` and
   `asn1`. So OpenSSL is cross-compiled too, and every NIF package needs a way to be
   linked statically. That way is a `static` target in its `Makefile`
   (`CauldronNative.Build.Nifs`), so a dependency describes its own build instead of
   the app listing it.
3. **One runtime package, not one per platform.** Booting the BEAM, the screen
   bridge, the release, static NIFs and the build steps are the same on both
   platforms; only the shell (Swift or Java + C) and the packaging step differ. They
   live in `cauldron_native` as `native/ios`, `native/android` and two build modules.
   The native-widget renderer for business apps is a separate product built on top of
   the same runtime, not part of it.
4. **No generated SDK bindings.** Generating modules for all of Foundation and the
   Android SDK is a very large API to keep working, and the Swift-only parts (structs,
   `async`, SwiftUI) don't map onto it anyway. The app's shell is ordinary Swift and
   Java the project owns; Elixir talks to it through one small NIF
   (`CauldronNative`): events in (`:screen`, `:touches`, `:lifecycle`, `:back`),
   commands out (`present/3`, `overlay/1`). A platform feature (haptics, the share
   sheet, purchases, notifications) is added as one more command or event on that
   NIF, with its Swift and Java side, when a game or app needs it.
5. **The app hosts the BEAM, not the other way round.** The platform owns the main
   thread (`UIApplicationMain`, the `Activity`); the BEAM runs `erl_start` on a thread
   of its own inside the app process. `erl_drv_steal_main_thread` and the stdio host
   don't come into it.
6. **Touch is a virtual controller, not a pointer.** Beast is played with keys or a
   pad, so a drag cannot steer it. `Cauldron2D.Native.Pad` draws a thumb pad and the
   buttons the game's padmap uses, labelled with their actions (a thumbstick that sets
   down where the thumb lands, the buttons fanned in the bottom right corner, sized in
   points and faint until held, the fan following the thumb that rests on its side,
   mirrored for left-handed play, as phone games and Apple's Touch Controller lay them
   out), and sends
   `Gamepad.Wire` events; sessions, menus and fronts already read those. No new game
   callback and no change to `Cauldron.Input` was needed, and each finger is
   tracked on its own, so steering and striking at once works. A list of pointers in
   `Cauldron.Input` is still needed for pointer-driven games (two-finger gestures,
   pinch to zoom), and is not built.
7. **Leaving the screen needed an engine call.** `Cauldron.Client.Stage.rest/1`
   opens the game's menu (which pauses a world of the player's own) unless it is open
   already, and `wake/1` resumes a game without a menu; `Session` and `Link.Local`
   pass them on. The app rests the game when it goes to the background.

## The design

```
 ┌──────────────── app process ─────────────────────────────────────────┐
 │  main thread: Swift (UIKit, UIScene) / Java (Activity, SurfaceView)    │
 │     touches, size, lifecycle ──► cn_touches/cn_screen/cn_lifecycle ─┐  │
 │     ◄── cn_platform_present (RGBA)   ◄── cn_platform_overlay ──┐    │  │
 │                                                                │    │  │
 │  BEAM thread: erl_start(start_args)                            │    ▼  │
 │     CauldronNative.Native (static NIF) ── present/overlay ─────┘  enif_send
 │     Cauldron2D.Native.Client ── FrontSession (title, summary)          │
 │                              └─ Link.Local → Session → World            │
 │     NIFs: cauldron_2d ×4, french_curve, tuning_fork (miniaudio),       │
 │           crypto + asn1 (OpenSSL), cauldron_native                     │
 └──────────────────────────────────────────────────────────────────────┘
```

### `cauldron_native`

* `CauldronNative` — `available?/0`, `subscribe/1`, `present/3` (shown centred,
  nearest-neighbour, by whole pixels when it fits), `overlay/1` (circles with labels
  over the picture), `screen/0`, `data_dir/0`.
* `c_src/cauldron_native.c` — the NIF; `cauldron_native.h` is everything the
  platform side calls or provides.
* `native/ios` — `main.swift` boots the BEAM then `UIApplicationMain`;
  `Beam.swift` sets `HOME`, the XDG folders, `TMPDIR`, `BINDIR` and the audio
  session, and reads `releases/start_args`; `Screen.swift` is the view controller
  (picture layer, overlay layers, multi-touch, safe-area insets) and the two
  `@_cdecl` functions; `App.swift` the app and scene delegates.
* `native/android` — `CauldronActivity.java` (surface, overlay view, touches,
  insets, back gesture, unpacking the release from the APK on first start after an
  update) and `c_src/android.c` (JNI, the `ANativeWindow` blit, stdout and stderr
  to logcat, the BEAM thread).
* `mix cauldron_native.build ios|android [--install] [--run]` — reruns itself with
  `MIX_TARGET` set, then:
  1. `Build.Otp` cross-compiles OpenSSL 3.5 and the running OTP version (iOS without
     the JIT, Android with it), cached under `~/.cache/cauldron_native/<otp>/<platform>`.
     The shell's `CC`/`CFLAGS`/`CPPFLAGS`/`LDFLAGS` are removed from every command.
  2. `Build.Release` runs `mix release` without ERTS, drops this machine's `.so`
     files, and writes `releases/start_args`.
  3. `Build.Nifs` runs `make static` in every dependency that has the target.
  4. `Build.DriverTab` adds those NIFs to OTP's static NIF table.
  5. `Build.Apple` writes an Xcode project and runs `xcodebuild` (signed with
     `--team`, unsigned without), then `devicectl` installs and launches with the
     console attached. `Build.Android` links `libcauldron_app.so` with the NDK,
     writes a Gradle project, builds a debug APK, and uses `adb`.

### `cauldron_2d_native`

* `Cauldron2D.Native.Client` — the game's title and summary through
  `Cauldron.Net.FrontSession` (the browser's own front runner, with its audio), its
  worlds through `Link.Local`, the pad's events to whichever is showing, taps on the
  picture as left clicks, rest and wake on lifecycle, Android back as Escape, settings
  kept under the game's home.
* `Cauldron2D.Native.Pad` — the on-screen controller.
* `Cauldron2D.Native.Screen` — picture scale (pixels a point times `:point_size`,
  default 0.75, so a tablet shows more of the world rather than a larger picture), pane, and touch-to-picture fractions.
* Started by its application when `CauldronNative.available?()` and
  `config :cauldron_2d_native, game: …` is set.

### What a game project adds

```elixir
def project do
  [
    elixirc_paths: elixirc_paths(Mix.target()),
    releases: [beast: [include_erts: false, strip_beams: true]],
    cauldron_native: [name: "Beast", id: "io.github.jaman.beast", orientation: :landscape],
    deps: deps()
  ]
end

defp deps do
  [
    {:cauldron_2d_wx, path: "…", targets: :host},
    {:cauldron_2d_native, path: "…", targets: [:ios, :android]},
    {:cauldron_native, path: "…", runtime: Mix.target() in [:ios, :android]}
  ]
end
```

and in `config/config.exs`:

```elixir
if config_target() in [:ios, :android], do: config(:cauldron_2d_native, game: Beast.Client)
```

Desktop and terminal front ends stay off the phone through `targets: :host`; code that
names them (beast's mix tasks, the terminal rows of its options page) is compiled only
for the host.

## Platform facts the design depends on

* **No processes.** iOS forbids `fork`; Android allows it but the app has no
  executables. The emulator starts `erl_child_setup` only when something spawns an OS
  process, so nothing in a mobile app may call `System.cmd`, `:os.cmd` or open a
  spawn port. `BINDIR` must still be set or the emulator exits at start.
* **No JIT on iOS.** The emulator is the interpreter, so Elixir-side drawing is
  slower than on a desktop; the C NIFs carry the inner loops and
  `:point_size` trades how much of the world shows for frame time.
* **Writable folders.** The bundle (iOS) and the unpacked release (Android) are read
  only in practice; settings, scores and caches go to the XDG folders the shell
  points into Application Support (iOS) or the app's files folder (Android).
* **Android 15 page size.** The library is linked with 16 KB page alignment.
* **No logging on the device.** The release starts with Elixir's default log
  handler off, the BEAM's output isn't forwarded anywhere, and a crash writes no dump.
  `--run` shows only the system's own crash reports (Android) or the console Xcode
  attaches (iOS).
* **Game controllers.** iOS reads them through the GameController framework, Android
  through gamepad key and motion events; both send `Gamepad.Wire` events. The first
  one connected hides the on-screen controller until the last one goes.
* **Schedulers don't spin** (`+sbwt none` and the dirty variants), so an idle game
  doesn't keep the CPU awake.

## Where it stands

As of 2026-10-23:

* **Android: runs.** `mix cauldron_native.build android --run` builds, installs and
  starts beast on an API 36 arm64 emulator (Pixel 7 profile). The title front draws and
  its menu works from the pad. The journey opens on the Red Plain, and the thumb pad
  walks the beast. Not yet checked: a physical phone, frame rate on real hardware,
  sound on a device, and rest and wake across backgrounding.
* **iOS: runs** on an iPad Pro 11" (iPadOS 26.7) and an iPhone (iPhone18,1), signed
  with a free personal team; the device must be connected while building, since the
  build registers it with the team. Frame rate on the interpreter is fine for beast. Nothing has run on iOS yet, including the
  interpreter's frame rate.
* **3D on both.** Courtyard (`cauldron_examples/3d/courtyard`) runs on the iPhone through
  Metal and on the Android emulator through Vulkan, with its character, scene switching
  and the on-screen controller; the renderer closes when the app leaves the screen and
  opens again on return. On a Mac the emulator needs `ANDROID_EMU_VK_SELECT_ICD=kosmickrisp`
  (its default MoltenVK driver cannot build `cauldron_gpu`'s pipelines). The emulator has
  no ray tracing; ray tracing and frame rate on an Android phone are not yet checked.
* **Size.** Beast's APK is 55 MB: its music is MP3 at 192 kbit/s (26 MB), decoded in C
  on the device by `TuningFork.Speaker.Decoder` (all six songs in under half a second
  on a Mac). The WAV masters are kept in `cauldron_examples/games/beast/audio_masters`, outside
  `priv`, so they don't ship.

## Next

* **Signing for distribution** — TestFlight / App Store archives and a Play upload
  key; today iOS is development-signed and Android is a debug APK.
* **Simulator and emulator builds for x86_64 hosts** — an iOS simulator slice
  (`aarch64-apple-ios-simulator`) and an `x86_64` Android ABI.
* **Text screens** — the phone client draws only the game's fronts and its world;
  a game that relies on the lobby, settings or guide text screens of the desktop and
  terminal clients, or on chat typing, needs those drawn as pictures (or as native
  views) first.
* **Pointer-driven games** — several pointers in `Cauldron.Input` and pinch zoom.
* **Business apps** — a native-widget renderer (SwiftUI / Compose) driven from the
  same runtime, as its own package.
* **App icons and launch images** from the game's art.
