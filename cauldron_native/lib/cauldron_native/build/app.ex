defmodule CauldronNative.Build.App do
  @moduledoc """
  An app's description, from the `:cauldron_native` key of the project's config:

      def project do
        [
          app: :my_game,
          version: "1.2.0",
          releases: [my_game: [include_erts: false]],
          cauldron_native: [name: "My Game", id: "com.example.mygame"]
        ]
      end

  Keys:

    * `:name` — the name under the icon. Required
    * `:id` — the bundle identifier (iOS) and application id (Android), reverse-DNS.
      Required
    * `:release` — the release to put in the app. Default: the project's app
    * `:team` — the Apple development team that signs the iOS app; the
      `CAULDRON_NATIVE_TEAM` environment variable or `--team` overrides it
    * `:emulator_flags` — more emulator flags, as `erl` would pass them to the
      emulator (`"-S", "2:2"` rather than `"+S", "2:2"`). Default `[]`
    * `:orientation` — `:landscape`, `:portrait` or `:any`, the ways the app may be
      turned. Default `:landscape`
    * `:files` — `[{from, to}]`, folders or files of this machine copied into the app
      beside the release, `to` relative to it: data a game reads that is not in its
      `priv`, such as downloaded models. Default `[]`
    * `:native` — the folder of the app's own native views, Swift in its `ios` folder and
      Kotlin in its `android` folder (`CauldronNative.Build.NativeViews`). Default `"native"`
    * `:env` — environment variables set before the BEAM starts, `$ROOT` in a value
      standing for the release's folder in the app and `$HOME` for the app's writable
      folder: `%{"MY_DATA" => "$ROOT/data"}`. Default `%{}`
    * `:permissions` — what the app may ask the phone for (`CauldronNative.Device`), each
      with the reason the phone shows when it asks: `[camera: "Takes photos of your
      notes", microphone: "Records voice notes", photos: "Saves your drawings", location:
      "Finds trucks near you", notifications: "Tells you when an order is ready"]`. iOS
      shows the reason; Android asks in the system's own words. Default `[]`
    * `:background_audio` — `true` lets `CauldronNative.Device.play/3` go on with the
      screen off, shown on the lock screen. Default `false`
    * `:push` — push notifications (`CauldronNative.Notifications.register_push/1`):
      `ios: true` for Apple's push service, `android:` the path of the Firebase project's
      `google-services.json` for Firebase Cloud Messaging. Default `[]`
    * `:widgets` — the app's Home Screen widgets (`CauldronNative.Widget`), each `kind:
      [name: "Orders", description: "Orders waiting", sizes: [:small, :medium]]`, sizes
      among `:small`, `:medium`, `:large` and `:extra_large`, and the Lock Screen's
      `:circular`, `:rectangular` and `:inline` (iOS only; Android leaves out a kind with
      no other size). On iOS they are a WidgetKit
      extension sharing an App Group with the app. Default `[]`
    * `:live_activities` — `true` lets the app start Live Activities
      (`CauldronNative.LiveActivity`). Default `false`
    * `:purchases` — the products the app sells (`CauldronNative.Purchases`), each `key:
      [type: :non_consumable, name: "Pro", price: "4.99", description: "…"]`, type
      among `:consumable`, `:non_consumable` and `:subscription`, a subscription with a
      `:period` among `:week`, `:month`, `:two_months`, `:quarter`, `:half_year` and
      `:year`, and maybe an introductory offer, `intro: [price: "2.49", period: :month,
      periods: 3, mode: :pay_as_you_go]` (`mode` among `:pay_as_you_go`, `:pay_up_front`
      and `:free`). The name, price, offer and description are the Xcode project's
      StoreKit testing configuration's; the stores' own come from App Store Connect and
      the Play Console. Default `[]`
    * `:background_refresh` — `true` lets the system wake the app for
      `CauldronNative.Background`'s refreshes: on iOS and tvOS it declares the refresh
      task and the `fetch` background mode. Default `false`
    * `:url_schemes` — the schemes of the links that open the app, such as
      `["nowinandroid"]` for `nowinandroid://topic/ui`; each link arrives as
      `{:cauldron_native, :url, url}`. Default `[]`
    * `:weatherkit` — `true` gives the Apple app WeatherKit's entitlement, so
      `CauldronNative.Weather` asks Apple Weather first. Signing it needs a paid Apple
      Developer Program team whose App ID has the WeatherKit capability. Default `false`:
      the app's weather comes from Open-Meteo
    * `:assets` — an Xcode asset catalog (a `.xcassets` folder) of the app's own images,
      colours and symbols, for its native views, its widgets and
      `CauldronNative.UI.image/2`; Android takes it converted
      (`CauldronNative.Build.Assets`). Default: none
    * `:window` — the Mac window's size in points when it first opens and the least it
      may be made: `[width: 1000, height: 650, min_width: 600, min_height: 450]`.
      Default `[width: 1100, height: 760, min_width: 480, min_height: 360]`
    * `:maps` — `android_key:` the Google Maps API key Android's maps need
      (`CauldronNative.UI.map/1`), as text or `{:env, "VARIABLE"}` to read it from the
      environment when building. iOS maps need no key. Default `[]`

  Keys for the stores (the guide's "Publishing" covers each):

    * `:icon` — a 1024 × 1024 PNG without transparency, the app's icon on both
      platforms; Android shows it inset on `:icon_background` (`"#rrggbb"`, default
      `"#ffffff"`), as its adaptive icons are, and Apple TV centred on it
      (`CauldronNative.Build.TvIcon`). A release build requires it
    * `:launch` — what shows while the app starts: `background:` a colour
      (`"#rrggbb"`) and `image:` a PNG drawn at its centre. Default: the system's
      background colour and the icon on Android
    * `:notification_icon` — Android's small notification icon: a PNG, white on
      transparent, about 96 × 96. Default: the system's bell
    * `:build` — the build number each store upload needs larger than the last.
      Default: the version code below
    * `:privacy` — what the app collects, for iOS's privacy manifest
      (`CauldronNative.Build.Privacy`). Default: collects nothing, no tracking
    * `:encryption` — `:exempt` (default) when the app's only encryption is the
      system's or standard protocols such as HTTPS and TLS, which App Store Connect's
      export compliance question then needs no answer for; `:non_exempt` otherwise
    * `:android_signing` — `keystore:` the upload key's keystore and `alias:` its key,
      for a release build; the passwords come from the `CAULDRON_ANDROID_STORE_PASSWORD`
      and `CAULDRON_ANDROID_KEY_PASSWORD` environment variables. Without it, the
      `CAULDRON_ANDROID_KEYSTORE` and `CAULDRON_ANDROID_KEY_ALIAS` (default `upload`)
      environment variables name the key, as a build machine gives them
      (`mix cauldron_native.upload_key` makes one)

  An app that names a `CauldronNative.App` (`config :cauldron_native, app: ...`) shows the
  platform's own controls: its window keeps the status bar and follows the device's light
  or dark setting. Without one, the app is a game's full screen.

  The version is the project's `:version`; Android's version code is made from it as
  `major * 1_000_000 + minor * 1_000 + patch`.
  """

  alias CauldronNative.Build.Privacy

  @enforce_keys [:name, :id, :release, :version]
  defstruct @enforce_keys ++
              [
                team: nil,
                emulator_flags: [],
                orientation: :landscape,
                files: [],
                env: %{},
                native: "native",
                native_ui?: false,
                permissions: [],
                background_audio: false,
                push: %{ios: false, android: nil},
                weatherkit: false,
                url_schemes: [],
                background_refresh: false,
                widgets: [],
                live_activities: false,
                purchases: [],
                maps_key: nil,
                assets: nil,
                window: %{width: 1100, height: 760, min_width: 480, min_height: 360},
                icon: nil,
                icon_background: "#ffffff",
                notification_icon: nil,
                launch: %{background: nil, image: nil},
                build: nil,
                privacy: [],
                encryption: :exempt,
                android_signing: nil
              ]

  @type t :: %__MODULE__{
          name: String.t(),
          id: String.t(),
          release: atom(),
          version: String.t(),
          team: String.t() | nil,
          emulator_flags: [String.t()],
          orientation: :landscape | :portrait | :any,
          files: [{String.t(), String.t()}],
          env: %{String.t() => String.t()},
          native: String.t(),
          native_ui?: boolean(),
          permissions: keyword(String.t()),
          background_audio: boolean(),
          push: %{ios: boolean(), android: String.t() | nil},
          weatherkit: boolean(),
          url_schemes: [String.t()],
          background_refresh: boolean(),
          widgets: [%{kind: atom(), name: String.t(), description: String.t(), sizes: [atom()]}],
          live_activities: boolean(),
          purchases: [
            %{
              key: atom(),
              type: :consumable | :non_consumable | :subscription,
              name: String.t(),
              price: String.t(),
              description: String.t(),
              period: atom() | nil,
              intro:
                %{mode: atom(), period: atom(), periods: pos_integer(), price: String.t()}
                | nil
            }
          ],
          maps_key: String.t() | nil,
          assets: String.t() | nil,
          window: %{width: number(), height: number(), min_width: number(), min_height: number()},
          icon: String.t() | nil,
          icon_background: String.t(),
          notification_icon: String.t() | nil,
          launch: %{background: String.t() | nil, image: String.t() | nil},
          build: pos_integer() | nil,
          privacy: keyword(),
          encryption: :exempt | :non_exempt,
          android_signing: %{keystore: String.t(), alias: String.t()} | nil
        }

  @doc "The current project's app."
  @spec from_project!() :: t()
  def from_project! do
    config = Mix.Project.config()

    mobile =
      Keyword.get(config, :cauldron_native) ||
        Mix.raise("The project has no :cauldron_native config")

    %__MODULE__{
      name: Keyword.get(mobile, :name) || Mix.raise(":cauldron_native needs a :name"),
      id: Keyword.get(mobile, :id) || Mix.raise(":cauldron_native needs an :id"),
      release: Keyword.get(mobile, :release, config[:app]),
      version: config[:version],
      team: Keyword.get(mobile, :team),
      emulator_flags: Keyword.get(mobile, :emulator_flags, []),
      orientation: Keyword.get(mobile, :orientation, :landscape),
      files:
        mobile
        |> Keyword.get(:files, [])
        |> Enum.map(fn {from, to} -> {Path.expand(from), to} end),
      env: Keyword.get(mobile, :env, %{}),
      native: mobile |> Keyword.get(:native, "native") |> Path.expand(),
      native_ui?: Application.get_env(:cauldron_native, :app) != nil,
      permissions: permissions!(Keyword.get(mobile, :permissions, [])),
      background_audio: Keyword.get(mobile, :background_audio, false),
      push: push!(Keyword.get(mobile, :push, [])),
      weatherkit: Keyword.get(mobile, :weatherkit, false),
      url_schemes: Keyword.get(mobile, :url_schemes, []),
      background_refresh: Keyword.get(mobile, :background_refresh, false),
      widgets: widgets(Keyword.get(mobile, :widgets, [])),
      live_activities: Keyword.get(mobile, :live_activities, false),
      purchases: purchases!(Keyword.get(mobile, :purchases, [])),
      maps_key: mobile |> Keyword.get(:maps, []) |> Keyword.get(:android_key) |> secret(),
      assets: assets!(Keyword.get(mobile, :assets)),
      window: window(Keyword.get(mobile, :window, [])),
      icon: optional_path(Keyword.get(mobile, :icon)),
      icon_background: colour!(Keyword.get(mobile, :icon_background, "#ffffff")),
      notification_icon: optional_path(Keyword.get(mobile, :notification_icon)),
      launch: launch!(Keyword.get(mobile, :launch, [])),
      build: Keyword.get(mobile, :build),
      privacy: Privacy.validate!(Keyword.get(mobile, :privacy, [])),
      encryption: encryption!(Keyword.get(mobile, :encryption, :exempt)),
      android_signing: signing!(Keyword.get(mobile, :android_signing))
    }
  end

  @doc "The build number: the app's `:build`, or the version code of its version."
  @spec build_number(t()) :: pos_integer()
  def build_number(%__MODULE__{build: nil, version: version}), do: version_code(version)
  def build_number(%__MODULE__{build: build}), do: build

  @widget_sizes [:small, :medium, :large, :extra_large, :circular, :rectangular, :inline]

  defp widgets(widgets) do
    for {kind, options} <- widgets do
      sizes = Keyword.get(options, :sizes, [:small, :medium])

      unless sizes != [] and Enum.all?(sizes, &(&1 in @widget_sizes)),
        do:
          Mix.raise(
            ":widgets' #{kind} has sizes #{inspect(sizes)}, which must be among #{inspect(@widget_sizes)}"
          )

      %{
        kind: kind,
        name: Keyword.fetch!(options, :name),
        description: Keyword.get(options, :description, ""),
        sizes: sizes
      }
    end
  end

  @purchase_types [:consumable, :non_consumable, :subscription]
  @periods [:week, :month, :two_months, :quarter, :half_year, :year]

  defp purchases!(purchases), do: Enum.map(purchases, &purchase!/1)

  @intro_modes [:pay_as_you_go, :pay_up_front, :free]

  defp intro!(_key, nil), do: nil

  defp intro!(key, intro) do
    mode = Keyword.get(intro, :mode, :pay_as_you_go)
    period = Keyword.fetch!(intro, :period)

    unless mode in @intro_modes and period in @periods,
      do:
        Mix.raise(
          ":purchases' #{key} :intro needs a :mode among #{inspect(@intro_modes)} and a :period among #{inspect(@periods)}"
        )

    %{
      mode: mode,
      period: period,
      periods: Keyword.get(intro, :periods, 1),
      price: intro |> Keyword.get(:price, "0") |> to_string()
    }
  end

  defp purchase!({key, options}) do
    type = Keyword.fetch!(options, :type)
    period = Keyword.get(options, :period)

    unless type in @purchase_types,
      do:
        Mix.raise(
          ":purchases' #{key} has type #{inspect(type)}, not one of #{inspect(@purchase_types)}"
        )

    if type == :subscription and period not in @periods,
      do:
        Mix.raise(
          ":purchases' #{key} is a subscription and needs a :period among #{inspect(@periods)}"
        )

    %{
      key: key,
      type: type,
      name: Keyword.get(options, :name, Atom.to_string(key)),
      price: options |> Keyword.get(:price, "0.99") |> to_string(),
      description: Keyword.get(options, :description, ""),
      period: period,
      intro: intro!(key, Keyword.get(options, :intro))
    }
  end

  defp push!(push) do
    android = optional_path(Keyword.get(push, :android))

    if android && not File.regular?(android),
      do: Mix.raise(":push's android file #{android} does not exist")

    %{ios: Keyword.get(push, :ios, false), android: android}
  end

  defp secret({:env, name}), do: System.get_env(name)
  defp secret(value), do: value

  defp window(window),
    do:
      Map.merge(
        %{width: 1100, height: 760, min_width: 480, min_height: 360},
        Map.new(Keyword.take(window, [:width, :height, :min_width, :min_height]))
      )

  defp assets!(nil), do: nil

  defp assets!(path) do
    catalog = Path.expand(path)

    unless Path.extname(catalog) == ".xcassets" and File.dir?(catalog),
      do:
        Mix.raise(
          ":assets is an Xcode asset catalog, a .xcassets folder, not lib/cauldron_native/build/app.ex"
        )

    catalog
  end

  defp optional_path(nil), do: nil
  defp optional_path(path), do: Path.expand(path)

  defp colour!("#" <> hex = colour) when byte_size(hex) == 6, do: colour
  defp colour!(other), do: Mix.raise("A colour is \"#rrggbb\", not #{inspect(other)}")

  defp launch!(launch),
    do: %{
      background: launch |> Keyword.get(:background) |> optional_colour(),
      image: optional_path(Keyword.get(launch, :image))
    }

  defp optional_colour(nil), do: nil
  defp optional_colour(colour), do: colour!(colour)

  defp encryption!(value) when value in [:exempt, :non_exempt], do: value

  defp encryption!(other),
    do: Mix.raise(":encryption is :exempt or :non_exempt, not #{inspect(other)}")

  defp signing!(nil) do
    case System.get_env("CAULDRON_ANDROID_KEYSTORE") do
      nil ->
        nil

      keystore ->
        signing!(
          keystore: keystore,
          alias: System.get_env("CAULDRON_ANDROID_KEY_ALIAS", "upload")
        )
    end
  end

  defp signing!(signing),
    do: %{
      keystore: Path.expand(Keyword.fetch!(signing, :keystore)),
      alias: Keyword.fetch!(signing, :alias)
    }

  @permissions [:camera, :microphone, :photos, :location, :notifications]

  defp permissions!(permissions) do
    for {name, reason} <- permissions do
      unless name in @permissions and is_binary(reason),
        do: Mix.raise(":permissions takes #{inspect(@permissions)}, each with its reason as text")

      {name, reason}
    end
  end

  @doc "Android's integer version code for `version`."
  @spec version_code(String.t()) :: pos_integer()
  def version_code(version) do
    %Version{major: major, minor: minor, patch: patch} = Version.parse!(version)
    max(1, major * 1_000_000 + minor * 1_000 + patch)
  end
end
