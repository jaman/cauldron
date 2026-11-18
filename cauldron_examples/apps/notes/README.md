# Notes

An app with the platform's own controls, written in Elixir: SwiftUI on iOS, Jetpack Compose
with Material 3 on Android (`CauldronNative.App`). It keeps a list of notes with a field to
add one, a screen to edit a note and rate it, and a settings screen. The star rating is a
view of the app's own, `native/ios/Rating.swift` and `native/android/Rating.kt`, placed
with `native(:rating, ...)`.

```
mix cauldron_native.build ios --team ABCDE12345 --run
mix cauldron_native.build android --run
```

`lib/notes/app.ex` is the whole app.
