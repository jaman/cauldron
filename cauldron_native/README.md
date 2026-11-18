# CauldronNative

This package builds an Elixir project as an iOS, tvOS, macOS or Android app. The app
starts the Erlang runtime inside its own process and boots your release. A small native bridge,
`CauldronNative`, gives your code the screen: it shows a picture and draws shapes over it,
and receives touches, the screen's size, game controllers and the app's lifecycle.

An app that is not a game shows the platform's own controls: SwiftUI on iOS, Apple TV
and the Mac, Jetpack Compose on Android. Its screens are written in Elixir
(`CauldronNative.App`, `CauldronNative.UI`), and the platform draws them, so they look and behave as the
device's own apps do, VoiceOver and TalkBack included. A `cauldron_2d` game plays on a
phone through `cauldron_2d_native` with no code of its own. Anything else uses
`CauldronNative` directly.

```
mix cauldron_native.build ios --team ABCDE12345 --run
mix cauldron_native.build android --run
```

The [Mobile releases guide](https://hexdocs.pm/cauldron_native/building_apps.html)
covers what you need installed, setting up a project, signing for iOS, what works on the
device, linking native code, and troubleshooting. In this repository it is
[`guides/building_apps.md`](guides/building_apps.md).

## Installation

```elixir
def deps do
  [
    {:cauldron_native, "~> 0.1", runtime: Mix.target() in [:ios, :tvos, :macos, :android]}
  ]
end
```

Describe the app in the project's config:

```elixir
cauldron_native: [name: "My Game", id: "com.example.mygame"]
```

The first build for each platform cross-compiles OpenSSL and OTP, which takes several
minutes. Later builds reuse them from `~/.cache/cauldron_native`.

## An app with native controls

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

In `config/config.exs`:

```elixir
config :cauldron_native, app: Counter.App
```

Views of the app's own, written in Swift under `native/ios` and in Kotlin under
`native/android`, are placed with `CauldronNative.UI.native/2`
(`CauldronNative.Build.NativeViews`). The guide's "Apps with native controls" covers the
controls, events and modifiers.

## Examples

`cauldron_examples/apps/notes` in the Cauldron repository is an app with native
controls and a view of its own on each platform; `cauldron_examples/games/beast` is a
game. Both build for both platforms.

## License

[AGPL-3.0-only](LICENSE). You may use, study, change and share it under the AGPL at
no cost.

A game or service whose source you do not publish needs a
[commercial license](COMMERCIAL.md).
