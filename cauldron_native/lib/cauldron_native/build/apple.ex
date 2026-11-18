defmodule CauldronNative.Build.Apple do
  @moduledoc """
  The iOS, tvOS and macOS app: an Xcode project generated under the build folder,
  holding the Swift shell from this package's `native` folder, the static libraries, and
  the release as the bundle's `otp` folder; built with `xcodebuild` for a device, a
  simulator or this Mac (`CauldronNative.Build.Platform`). An iOS or tvOS app is
  installed and started on a connected device with `xcrun devicectl` or in a simulator
  with `CauldronNative.Build.Simulator`; a Mac app is started from the build folder
  (`run_mac!/1`) or copied into `~/Applications` (`install_mac!/2`).

  The SwiftUI views, the requests and the BEAM's start are shared by the three
  systems (`native/ios`); the window, the game screen, the pickers and the media views
  are UIKit's on iOS and tvOS (`native/ios`) and AppKit's on macOS (`native/macos`).
  An app's own views (`CauldronNative.Build.NativeViews`) are compiled for all three.

  A simulator build, and a Mac build without a team, is signed to run on this Mac only.

  Signing is Xcode's automatic signing for the development team given (`--team`, the
  `CAULDRON_NATIVE_TEAM` environment variable, or the app's `:team`); without one the
  app is built unsigned. The project carries the team, so it opens in Xcode ready to
  sign. The team ID is
  the ten characters Xcode shows under Settings → Accounts, or in the team's
  certificate name, `Apple Development: … (TEAMID)`. A free Apple ID's personal team
  works for apps installed on one's own devices. The device must have Developer Mode on
  (Settings → Privacy & Security → Developer Mode).

  `archive!/3` makes the App Store build instead: an archive signed for distribution and
  exported as an `.ipa` for App Store Connect, which needs a paid Apple Developer
  Program team.

  Every project carries the app's icon and launch screen in an asset catalog, its
  privacy manifest (`CauldronNative.Build.Privacy`), and, with push configured, the push
  entitlement.
  """

  alias CauldronNative.Build.{
    App,
    Assets,
    NativeViews,
    Platform,
    Png,
    Privacy,
    Shell,
    StoreKit,
    TvIcon,
    Widgets
  }

  @shared ~w(Beam.swift Weather.swift Background.swift Widgets.swift Purchases.swift Frames.swift Controllers.swift UI.swift UIControls.swift UIPlatform.swift UILayout.swift UIMedia.swift UICharts.swift UIGauge.swift Device.swift Location.swift Notifications.swift Bridging.h)
  @uikit ~w(main.swift App.swift Resolver.swift Screen.swift Hinge.swift UIMediaViews.swift DevicePickers.swift)
  @appkit ~w(main.swift App.swift Screen.swift UIMediaViews.swift DevicePickers.swift MenuBarExtra.swift)
  @frameworks ~w(SwiftUI StoreKit WeatherKit Charts MapKit Foundation QuartzCore CoreText GameController AVFoundation AVKit AudioToolbox CoreAudio CoreFoundation CoreLocation MediaPlayer Photos UniformTypeIdentifiers UserNotifications)

  @type linked :: %{objects: [String.t()], archives: [String.t()], ldflags: [String.t()]}

  @doc """
  Write the Xcode project for `app` on `platform` into `folder`: the shell from `source`
  (this package's folder), the release in `release`, and the libraries in `linked`.
  `kind` is `:development` for a build installed from this machine or `:store` for the
  App Store, which requires the app's icon and takes push from Apple's production
  service.
  """
  @spec project!(
          App.t(),
          Platform.t(),
          String.t(),
          String.t(),
          String.t(),
          linked(),
          :development | :store
        ) :: String.t()
  def project!(app, platform, source, folder, release, linked, kind) do
    File.rm_rf!(folder)
    sources = Path.join(folder, "Sources")
    libraries = Path.join(folder, "Libs")
    File.mkdir_p!(sources)
    File.mkdir_p!(libraries)
    shell = shell_files(source, platform.os)

    for {folder, file} <- shell,
        do: File.cp!(Path.join(folder, file), Path.join(sources, file))

    own = NativeViews.files(app, :ios)
    own_names = Enum.map(own, &copy_own!(&1, sources))
    File.write!(Path.join(sources, "NativeViews.swift"), NativeViews.registry(:ios, own))
    files = Enum.map(shell, &elem(&1, 1)) ++ own_names ++ ["NativeViews.swift"]

    File.cp!(
      Path.join(source, "c_src/cauldron_native.h"),
      Path.join(sources, "cauldron_native.h")
    )

    linked_names =
      for path <- linked.objects ++ linked.archives do
        name = unique_name(path)
        File.cp!(path, Path.join(libraries, name))
        name
      end

    File.cp_r!(release, Path.join(folder, "otp"))
    File.write!(Path.join(folder, "Info.plist"), info_plist(app, platform.os))
    File.write!(Path.join(folder, "PrivacyInfo.xcprivacy"), Privacy.manifest(app.privacy))
    catalog = Path.join(folder, "Assets.xcassets")
    assets!(app, platform.os, catalog, kind)
    if app.assets, do: Assets.merge!(app.assets, catalog)

    entitled = entitlements(app, platform.os, kind)
    if entitled != [], do: File.write!(Path.join(folder, "App.entitlements"), plist(entitled))

    project = Path.join(folder, "App.xcodeproj")
    File.mkdir_p!(project)

    widget_sources =
      if Widgets.extension?(app, platform.os), do: Widgets.write!(app, source, folder), else: []

    File.write!(
      Path.join(project, "project.pbxproj"),
      pbxproj(app, platform, files, linked_names, linked.ldflags, widget_sources)
    )

    if app.purchases != [], do: StoreKit.write!(app, folder, project, id("target", "App"))

    project
  end

  defp shell_files(source, :macos) do
    Enum.map(@shared, &{Path.join(source, "native/ios"), &1}) ++
      Enum.map(@appkit, &{Path.join(source, "native/macos"), &1})
  end

  defp shell_files(source, _uikit),
    do:
      Enum.map(@shared ++ @uikit, &{Path.join(source, "native/ios"), &1}) ++
        [{Path.join(source, "native/widgets"), "ActivityAttributes.swift"}]

  defp frameworks(:macos), do: @frameworks ++ ["AppKit", "WidgetKit"]
  defp frameworks(:tvos), do: @frameworks ++ ["UIKit", "PhotosUI", "BackgroundTasks"]

  defp frameworks(:ios),
    do: @frameworks ++ ["UIKit", "PhotosUI", "BackgroundTasks", "WidgetKit", "ActivityKit"]

  @mac_icon_sizes [16, 32, 128, 256, 512]

  defp assets!(app, :macos, folder, kind) do
    File.mkdir_p!(folder)
    File.write!(Path.join(folder, "Contents.json"), JSON.encode!(%{info: catalog_info()}))

    if kind == :store and app.icon == nil,
      do: Mix.raise(":icon is required for an App Store build")

    if app.icon, do: mac_icon_set!(Path.join(folder, "AppIcon.appiconset"), Png.icon!(app.icon))
  end

  defp assets!(app, :tvos, folder, kind) do
    File.mkdir_p!(folder)
    File.write!(Path.join(folder, "Contents.json"), JSON.encode!(%{info: catalog_info()}))

    if kind == :store and app.icon == nil,
      do: Mix.raise(":icon is required for an App Store build")

    if app.icon, do: TvIcon.write!(app, folder)
  end

  defp assets!(app, :ios, folder, kind) do
    File.mkdir_p!(folder)
    File.write!(Path.join(folder, "Contents.json"), JSON.encode!(%{info: catalog_info()}))

    if kind == :store and app.icon == nil,
      do: Mix.raise(":icon is required for an App Store build")

    if app.icon,
      do: image_set!(Path.join(folder, "AppIcon.appiconset"), Png.icon!(app.icon), :icon)

    if app.launch.image,
      do: image_set!(Path.join(folder, "LaunchImage.imageset"), app.launch.image, :image)

    if app.launch.background,
      do: colour_set!(Path.join(folder, "LaunchBackground.colorset"), app.launch.background)
  end

  defp image_set!(folder, image, kind) do
    File.mkdir_p!(folder)
    File.cp!(image, Path.join(folder, "image.png"))

    entry =
      case kind do
        :icon -> %{filename: "image.png", idiom: "universal", platform: "ios", size: "1024x1024"}
        :image -> %{filename: "image.png", idiom: "universal"}
      end

    File.write!(
      Path.join(folder, "Contents.json"),
      JSON.encode!(%{images: [entry], info: catalog_info()})
    )
  end

  defp mac_icon_set!(folder, icon) do
    File.mkdir_p!(folder)

    images =
      for size <- @mac_icon_sizes, scale <- [1, 2] do
        file = "icon_#{size}@#{scale}x.png"
        pixels = Integer.to_string(size * scale)
        _ = Shell.output!("sips", ["-z", pixels, pixels, icon, "--out", Path.join(folder, file)])
        %{filename: file, idiom: "mac", scale: "#{scale}x", size: "#{size}x#{size}"}
      end

    File.write!(
      Path.join(folder, "Contents.json"),
      JSON.encode!(%{images: images, info: catalog_info()})
    )
  end

  defp colour_set!(folder, "#" <> hex) do
    File.mkdir_p!(folder)
    <<red::binary-size(2), green::binary-size(2), blue::binary-size(2)>> = hex
    components = %{red: "0x" <> red, green: "0x" <> green, blue: "0x" <> blue, alpha: "1.000"}

    File.write!(
      Path.join(folder, "Contents.json"),
      JSON.encode!(%{
        colors: [%{color: %{"color-space": "srgb", components: components}, idiom: "universal"}],
        info: catalog_info()
      })
    )
  end

  defp catalog_info, do: %{author: "xcode", version: 1}

  defp entitlements(app, os, kind) do
    environment = if kind == :store, do: "production", else: "development"
    push = if os == :macos, do: "com.apple.developer.aps-environment", else: "aps-environment"

    [
      app.push.ios && {push, "<string>#{environment}</string>"},
      app.weatherkit && {"com.apple.developer.weatherkit", "<true/>"},
      Widgets.extension?(app, os) &&
        {"com.apple.security.application-groups",
         "<array><string>#{Widgets.group(app)}</string></array>"}
    ]
    |> Enum.filter(& &1)
  end

  defp plist(entries) do
    keys = Enum.map_join(entries, "\n  ", fn {key, value} -> "<key>#{key}</key>#{value}" end)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      #{keys}
    </dict>
    </plist>
    """
  end

  defp copy_own!(path, sources) do
    name = Path.basename(path)

    if name in @shared or name in @uikit or name in @appkit or name == "NativeViews.swift",
      do:
        Mix.raise(
          "#{path}: a file of the app's own may not be named #{name}, which the app's shell uses"
        )

    File.cp!(path, Path.join(sources, name))
    name
  end

  @unregistered_group """
  A profile that "doesn't match the entitlements file's value for the
  com.apple.security.application-groups entitlement" names an App Group the team has not
  registered, which xcodebuild does not do: open App.xcodeproj in the build folder, choose
  the device and Product ▸ Build once, then build again.
  """

  defp unregistered_group(tail),
    do: if(String.contains?(tail, "application-groups"), do: @unregistered_group)

  @doc """
  Build the project for `platform`'s `device` (an identifier, or `nil` for any device
  of the platform), signed by `team`, or unsigned when `team` is `nil` (an unsigned app
  builds and links but does not install on a device); the `.app`'s path. Signing
  registers `device` with the team, which a free personal team needs before it can make
  a profile. A simulator build is signed to run locally whatever `team` is.
  """
  @spec build!(String.t(), Platform.t(), String.t() | nil, String.t() | nil, String.t()) ::
          String.t()
  def build!(project, platform, team, device, log) do
    folder = Path.dirname(project)
    derived = Path.join(folder, "build")

    Shell.run!(
      "xcodebuild",
      ["-project", project, "-scheme", "App", "-configuration", "Release"] ++
        ["-sdk", platform.sdk, "-destination", destination(platform, device)] ++
        ["-derivedDataPath", derived] ++ signing(platform, team) ++ ["build"],
      cd: folder,
      log: log,
      explain: &unregistered_group/1
    )

    Path.join([derived, "Build", "Products", products(platform), "App.app"])
  end

  defp products(%Platform{os: :macos}), do: "Release"
  defp products(platform), do: "Release-#{platform.sdk}"

  @doc "Start the Mac app at `bundle`, its output streamed here until it quits."
  @spec run_mac!(String.t()) :: :ok
  def run_mac!(bundle) do
    executable = Path.join([bundle, "Contents", "MacOS", "App"])

    {_, _status} =
      System.cmd(executable, [], into: IO.stream(:stdio, :line), stderr_to_stdout: true)

    :ok
  end

  @doc """
  Copy the Mac app at `bundle` into `~/Applications` as `<name>.app`, replacing an
  earlier copy; the copy's path.
  """
  @spec install_mac!(String.t(), String.t()) :: String.t()
  def install_mac!(bundle, name) do
    target = Path.join([System.user_home!(), "Applications", name <> ".app"])
    File.mkdir_p!(Path.dirname(target))
    File.rm_rf!(target)
    _ = Shell.output!("ditto", [bundle, target])
    target
  end

  @export_help """
  Exporting for the App Store signs the app with an Apple Distribution certificate and an
  App Store profile, which Xcode makes when the team is a paid Apple Developer Program
  team, the app's bundle identifier is registered in it (or its App Store Connect record
  exists), and the Apple ID signed in to Xcode may make distribution certificates (the
  Account Holder or an Admin). Xcode → Settings → Accounts → Manage Certificates shows
  the certificates the account has.
  """

  @doc """
  Archive the project for the App Store, signed by `team`, and export it as an `.ipa`
  for App Store Connect; the `.ipa`'s path. Upload it with Xcode's Organizer, the
  Transporter app, or `xcrun altool --upload-app`.
  """
  @spec archive!(String.t(), Platform.t(), String.t(), String.t()) :: String.t()
  def archive!(project, platform, team, log) do
    folder = Path.dirname(project)
    archive = Path.join(folder, "App.xcarchive")
    export = Path.join(folder, "export")
    options = Path.join(folder, "ExportOptions.plist")
    File.rm_rf!(archive)
    File.rm_rf!(export)

    Shell.run!(
      "xcodebuild",
      ["-project", project, "-scheme", "App", "-configuration", "Release"] ++
        ["-destination", destination(platform, nil), "-archivePath", archive] ++
        signing(platform, team) ++ ["archive"],
      cd: folder,
      log: log
    )

    File.write!(options, export_options(team))

    Shell.run!(
      "xcodebuild",
      ["-exportArchive", "-archivePath", archive, "-exportPath", export] ++
        ["-exportOptionsPlist", options, "-allowProvisioningUpdates"],
      cd: folder,
      log: log,
      explain: @export_help
    )

    Path.join(export, if(platform.os == :macos, do: "App.pkg", else: "App.ipa"))
  end

  defp export_options(team) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>method</key><string>app-store-connect</string>
      <key>destination</key><string>export</string>
      <key>teamID</key><string>#{team}</string>
      <key>signingStyle</key><string>automatic</string>
      <key>uploadSymbols</key><true/>
      <key>manageAppVersionAndBuildNumber</key><false/>
    </dict>
    </plist>
    """
  end

  defp destination(%Platform{name: :ios}, nil), do: "generic/platform=iOS"
  defp destination(%Platform{name: :tvos}, nil), do: "generic/platform=tvOS"
  defp destination(%Platform{name: :ios_simulator}, nil), do: "generic/platform=iOS Simulator"
  defp destination(%Platform{name: :tvos_simulator}, nil), do: "generic/platform=tvOS Simulator"
  defp destination(%Platform{name: :macos}, _device), do: "generic/platform=macOS"
  defp destination(_platform, device), do: "id=#{device}"

  defp signing(%Platform{} = platform, team) do
    if Platform.simulator?(platform) or (platform.os == :macos and team == nil),
      do: ["CODE_SIGN_IDENTITY=-", "CODE_SIGN_STYLE=Manual", "DEVELOPMENT_TEAM="],
      else: signing(team)
  end

  defp signing(nil), do: ["CODE_SIGNING_ALLOWED=NO"]

  defp signing(team),
    do: [
      "-allowProvisioningUpdates",
      "-allowProvisioningDeviceRegistration",
      "DEVELOPMENT_TEAM=#{team}"
    ]

  @doc """
  The identifier of the first `os` device (`:ios` or `:tvos`) that is paired, connected
  and in Developer Mode, or of the device `id` when it is ready; raises, naming each
  device seen and what it lacks, when there is none.
  """
  @spec device!(:ios | :tvos, String.t() | nil) :: String.t()
  def device!(os, id) do
    file = Path.join(System.tmp_dir!(), "cauldron_native_devices.json")
    _ = Shell.output!("xcrun", ["devicectl", "list", "devices", "--json-output", file])
    devices = file |> File.read!() |> JSON.decode!() |> get_in(["result", "devices"]) || []
    File.rm(file)

    system = if os == :tvos, do: "tvOS", else: "iOS"

    ready =
      Enum.filter(devices, fn device ->
        get_in(device, ["hardwareProperties", "platform"]) == system and
          (id == nil or get_in(device, ["hardwareProperties", "udid"]) == id)
      end)

    case Enum.find(ready, &(lacking(&1) == [])) do
      nil -> Mix.raise(no_device(system, ready))
      device -> get_in(device, ["hardwareProperties", "udid"])
    end
  end

  defp lacking(device) do
    [
      get_in(device, ["connectionProperties", "pairingState"]) != "paired" && "not paired",
      get_in(device, ["connectionProperties", "tunnelState"]) != "connected" &&
        "not connected (plug it in or put it on the same network, and unlock it)",
      get_in(device, ["deviceProperties", "developerModeStatus"]) != "enabled" &&
        "Developer Mode off (Settings → Privacy & Security → Developer Mode)"
    ]
    |> Enum.filter(& &1)
  end

  defp no_device(system, []), do: "No #{system} device is paired with this Mac"

  defp no_device(system, devices) do
    lines =
      Enum.map_join(devices, "\n", fn device ->
        "  #{get_in(device, ["deviceProperties", "name"])}: #{Enum.join(lacking(device), "; ")}"
      end)

    "No #{system} device is ready to install on:\n" <> lines
  end

  @doc "Install the `.app` at `bundle` on `device`."
  @spec install!(String.t(), String.t(), String.t()) :: :ok
  def install!(bundle, device, log),
    do:
      Shell.run!("xcrun", ["devicectl", "device", "install", "app", "--device", device, bundle],
        log: log
      )

  @doc "Start `app` on `device`, its output streamed here until it exits."
  @spec run!(App.t(), String.t()) :: :ok
  def run!(app, device) do
    {_, _status} =
      System.cmd(
        "xcrun",
        [
          "devicectl",
          "device",
          "process",
          "launch",
          "--device",
          device,
          "--terminate-existing",
          "--console",
          app.id
        ],
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

    :ok
  end

  defp unique_name(path) do
    hash = :crypto.hash(:md5, path) |> Base.encode16(case: :lower) |> binary_part(0, 6)
    ext = Path.extname(path)
    Path.basename(path, ext) <> "_" <> hash <> ext
  end

  defp info_plist(app, os) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleDevelopmentRegion</key><string>en</string>
      <key>CFBundleDisplayName</key><string>#{escape(app.name)}</string>
      <key>CFBundleName</key><string>#{escape(app.name)}</string>
      <key>CFBundleExecutable</key><string>$(EXECUTABLE_NAME)</string>
      <key>CFBundleIdentifier</key><string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
      <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
      <key>CFBundlePackageType</key><string>APPL</string>
      <key>CFBundleShortVersionString</key><string>#{app.version}</string>
      <key>CFBundleVersion</key><string>#{App.build_number(app)}</string>
      <key>ITSAppUsesNonExemptEncryption</key>#{plist_bool(app.encryption == :non_exempt)}
      <key>CauldronPush</key>#{plist_bool(app.push.ios)}
      <key>CauldronAppGroup</key><string>#{Widgets.group(app)}</string>
      <key>NSSupportsLiveActivities</key>#{plist_bool(app.live_activities)}
      <key>CauldronWindow</key><dict>#{window_size(app.window)}</dict>
      #{refresh_task(app)}
      #{url_types(app)}
      #{usage(app)}
      #{system_keys(app, os)}
    </dict>
    </plist>
    """
  end

  defp window_size(window),
    do:
      Enum.map_join(window, "", fn {key, points} -> "<key>#{key}</key><real>#{points}</real>" end)

  defp refresh_task(%App{background_refresh: false}), do: ""

  defp refresh_task(app),
    do:
      "<key>BGTaskSchedulerPermittedIdentifiers</key><array><string>#{app.id}.refresh</string></array>"

  defp url_types(%App{url_schemes: []}), do: ""

  defp url_types(app) do
    schemes = Enum.map_join(app.url_schemes, &"<string>#{escape(&1)}</string>")

    "<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>#{app.id}</string>" <>
      "<key>CFBundleURLSchemes</key><array>#{schemes}</array></dict></array>"
  end

  defp system_keys(_app, :macos) do
    """
    <key>LSMinimumSystemVersion</key><string>#{Platform.minimum(:macos)}</string>
      <key>NSPrincipalClass</key><string>NSApplication</string>
      <key>NSHighResolutionCapable</key><true/>
    """
  end

  defp system_keys(_app, :tvos), do: scene_manifest()

  defp system_keys(app, :ios), do: handheld_keys(app) <> scene_manifest()

  defp scene_manifest do
    """
    <key>UIApplicationSceneManifest</key>
      <dict>
        <key>UIApplicationSupportsMultipleScenes</key><false/>
        <key>UISceneConfigurations</key>
        <dict>
          <key>UIWindowSceneSessionRoleApplication</key>
          <array>
            <dict>
              <key>UISceneConfigurationName</key><string>Default</string>
              <key>UISceneDelegateClassName</key><string>$(PRODUCT_MODULE_NAME).SceneDelegate</string>
            </dict>
          </array>
        </dict>
      </dict>
    """
  end

  defp handheld_keys(app) do
    orientations = orientations(app.orientation)

    """
    <key>LSRequiresIPhoneOS</key><true/>
      <key>UILaunchScreen</key>#{launch_screen(app.launch)}
      <key>UIRequiresFullScreen</key>#{plist_bool(not app.native_ui?)}
      <key>UIStatusBarHidden</key>#{plist_bool(not app.native_ui?)}
      <key>UISupportedInterfaceOrientations</key>
      <array>#{orientations}</array>
      <key>UISupportedInterfaceOrientations~ipad</key>
      <array>#{orientations}</array>
    """
  end

  @usage_keys [
    camera: ["NSCameraUsageDescription"],
    microphone: ["NSMicrophoneUsageDescription"],
    photos: ["NSPhotoLibraryUsageDescription", "NSPhotoLibraryAddUsageDescription"],
    location: ["NSLocationWhenInUseUsageDescription"],
    notifications: []
  ]

  defp usage(app) do
    reasons =
      for {name, reason} <- app.permissions,
          key <- Keyword.fetch!(@usage_keys, name),
          do: "<key>#{key}</key><string>#{escape(reason)}</string>"

    Enum.join(reasons ++ background_modes(app), "\n      ")
  end

  defp background_modes(app) do
    modes =
      [
        app.background_audio && "audio",
        app.push.ios && "remote-notification",
        app.background_refresh && "fetch"
      ]
      |> Enum.filter(& &1)

    if modes == [],
      do: [],
      else: [
        "<key>UIBackgroundModes</key><array>#{Enum.map_join(modes, &"<string>#{&1}</string>")}</array>"
      ]
  end

  defp launch_screen(launch) do
    colour =
      if launch.background,
        do: "<key>UIColorName</key><string>LaunchBackground</string>",
        else: ""

    image =
      if launch.image,
        do:
          "<key>UIImageName</key><string>LaunchImage</string><key>UIImageRespectsSafeAreaInsets</key><true/>",
        else: ""

    "<dict>#{colour}#{image}</dict>"
  end

  defp plist_bool(true), do: "<true/>"
  defp plist_bool(false), do: "<false/>"

  defp orientations(:landscape),
    do:
      "<string>UIInterfaceOrientationLandscapeLeft</string><string>UIInterfaceOrientationLandscapeRight</string>"

  defp orientations(:portrait), do: "<string>UIInterfaceOrientationPortrait</string>"

  defp orientations(:any),
    do: orientations(:landscape) <> orientations(:portrait)

  defp escape(text),
    do:
      text
      |> String.replace("&", "&amp;")
      |> String.replace("<", "&lt;")
      |> String.replace(">", "&gt;")

  @resources [
    {"otp", "folder"},
    {"Assets.xcassets", "folder.assetcatalog"},
    {"PrivacyInfo.xcprivacy", "text.xml"}
  ]

  defp pbxproj(app, platform, sources, linked_names, ldflags, widget_sources) do
    widgets = extension_part(app, widget_sources)
    swift = Enum.filter(sources, &String.ends_with?(&1, ".swift"))
    files = sources ++ ["cauldron_native.h"]

    resource_refs =
      Enum.map_join(@resources, "\n", fn {name, type} ->
        "\t\t#{id("build", name)} /* #{name} */ = {isa = PBXBuildFile; fileRef = #{id("ref", name)}; };\n" <>
          "\t\t#{id("ref", name)} /* #{name} */ = {isa = PBXFileReference; lastKnownFileType = #{type}; path = #{name}; sourceTree = \"<group>\"; };"
      end)

    resource_ids = Enum.map_join(@resources, ", ", fn {name, _type} -> id("build", name) end)
    resource_files = Enum.map_join(@resources, ", ", fn {name, _type} -> id("ref", name) end)

    link_flags =
      Enum.map(linked_names, &"\"$(PROJECT_DIR)/Libs/#{&1}\"") ++
        Enum.map(ldflags ++ ["-lc++", "-lz", "-lresolv"], &quote_flag/1) ++
        Enum.flat_map(frameworks(platform.os), &["\"-framework\"", "\"#{&1}\""])

    file_refs =
      Enum.map_join(files, "\n", fn file ->
        type =
          if String.ends_with?(file, ".swift"), do: "sourcecode.swift", else: "sourcecode.c.h"

        "\t\t#{id("ref", file)} /* #{file} */ = {isa = PBXFileReference; lastKnownFileType = #{type}; path = #{file}; sourceTree = \"<group>\"; };"
      end)

    build_files =
      Enum.map_join(swift, "\n", fn file ->
        "\t\t#{id("build", file)} /* #{file} */ = {isa = PBXBuildFile; fileRef = #{id("ref", file)}; };"
      end)

    """
    // !$*UTF8*$!
    {
    \tarchiveVersion = 1;
    \tclasses = {
    \t};
    \tobjectVersion = 56;
    \tobjects = {
    #{build_files}
    #{widgets.objects}
    #{resource_refs}
    #{file_refs}
    \t\t#{id("ref", "Info.plist")} /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
    \t\t#{id("ref", "App.app")} /* App.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = App.app; sourceTree = BUILT_PRODUCTS_DIR; };
    \t\t#{id("phase", "frameworks")} = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
    \t\t#{id("group", "main")} = {isa = PBXGroup; children = (#{id("group", "sources")}, #{widgets.group}#{resource_files}, #{id("ref", "Info.plist")}, #{id("group", "products")}); sourceTree = "<group>"; };
    \t\t#{id("group", "sources")} = {isa = PBXGroup; children = (#{Enum.map_join(files, ", ", &id("ref", &1))}); path = Sources; sourceTree = "<group>"; };
    \t\t#{id("group", "products")} = {isa = PBXGroup; children = (#{id("ref", "App.app")}#{widgets.product}); name = Products; sourceTree = "<group>"; };
    \t\t#{id("target", "App")} = {isa = PBXNativeTarget; buildConfigurationList = #{id("list", "target")}; buildPhases = (#{id("phase", "sources")}, #{id("phase", "frameworks")}, #{id("phase", "resources")}#{widgets.embed}); buildRules = (); dependencies = (#{widgets.dependency}); name = App; productName = App; productReference = #{id("ref", "App.app")}; productType = "com.apple.product-type.application"; };
    \t\t#{id("project", "App")} = {isa = PBXProject; attributes = {BuildIndependentTargetsInParallel = 1; LastUpgradeCheck = 1600; TargetAttributes = {#{id("target", "App")} = {CreatedOnToolsVersion = 16.0; }; }; }; buildConfigurationList = #{id("list", "project")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = #{id("group", "main")}; productRefGroup = #{id("group", "products")}; projectDirPath = ""; projectRoot = ""; targets = (#{id("target", "App")}#{widgets.target}); };
    \t\t#{id("phase", "resources")} = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (#{resource_ids}); runOnlyForDeploymentPostprocessing = 0; };
    \t\t#{id("phase", "sources")} = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (#{Enum.map_join(swift, ", ", &id("build", &1))}); runOnlyForDeploymentPostprocessing = 0; };
    \t\t#{id("config", "project")} = {isa = XCBuildConfiguration; buildSettings = {#{project_settings(platform)}}; name = Release; };
    \t\t#{id("config", "target")} = {isa = XCBuildConfiguration; buildSettings = {#{target_settings(app, platform, link_flags)}}; name = Release; };
    \t\t#{id("list", "project")} = {isa = XCConfigurationList; buildConfigurations = (#{id("config", "project")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };
    \t\t#{id("list", "target")} = {isa = XCConfigurationList; buildConfigurations = (#{id("config", "target")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };
    \t};
    \trootObject = #{id("project", "App")};
    }
    """
  end

  defp extension_part(_app, []),
    do: %{objects: "", group: "", product: "", embed: "", dependency: "", target: ""}

  defp extension_part(app, sources) do
    part = Widgets.project(app, sources, &id/2, id("project", "App"))

    %{
      objects: part.objects,
      group: part.group <> ", ",
      product: ", " <> part.product,
      embed: ", " <> part.embed,
      dependency: part.dependency,
      target: ", " <> part.target
    }
  end

  defp project_settings(%Platform{os: os}) do
    [
      ALWAYS_SEARCH_USER_PATHS: "NO",
      CLANG_ENABLE_MODULES: "YES",
      ENABLE_USER_SCRIPT_SANDBOXING: "NO",
      "#{deployment_setting(os)}": Platform.minimum(os),
      SDKROOT: device_sdk(os),
      SUPPORTED_PLATFORMS: supported_platforms(os),
      ARCHS: "arm64",
      SWIFT_OPTIMIZATION_LEVEL: "\"-O\"",
      SWIFT_COMPILATION_MODE: "wholemodule",
      VALIDATE_PRODUCT: "YES"
    ]
    |> settings()
  end

  defp deployment_setting(:ios), do: "IPHONEOS_DEPLOYMENT_TARGET"
  defp deployment_setting(:tvos), do: "TVOS_DEPLOYMENT_TARGET"
  defp deployment_setting(:macos), do: "MACOSX_DEPLOYMENT_TARGET"

  defp device_sdk(:ios), do: "iphoneos"
  defp device_sdk(:tvos), do: "appletvos"
  defp device_sdk(:macos), do: "macosx"

  defp supported_platforms(:ios), do: "\"iphoneos iphonesimulator\""
  defp supported_platforms(:tvos), do: "\"appletvos appletvsimulator\""
  defp supported_platforms(:macos), do: "macosx"

  defp icon_name(:tvos), do: "\"#{TvIcon.name()}\""
  defp icon_name(_os), do: "AppIcon"

  defp system_settings(:ios), do: [TARGETED_DEVICE_FAMILY: "\"1,2\""]
  defp system_settings(:tvos), do: [TARGETED_DEVICE_FAMILY: "3"]
  defp system_settings(:macos), do: [COMBINE_HIDPI_IMAGES: "YES"]

  defp runpath(:macos), do: "\"@executable_path/../Frameworks\""
  defp runpath(_uikit), do: "\"@executable_path/Frameworks\""

  defp accent_settings(%App{assets: nil}), do: []

  defp accent_settings(%App{assets: catalog}) do
    if File.dir?(Path.join(catalog, "AccentColor.colorset")),
      do: [ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: "AccentColor"],
      else: []
  end

  defp team_settings(%App{team: nil}), do: []
  defp team_settings(%App{team: team}), do: [DEVELOPMENT_TEAM: team]

  defp target_settings(app, platform, link_flags) do
    icon = if app.icon, do: [ASSETCATALOG_COMPILER_APPICON_NAME: icon_name(platform.os)], else: []

    entitled =
      if entitlements(app, platform.os, :development) != [],
        do: [CODE_SIGN_ENTITLEMENTS: "App.entitlements"],
        else: []

    (icon ++
       entitled ++
       accent_settings(app) ++
       team_settings(app) ++
       [
         CODE_SIGN_STYLE: "Automatic",
         CURRENT_PROJECT_VERSION: App.build_number(app),
         MARKETING_VERSION: app.version,
         ENABLE_BITCODE: "NO",
         GENERATE_INFOPLIST_FILE: "NO",
         HEADER_SEARCH_PATHS: "\"$(PROJECT_DIR)/Sources\"",
         INFOPLIST_FILE: "Info.plist",
         LD_RUNPATH_SEARCH_PATHS: runpath(platform.os),
         OTHER_LDFLAGS: "(#{Enum.join(link_flags, ", ")})",
         PRODUCT_BUNDLE_IDENTIFIER: app.id,
         PRODUCT_NAME: "App",
         SWIFT_OBJC_BRIDGING_HEADER: "Sources/Bridging.h",
         SWIFT_VERSION: "5.0"
       ] ++ system_settings(platform.os))
    |> settings()
  end

  defp settings(pairs), do: Enum.map_join(pairs, " ", fn {key, value} -> "#{key} = #{value};" end)

  defp quote_flag(flag), do: "\"#{flag}\""

  defp id(kind, name),
    do: :crypto.hash(:md5, kind <> ":" <> name) |> Base.encode16() |> binary_part(0, 24)
end
