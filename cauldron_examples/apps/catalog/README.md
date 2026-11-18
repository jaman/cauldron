# Catalog

Every control of `CauldronNative.UI` on one app, as the platforms' own component catalogs
show theirs: SwiftUI on iOS, Jetpack Compose with Material 3 on Android. A Catalog tab
lists twelve screens (text and icons, buttons and menus, text input, selection, dates
and times, progress, lists, layout, sheets and alerts, images, media and the phone's
services, and a view of the app's own), beside a Gallery tab of pictures from the web;
the settings open in a sheet from the toolbar. The media screen asks for each
permission the app names in `mix.exs`, plays audio on with the screen locked, and shows
the photos, videos and files it is handed.

```
mix cauldron_native.build ios --team ABCDE12345 --run
mix cauldron_native.build android --run
```

`lib/catalog/app.ex` holds the state and events, `lib/catalog/screens.ex` the screens,
and `native/ios/Meter.swift` and `native/android/Meter.kt` the meter drawn by each
platform. Started with `CATALOG_OPEN` set to a screen's name (`buttons`, `selection`,
`presentation`, …) the app opens on that screen.
