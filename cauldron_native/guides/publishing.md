# Publishing

This guide takes an app from a development build to the App Store and Google Play.
Cauldron builds what each store requires: the icon, the launch screen, the privacy
manifest, the build number, and a store build signed for upload. The accounts, the
store listings and the review are yours: each app is published by the person or company
whose name is on it.

## What Cauldron does and what you do

| Cauldron | You |
| --- | --- |
| Writes the icon in every form each platform needs, from one PNG | Draw the icon |
| Writes the launch screen | Choose its colour and image |
| Writes the permission reasons into `Info.plist` and the Android manifest | Write a reason for each permission |
| Writes iOS's privacy manifest, with the reasons for the system interfaces the runtime uses | Say what data your app collects |
| Answers the export compliance question in `Info.plist` | Say whether your app uses non-standard encryption |
| Builds and signs the `.ipa` and the `.aab` | Hold the Apple team and the upload key |
| | Make the store listings, screenshots and privacy policy, and upload |

## Before the first build

### Accounts

* **Apple:** an [Apple Developer Program](https://developer.apple.com/programs/)
  membership (a paid team; a free personal team installs on your own devices only), and
  the app's record in [App Store Connect](https://appstoreconnect.apple.com) under its
  bundle identifier (the app's `:id`).
* **Google:** a [Google Play Console](https://play.google.com/console) developer account,
  and the app created there. Turn on Play App Signing when asked: Google keeps the key
  that signs what users install, and you keep an upload key.

### The upload key (Google Play)

```
export CAULDRON_ANDROID_STORE_PASSWORD=…
export CAULDRON_ANDROID_KEY_PASSWORD=…
mix cauldron_native.upload_key --keystore ~/keys/my_app.jks --name "Example Ltd"
```

Keep the keystore and its passwords out of the repository, and back them up: every
later update must be signed with the same key.

### The config

```elixir
cauldron_native: [
  name: "My App",
  id: "com.example.myapp",
  build: 7,
  icon: "assets/icon.png",
  icon_background: "#1E2A44",
  launch: [background: "#1E2A44", image: "assets/logo.png"],
  permissions: [camera: "Takes photos for your notes"],
  privacy: [
    tracking: false,
    collects: [
      email: [linked: true, purposes: [:app_functionality]],
      crash_data: [linked: false, purposes: [:analytics]]
    ]
  ],
  encryption: :exempt,
  android_signing: [keystore: "~/keys/my_app.jks", alias: "upload"]
]
```

* **`:icon`** is a 1024 × 1024 PNG with no alpha channel; the build refuses any other.
  iOS rounds its corners. Android shows it inset on `:icon_background` as an adaptive
  icon, so keep what matters away from the edges.
* **`:build`** must be larger for every upload to either store. The version (the
  project's `:version`) is what users see; the build number tells uploads apart.
* **`:privacy`** lists what the app collects and why; `CauldronNative.Build.Privacy`
  names the types and purposes. Answer App Store Connect's App Privacy questions and
  Google Play's Data safety form the same way. Collecting nothing is
  `privacy: [tracking: false, collects: []]`.
* **`:encryption`** stays `:exempt` when the app only uses HTTPS, TLS or the system's
  own encryption. Otherwise set `:non_exempt` and complete App Store Connect's export
  compliance documents.
* **`:notification_icon`** (Android) is a white-on-transparent PNG for the status bar,
  if the app shows notifications.

## Building for the stores

```
mix cauldron_native.build ios --release --team ABCDE12345
mix cauldron_native.build android --release
```

* **iOS** archives the app, signs it for distribution with the team, and exports an
  `.ipa` for App Store Connect. Upload it with the Transporter app, Xcode's Organizer
  (Window → Organizer, after opening the archive), or `xcrun altool --upload-app` with an
  App Store Connect API key.
* **Android** builds an Android App Bundle (`.aab`) signed with the upload key. Upload it
  in the Play Console under Test and release; start with an internal testing track.

## The App Store

Apple reviews each version against the
[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/). Points
that apply to apps made with Cauldron:

* **Native screens.** Apps built with `CauldronNative.App` use SwiftUI's own controls,
  which follow the
  [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
  for navigation, tab bars, sheets, text sizes and dark mode. Lay screens out as iOS apps
  do: settings in a sheet or a screen rather than a tab, one tab bar at most.
* **Permissions.** Ask for a permission when the user reaches the feature that needs
  it, not at launch, and write reasons that say what the user gets.
* **Accounts.** An app that lets users make an account must let them delete it from
  inside the app; an app that offers sign-in through another company must also offer
  Sign in with Apple.
* **Purchases.** Digital goods and subscriptions sold in the app go through Apple's
  in-app purchase.
* **Listing.** Screenshots for the iPhone sizes App Store Connect asks for (and iPad,
  as the app runs there), a description, keywords, a support URL and a privacy policy
  URL. The age rating questionnaire and the App Privacy answers are required.
* **Review.** Give the reviewers a demo account if the app needs signing in, and notes
  on anything they cannot reach otherwise.

## Google Play

Google checks each release against the
[Developer Program Policies](https://play.google.com/about/developer-content-policy/).

* **Target API level.** Cauldron builds against Android 16 (API 36), which meets
  Google Play's current requirement.
* **Data safety.** Answer the Data safety form to match `:privacy`, including data a
  library collects (Firebase for push, Google Maps).
* **Permissions.** Location, the camera, the microphone and notifications are asked for
  at the moment of use. Background location and exact alarms are not requested by
  Cauldron; an app that needs them makes its case in the Play Console.
* **Listing.** A 512 × 512 icon, a 1024 × 500 feature graphic, phone screenshots (and
  tablet ones, as the app adapts to large screens), a short and a full description, the
  content rating questionnaire, the target audience, and a privacy policy URL.
* **Testing.** A new personal developer account must run a closed test with testers
  before its first production release; the Play Console says how many and for how long.

## Push notifications and maps

These need accounts of the app's own:

* **Push on iOS:** `push: [ios: true]` adds the push entitlement; the App ID must have
  Push Notifications turned on in the Apple Developer account, and the app's server
  sends through APNs with a key from the same account.
* **Push on Android:** make a Firebase project, add the Android app with the app's
  `:id`, download its `google-services.json`, and name it: `push: [android:
  "config/google-services.json"]`. The server sends through Firebase Cloud Messaging.
* **Maps on Android:** make a Google Maps Platform API key restricted to the app's
  package and signing certificates (the upload key's and Play App Signing's), and give it
  as `maps: [android_key: {:env, "MAPS_API_KEY"}]`. iOS maps need no key.

## Each update

1. Raise `:build`, and the project's `:version` when the change is one users should see.
2. `mix cauldron_native.build ios --release` and `mix cauldron_native.build android --release`.
3. Upload both, add the release notes, and submit for review.
