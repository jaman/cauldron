# Native UI on iOS and Android

Apps that are not games (forms, lists, settings, accounts, tools) are built in Elixir and
shown with each platform's own toolkit: SwiftUI on iOS, Jetpack Compose on Android. Cauldron
does not draw these apps' controls itself. The platform draws them, so they look and behave
as the device's own apps do: system fonts, dark mode, Dynamic Type, safe areas, keyboard,
scrolling, haptics, and VoiceOver and TalkBack.

## How it works

The app's state and logic live in Elixir, on the device, in the BEAM that `cauldron_native`
already runs. The app describes its screen as a tree of plain Elixir data: stacks, text,
buttons, fields, lists. The native side turns that tree into SwiftUI or Compose views.

```elixir
defmodule Notes.App do
  use CauldronNative.App

  def mount(_params), do: %{notes: [], draft: ""}

  def render(state) do
    navigation([
      screen("Notes", [
        list(for note <- state.notes, do: text(note, id: note)),
        text_field("New note", value: state.draft, on_change: :draft),
        button("Add", on_tap: :add, disabled: state.draft == "")
      ])
    ])
  end

  def handle_event(:draft, text, state), do: %{state | draft: text}
  def handle_event(:add, _value, state), do: %{state | notes: [state.draft | state.notes], draft: ""}
end
```

1. After each event, Elixir renders the tree again and compares it with the last one. It
   sends only the changes to the native side.
2. The native side keeps the tree in an observable model and renders each node with one
   generic SwiftUI or Compose view per node type. When the tree changes, the platform
   updates only the views that changed, with its own animations.
3. A tap, a text edit or a toggle goes back to Elixir as an event with the node's event
   name and value.

Text a user is typing stays in the native field. Elixir gets the edits, and the native field
keeps its own cursor and selection, so typing never waits on a round trip.

## Parts to build

| Part | What it is |
| --- | --- |
| The bridge | Messages both ways between the BEAM and the native side: tree changes down, events up. `cauldron_native` already sends touches, controllers, the screen and app life to Elixir, and pictures to the screen; this adds a general message channel on the same mechanism. |
| The node set | The controls both platforms have, under one name each: text, image, button, text field, secure field, toggle, slider, stepper, picker, date picker, progress, list and its sections, stacks, scroll, grid, navigation stack and links, tab bar, sheet, alert, confirmation, menu, toolbar items. Each takes the common properties (padding, spacing, font style, colour role, accessibility label and hint) and may take properties that only one platform has. |
| `CauldronNative.App` | The behaviour an app implements (`mount/1`, `render/1`, `handle_event/3`, `handle_info/2`), the functions that build nodes, and the process that renders, compares trees and sends changes. |
| The SwiftUI renderer | An observable tree and one SwiftUI view per node type, in the iOS shell `cauldron_native` already builds. |
| The Compose renderer | The same in Compose, in the Android shell. |
| A canvas node | A game's view as one node inside the native tree, so a game can use native menus and settings around its picture, and an app can show a drawn view inside native screens. |
| Platform services | Elixir functions for what apps ask the system for: permissions, notifications, sharing, opening links, the camera and photo library, secure storage (Keychain, Keystore), files, background work. |
| Store requirements | The build writes what review needs: app icons and a launch screen from one picture, the privacy manifest and the permission usage strings from the app's config, and the platform settings for release builds. |

## Going beyond the stock controls

Built-in controls and an app's own are registered the same way, so an app moves from one to
the other a piece at a time and never forks the renderer.

1. **Stock controls, from Elixir.** The node set above.
2. **Platform modifiers, from Elixir.** Every node takes a `modifiers:` list of the
   platform's own adjustments by name, such as `padding`, `font`, `foreground`, `frame`,
   `corner_radius`, and ones only one platform has, such as a SwiftUI list style or a
   Material colour role, kept under `ios:` or `android:`. A renderer applies the ones it
   knows and passes over the rest.
3. **The app's own native views.** An app keeps SwiftUI views in `native/ios/` and Compose
   views in `native/android/`, each registered under a name. Elixir places it like any node,
   `native(:map_view, region: region, on_select: :picked)`: properties go down as the view's
   input, and the view sends events up by name. The build compiles these files into the app,
   so Xcode and Android Studio are not needed.
4. **The generated projects, opened in the platform tools.** The build writes a real Xcode
   project and a real Gradle project; opening them gives SwiftUI previews, the layout
   inspector, the debugger and Instruments. The source stays in `native/` and in Elixir, so a
   rebuild keeps every change made there.
