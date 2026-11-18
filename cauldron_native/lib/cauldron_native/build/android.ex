defmodule CauldronNative.Build.Android do
  @moduledoc """
  The Android app: `libcauldron_app.so` linked with the NDK from the emulator, the
  NIFs and this package's JNI glue (`native/android/c_src`), and a Gradle project
  generated under the build folder around the Java activity from
  `native/android/java`, with the release zipped into the APK's assets. The activity
  unpacks the release into the app's files on the first start after an update.

  `apk!/4` builds a debug APK, signed with the SDK's debug key; `install!/2` and
  `run!/2` use `adb` with the first device it lists, an emulator or a phone with USB
  debugging on. `bundle!/4` builds the Android App Bundle for Google Play, signed with
  the app's upload key (`:android_signing`).

  The project carries the app's adaptive icon and launch screen, and, when the app's
  config asks for them, Firebase Cloud Messaging (`:push`) and Google Maps (`:maps`).
  """

  alias CauldronNative.Build.{AndroidWidgets, App, Assets, NativeViews, Platform, Shell}

  @gradle "8.14.3"

  @type linked :: %{objects: [String.t()], archives: [String.t()], ldflags: [String.t()]}

  @doc "Link the app's shared library for `platform` into `folder`; its path."
  @spec library!(Platform.t(), String.t(), String.t(), linked()) :: String.t()
  def library!(platform, source, folder, linked) do
    File.mkdir_p!(folder)
    library = Path.join(folder, "libcauldron_app.so")
    [cc | cc_arguments] = String.split(platform.cc)

    Shell.run!(
      cc,
      cc_arguments ++
        String.split(platform.cflags) ++
        [
          "-shared",
          "-o",
          library,
          "-I" <> Path.join(source, "c_src"),
          Path.join(source, "native/android/c_src/android.c")
        ] ++
        linked.objects ++
        linked.archives ++
        linked.ldflags ++
        ~w(-landroid -llog -lm -ldl -lc++_static -lc++abi -Wl,-z,max-page-size=16384 -Wl,--no-undefined),
      log: Path.join(folder, "link.log")
    )

    library
  end

  @doc "Write the Gradle project for `app` into `folder` and build its debug APK; the APK's path."
  @spec apk!(App.t(), String.t(), String.t(), %{library: String.t(), release: String.t()}) ::
          String.t()
  def apk!(app, source, folder, %{library: library, release: release}) do
    gradle!(app, source, folder, library, release, "assembleDebug", [])
    Path.join(folder, "app/build/outputs/apk/debug/app-debug.apk")
  end

  @doc """
  Write the Gradle project for `app` into `folder` and build its release App Bundle,
  signed with the upload key the app's `:android_signing` names; the bundle's path.
  Raises when the app has no `:android_signing` or icon, or the passwords are not in
  `CAULDRON_ANDROID_STORE_PASSWORD` and `CAULDRON_ANDROID_KEY_PASSWORD`.
  """
  @spec bundle!(App.t(), String.t(), String.t(), %{library: String.t(), release: String.t()}) ::
          String.t()
  def bundle!(app, source, folder, %{library: library, release: release}) do
    if app.icon == nil, do: Mix.raise(":icon is required for a Google Play build")
    gradle!(app, source, folder, library, release, "bundleRelease", signing_env!(app))
    Path.join(folder, "app/build/outputs/bundle/release/app-release.aab")
  end

  defp gradle!(app, source, folder, library, release, task, env) do
    log = Path.join(folder, "gradle.log")
    File.mkdir_p!(folder)
    unless File.exists?(Path.join(folder, "gradlew")), do: wrapper!(folder, log)
    project!(app, source, folder, library, release)

    Shell.run!(Path.join(folder, "gradlew"), ["--no-daemon", task],
      cd: folder,
      log: log,
      env: [{"ANDROID_HOME", Platform.android_sdk()} | env]
    )
  end

  defp signing_env!(%App{android_signing: nil}),
    do:
      Mix.raise(
        "A Google Play build needs :android_signing, the upload key's keystore and alias; mix cauldron_native.upload_key makes one"
      )

  defp signing_env!(%App{android_signing: signing}) do
    unless File.regular?(signing.keystore),
      do: Mix.raise("The upload keystore #{signing.keystore} does not exist")

    passwords =
      for name <- ["CAULDRON_ANDROID_STORE_PASSWORD", "CAULDRON_ANDROID_KEY_PASSWORD"] do
        {name, System.get_env(name) || Mix.raise("#{name} is not set")}
      end

    [
      {"CAULDRON_ANDROID_KEYSTORE", signing.keystore},
      {"CAULDRON_ANDROID_KEY_ALIAS", signing.alias}
    ] ++
      passwords
  end

  @doc "The serial of the first device `adb` lists, or `nil`."
  @spec device() :: String.t() | nil
  def device do
    adb()
    |> Shell.output!(["devices"])
    |> String.split("\n")
    |> Enum.drop(1)
    |> Enum.find_value(fn line ->
      case String.split(line, "\t") do
        [serial, "device"] -> serial
        _other -> nil
      end
    end)
  end

  @doc "Install the APK at `apk` on `device`."
  @spec install!(String.t(), String.t(), String.t()) :: :ok
  def install!(apk, device, log),
    do: Shell.run!(adb(), ["-s", device, "install", "-r", apk], log: log)

  @doc "Start `app` on `device` and show here, until interrupted, the system's crash reports for it and, from a `--log` build, its output."
  @spec run!(App.t(), String.t()) :: :ok
  def run!(app, device) do
    Shell.output!(adb(), ["-s", device, "logcat", "-c"])

    Shell.output!(adb(), [
      "-s",
      device,
      "shell",
      "am",
      "start",
      "-S",
      "-n",
      "#{app.id}/cauldron.app.CauldronActivity"
    ])

    {_, _status} =
      System.cmd(
        adb(),
        ["-s", device, "logcat", "-s", "AndroidRuntime:E", "DEBUG:V", "cauldron:V"],
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

    :ok
  end

  @doc "The `adb` of the Android SDK."
  @spec adb() :: String.t()
  def adb, do: Path.join(Platform.android_sdk(), "platform-tools/adb")

  defp project!(app, source, folder, library, release) do
    template = Path.join(source, "native/android/project")
    main = Path.join(folder, "app/src/main")

    for path <- ["app", "settings.gradle", "build.gradle", "gradle.properties"],
        do: File.rm_rf!(Path.join(folder, path))

    File.mkdir_p!(Path.join(main, "java/cauldron/app"))
    File.mkdir_p!(Path.join(main, "jniLibs/arm64-v8a"))
    File.mkdir_p!(Path.join(main, "assets"))

    values = %{
      "name" => app.name,
      "id" => app.id,
      "version" => app.version,
      "version_code" => Integer.to_string(App.build_number(app)),
      "orientation" => orientation(app.orientation),
      "theme" => "@style/Cauldron",
      "native_ui" => to_string(app.native_ui?),
      "permissions" => android_permissions(app),
      "services" =>
        services(app) <>
          push_service(app) <>
          maps_key(app) <>
          purchase_types(app) <>
          AndroidWidgets.receivers(app),
      "links" => links(app.url_schemes),
      "icon" => icon_attributes(app),
      "root_plugins" => root_plugins(app),
      "plugins" => plugins(app),
      "dependencies" => dependencies(app)
    }

    filled!(Path.join(template, "settings.gradle"), Path.join(folder, "settings.gradle"), values)
    filled!(Path.join(template, "build.gradle"), Path.join(folder, "build.gradle"), values)

    filled!(
      Path.join(template, "gradle.properties"),
      Path.join(folder, "gradle.properties"),
      values
    )

    filled!(
      Path.join(template, "app.build.gradle"),
      Path.join(folder, "app/build.gradle"),
      values
    )

    filled!(
      Path.join(template, "AndroidManifest.xml"),
      Path.join(main, "AndroidManifest.xml"),
      values
    )

    File.cp_r!(Path.join(template, "res"), Path.join(main, "res"))
    resources!(app, Path.join(main, "res"))

    if app.push.android,
      do: File.cp!(app.push.android, Path.join(folder, "app/google-services.json"))

    File.write!(Path.join(folder, "local.properties"), "sdk.dir=#{Platform.android_sdk()}\n")

    File.cp!(
      Path.join(source, "native/android/java/CauldronActivity.java"),
      Path.join(main, "java/cauldron/app/CauldronActivity.java")
    )

    for file <-
          Path.wildcard(Path.join(source, "native/android/kotlin/*.kt")) ++ optional(app, source),
        do: File.cp!(file, Path.join([main, "java/cauldron/app", Path.basename(file)]))

    if AndroidWidgets.any?(app),
      do: AndroidWidgets.write!(app, Path.join(main, "java/cauldron/app"), Path.join(main, "res"))

    own = NativeViews.files(app, :android)
    File.mkdir_p!(Path.join(main, "java/app"))
    for file <- own, do: File.cp!(file, Path.join([main, "java/app", Path.basename(file)]))

    File.write!(
      Path.join(main, "java/cauldron/app/NativeViews.kt"),
      NativeViews.registry(:android, own)
    )

    File.cp!(library, Path.join(main, "jniLibs/arm64-v8a/libcauldron_app.so"))
    zip = Path.join(main, "assets/otp.zip")
    zip!(release, zip)
    stamp = :crypto.hash(:sha256, File.read!(zip)) |> Base.encode16(case: :lower)
    File.write!(Path.join(main, "assets/otp.stamp"), stamp)
  end

  defp optional(app, source) do
    push = if app.push.android, do: "push", else: "no_push"
    maps = if app.maps_key, do: "maps", else: "no_maps"
    widgets = if AndroidWidgets.any?(app), do: "widgets", else: "no_widgets"
    purchases = if app.purchases != [], do: "purchases", else: "no_purchases"

    [
      {push, "CauldronPush.kt"},
      {maps, "CauldronMap.kt"},
      {widgets, "CauldronWidgets.kt"},
      {purchases, "CauldronPurchases.kt"}
    ]
    |> Enum.map(fn {folder, file} ->
      Path.join([source, "native/android/optional", folder, file])
    end)
  end

  defp resources!(app, res) do
    themes!(app, res)
    if app.icon, do: icon!(app, res)

    notification_icon!(app.notification_icon, res)

    if app.launch.image, do: drawable!(res, "cauldron_launch.png", app.launch.image)
    if app.assets, do: Assets.android!(app.assets, res)
  end

  defp notification_icon!(nil, res) do
    File.mkdir_p!(Path.join(res, "drawable"))

    File.write!(Path.join(res, "drawable/cauldron_notification.xml"), """
    <?xml version="1.0" encoding="utf-8"?>
    <vector xmlns:android="http://schemas.android.com/apk/res/android"
        android:width="24dp"
        android:height="24dp"
        android:viewportWidth="24"
        android:viewportHeight="24">
        <path
            android:fillColor="#FFFFFFFF"
            android:pathData="M12,22c1.1,0 2,-0.9 2,-2h-4c0,1.1 0.89,2 2,2zM18,16v-5c0,-3.07 -1.64,-5.64 -4.5,-6.32L13.5,4c0,-0.83 -0.67,-1.5 -1.5,-1.5s-1.5,0.67 -1.5,1.5v0.68C7.63,5.36 6,7.92 6,11v5l-2,2v1h16v-1l-2,-2z" />
    </vector>
    """)
  end

  defp notification_icon!(icon, res), do: drawable!(res, "cauldron_notification.png", icon)

  defp drawable!(res, name, from) do
    folder = Path.join(res, "drawable-nodpi")
    File.mkdir_p!(folder)
    File.cp!(from, Path.join(folder, name))
  end

  defp icon!(app, res) do
    drawable!(res, "cauldron_icon.png", app.icon)
    File.mkdir_p!(Path.join(res, "mipmap-anydpi-v26"))
    File.mkdir_p!(Path.join(res, "drawable"))

    File.write!(Path.join(res, "drawable/cauldron_icon_inset.xml"), """
    <?xml version="1.0" encoding="utf-8"?>
    <inset xmlns:android="http://schemas.android.com/apk/res/android"
        android:drawable="@drawable/cauldron_icon"
        android:inset="16.7%" />
    """)

    adaptive = """
    <?xml version="1.0" encoding="utf-8"?>
    <adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
        <background android:drawable="@color/cauldron_icon_background" />
        <foreground android:drawable="@drawable/cauldron_icon_inset" />
    </adaptive-icon>
    """

    File.write!(Path.join(res, "mipmap-anydpi-v26/ic_launcher.xml"), adaptive)
    File.write!(Path.join(res, "mipmap-anydpi-v26/ic_launcher_round.xml"), adaptive)
  end

  defp themes!(app, res) do
    for folder <- ["values", "values-night"], do: File.mkdir_p!(Path.join(res, folder))

    colours =
      [
        {"cauldron_icon_background", app.icon_background},
        app.launch.background && {"cauldron_launch_background", app.launch.background}
      ]
      |> Enum.filter(& &1)
      |> Enum.map_join("\n", fn {name, value} ->
        "    <color name=\"#{name}\">#{value}</color>"
      end)

    File.write!(Path.join(res, "values/cauldron_colours.xml"), """
    <?xml version="1.0" encoding="utf-8"?>
    <resources>
    #{colours}
    </resources>
    """)

    File.write!(Path.join(res, "values/themes.xml"), theme_file(app, :light))
    File.write!(Path.join(res, "values-night/themes.xml"), theme_file(app, :dark))
  end

  defp theme_file(app, appearance) do
    """
    <?xml version="1.0" encoding="utf-8"?>
    <resources>
        <style name="Cauldron" parent="#{theme_parent(app, appearance)}">
    #{Enum.map_join(splash_items(app), "\n", &"        #{&1}")}
        </style>
    </resources>
    """
  end

  defp theme_parent(%App{native_ui?: false}, _appearance),
    do: "@android:style/Theme.Black.NoTitleBar.Fullscreen"

  defp theme_parent(_app, :light), do: "@android:style/Theme.Material.Light.NoActionBar"
  defp theme_parent(_app, :dark), do: "@android:style/Theme.Material.NoActionBar"

  defp splash_items(app) do
    background =
      if app.launch.background,
        do: [
          ~s(<item name="android:windowSplashScreenBackground">@color/cauldron_launch_background</item>)
        ],
        else: []

    image =
      if app.launch.image,
        do: [
          ~s(<item name="android:windowSplashScreenAnimatedIcon">@drawable/cauldron_launch</item>)
        ],
        else: []

    background ++ image
  end

  defp icon_attributes(%App{icon: nil}), do: ""

  defp icon_attributes(_app),
    do:
      ~s(\n        android:icon="@mipmap/ic_launcher"\n        android:roundIcon="@mipmap/ic_launcher_round")

  defp root_plugins(%App{push: %{android: nil}}), do: ""

  defp root_plugins(_app),
    do: ~s(    id "com.google.gms.google-services" version "4.5.0" apply false\n)

  defp plugins(%App{push: %{android: nil}}), do: ""
  defp plugins(_app), do: ~s(    id "com.google.gms.google-services"\n)

  defp dependencies(app) do
    push =
      if app.push.android,
        do: [
          ~s(implementation platform\("com.google.firebase:firebase-bom:35.1.0"\)),
          ~s(implementation "com.google.firebase:firebase-messaging")
        ],
        else: []

    maps =
      if app.maps_key,
        do: [
          ~s(implementation "com.google.maps.android:maps-compose:8.2.0")
        ],
        else: []

    widgets =
      if AndroidWidgets.any?(app),
        do: [
          ~s(implementation "androidx.glance:glance-appwidget:1.1.1"),
          ~s(implementation "androidx.glance:glance-material3:1.1.1")
        ],
        else: []

    purchases =
      if app.purchases != [],
        do: [~s(implementation "com.android.billingclient:billing:8.0.0")],
        else: []

    review = [~s(implementation "com.google.android.play:review:2.0.2")]

    Enum.map_join(push ++ maps ++ widgets ++ purchases ++ review, &"    #{&1}\n")
  end

  defp push_service(%App{push: %{android: nil}}), do: ""

  defp push_service(_app) do
    """
            <service
                android:name="cauldron.app.CauldronMessaging"
                android:exported="false">
                <intent-filter>
                    <action android:name="com.google.firebase.MESSAGING_EVENT" />
                </intent-filter>
            </service>
    """
  end

  defp links([]), do: ""

  defp links(schemes) do
    data = Enum.map_join(schemes, "\n", &~s(                <data android:scheme="#{&1}" />))

    """
                <intent-filter>
                    <action android:name="android.intent.action.VIEW" />
                    <category android:name="android.intent.category.DEFAULT" />
                    <category android:name="android.intent.category.BROWSABLE" />
    #{data}
                </intent-filter>
    """
  end

  defp purchase_types(%App{purchases: []}), do: ""

  defp purchase_types(app) do
    types =
      Map.new(app.purchases, &{&1.key, &1.type})
      |> JSON.encode!()
      |> String.replace("\"", "&quot;")

    ~s(        <meta-data android:name="cauldron.purchases" android:value="#{types}" />\n)
  end

  defp maps_key(%App{maps_key: nil}), do: ""

  defp maps_key(app),
    do:
      ~s(        <meta-data android:name="com.google.android.geo.API_KEY" android:value="#{app.maps_key}" />\n)

  defp filled!(from, to, values) do
    text =
      Enum.reduce(values, File.read!(from), fn {key, value}, acc ->
        String.replace(acc, "{{#{key}}}", value)
      end)

    File.write!(to, text)
  end

  @android_permissions [
    camera: ["CAMERA"],
    microphone: ["RECORD_AUDIO"],
    photos: [],
    location: ["ACCESS_FINE_LOCATION", "ACCESS_COARSE_LOCATION"],
    notifications: ["POST_NOTIFICATIONS"]
  ]

  defp android_permissions(app) do
    playback =
      if app.background_audio,
        do: ["FOREGROUND_SERVICE", "FOREGROUND_SERVICE_MEDIA_PLAYBACK"],
        else: []

    live =
      if app.live_activities,
        do: ["POST_NOTIFICATIONS", "POST_PROMOTED_NOTIFICATIONS"],
        else: []

    (Enum.flat_map(app.permissions, fn {name, _reason} ->
       Keyword.fetch!(@android_permissions, name)
     end) ++ playback ++ live)
    |> Enum.uniq()
    |> Enum.map_join(&"    <uses-permission android:name=\"android.permission.#{&1}\" />\n")
  end

  defp services(%App{background_audio: true}) do
    """
            <service
                android:name="cauldron.app.CauldronPlayback"
                android:exported="true"
                android:foregroundServiceType="mediaPlayback">
                <intent-filter>
                    <action android:name="androidx.media3.session.MediaSessionService" />
                </intent-filter>
            </service>
    """
  end

  defp services(_app), do: ""

  defp orientation(:landscape), do: "sensorLandscape"
  defp orientation(:portrait), do: "sensorPortrait"
  defp orientation(:any), do: "fullSensor"

  defp zip!(release, zip) do
    File.rm_rf!(zip)

    files =
      release
      |> Path.join("**")
      |> Path.wildcard(match_dot: true)
      |> Enum.reject(&File.dir?/1)
      |> Enum.map(&(&1 |> Path.relative_to(release) |> String.to_charlist()))

    {:ok, _} = :zip.create(String.to_charlist(zip), files, cwd: String.to_charlist(release))
  end

  defp wrapper!(folder, log) do
    gradle =
      System.find_executable("gradle") ||
        Mix.raise("Gradle is needed once to write the project's wrapper: brew install gradle")

    File.write!(Path.join(folder, "settings.gradle"), "")

    Shell.run!(gradle, ["wrapper", "--gradle-version", @gradle, "--no-daemon"],
      cd: folder,
      log: log
    )
  end
end