5. **Cauldron inside a native app.** For an app whose shell is Swift or Kotlin, Cauldron
   ships as a library the app's own project adds; its code owns the app and Elixir runs the
   logic or chosen screens.

## Order

1. The bridge, the `CauldronNative.App` behaviour, a first node set (text, button, text
   field, toggle, list, stacks, navigation), platform modifiers and the app's own native
   views, on both platforms, with an example app running on an iPhone and an Android device.
2. The rest of the node set, accessibility properties, and sheets, alerts and menus.
3. Platform services, starting with permissions, notifications, sharing and secure storage.
4. The store requirements in the build, and a release build of the example on TestFlight and
   an internal test track.
5. The canvas node, and a game's menus and settings in native views.
6. Cauldron as a library inside a native app's own project.

## The renderers are Cauldron's own

LiveView Native (DockYard) drove SwiftUI and Jetpack Compose from a Phoenix server. Its
core repository was archived in February 2026 and its native clients have no 2026
releases, so Cauldron has renderers of its own: `native/ios/UI.swift` and
`native/android/kotlin/CauldronUi.kt` in `cauldron_native`.

## Where it stands

As of 2026-10-23, steps 1, 2 and 3 are done.

* `CauldronNative.App`, `CauldronNative.UI` and `CauldronNative.UI.Tree` in Elixir; the
  patch and event bridge in the NIF; the SwiftUI and Compose renderers; platform
  modifiers; the app's own views from `native/ios` and `native/android`, with a generated
  registry; a window per app kind (status bar, light and dark) on both platforms.
* `cauldron_examples/apps/notes` runs on an Android emulator: adding notes, typing at
  speed, a pushed screen with the system back gesture, a toggle, the app's own star view
  in Kotlin, light and dark mode. On an iPhone it builds, installs and draws in SwiftUI.
* The Android build uses Compose BOM 2026.01.01 and Kotlin 2.3.21: later Compose needs
  the Android Gradle plugin 9.1 and compile SDK 37, a move of the whole Android build.
* Step 2: icons (SF Symbols and Material icons by shared names), images from the app and
  the web, labels, links, menus, chips, pickers (menu, segments, wheel, rows), date and
  time pickers, steppers, progress, many-line text, cards, grids, expandable sections,
  tabs, toolbars, search, sheets, alerts and action sheets. Pickers, tabs and dates give
  the app its own terms back (`CauldronNative.UI.Value`).
* `cauldron_examples/apps/catalog` shows every control: each screen checked on an
  Android emulator (Material 3) and on an iPhone on iOS 26 (SwiftUI, with the system's
  glass tab bar and toolbar).
* Android apps use the network, resolving names with Elixir's own resolver against the
  network's DNS servers at launch.
* Step 3: `CauldronNative.Device` (haptics, photo and document pickers, the system
  camera, microphone recording, permissions, the share sheet, opening addresses, audio
  in the background with lock-screen controls), the `video` and `camera_preview`
  controls, permissions and background audio in the app's config, and tabs that become a
  sidebar on an iPad and a navigation rail on a large Android screen. The catalog's
  "Media and device" screen uses each, and its settings moved to a sheet from the
  toolbar.
* Since: location readings and watching, notifications (scheduled, tapped, push through
  APNs and Firebase), charts and maps, the accessibility hint on Android, DNS servers
  followed as the network changes, and what the stores require (icon, launch screen,
  build number, privacy manifest, export compliance, release builds and the Play upload
  key; the guide "Publishing"). The catalog shows them on Android and iOS, apart from push,
  which needs an app's own Apple and Firebase accounts, and the Android map, which needs a
  Google Maps key.
* 2026-10-24: foldables (`:posture` events from the iPhone Duo's hinge and Android's
  WindowManager), Apple's simulators (`--simulator`), tvOS apps and macOS apps, from the
  same SwiftUI renderer with each system's own window, screen and pickers
  (`native/macos` for AppKit). The catalog's "Folding" screen was checked on the iPhone
  Duo simulator (closed) and a Pixel 9 Pro Fold emulator (open, half open, closed); the
  catalog runs on the Apple TV simulator and as a Mac app, and beast runs as a Mac app.
* Not yet: an app inside an existing Xcode or Android Studio project, and a game view
  inside an app's native screens (the canvas node).
