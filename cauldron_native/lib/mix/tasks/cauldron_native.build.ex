defmodule Mix.Tasks.CauldronNative.Build do
  @shortdoc "Builds the project as an iOS, tvOS, macOS or Android app"

  @moduledoc """
  Builds the current project as a phone, tablet, TV or Mac app, and optionally installs
  and starts it.

      mix cauldron_native.build ios --run
      mix cauldron_native.build ios --simulator --device "iPhone Duo" --run
      mix cauldron_native.build tvos --simulator --run
      mix cauldron_native.build macos --run
      mix cauldron_native.build android --run

  Each build is kept under `_build/<system>_<env>/cauldron_native/<platform>`
  (`CauldronNative.Build.Platform`), a device's and a simulator's apart. Once the app
  is built, the system's builds from the project's other environments are removed, being
  older builds of the same app.

  The project is compiled with `MIX_TARGET` set to the system (`ios`, `tvos`, `macos`
  or `android`) and `MIX_ENV` to `prod` unless set, so dependencies can be limited to a
  system with `targets:` (a desktop front end left out of the phone, say). The task
  runs itself again under that target when called without it.

  The app is described by the project's `:cauldron_native` config
  (`CauldronNative.Build.App`). The first build for a platform cross-compiles OpenSSL
  and OTP, which takes several minutes; later builds reuse them
  (`CauldronNative.Build.Otp`).

  ## Options

    * `--install` — install the app on the first connected device; a Mac app is copied
      into `~/Applications`
    * `--run` — install it, start it, and stream its output here; a Mac app is started
      from the build folder
    * `--simulator` — build for Apple's simulator on this Mac instead of a device;
      `--install` and `--run` use the simulator running, or the one `--device` names
      (`CauldronNative.Build.Simulator`)
    * `--team` — the Apple development team that signs the app for a device
    * `--device` — the device to install on: an Apple device's identifier, a
      simulator's name or identifier, or an `adb` serial
    * `--log` — keep Elixir's log on in the app, for a development build: `--run` shows
      it here. Without it the app logs nothing
    * `--release` — the store build instead of one to install: an `.ipa` for App Store
      Connect, signed for distribution by the team, or an Android App Bundle (`.aab`)
      for Google Play, signed with the upload key named by `:android_signing`. The
      guide's "Publishing" covers the steps around it

  ## Requirements

    * macOS: Xcode; a Mac build without a team is signed to run on this Mac
    * iOS and tvOS: Xcode, and a paired device with Developer Mode on and a
      development team, or the system's simulator runtime (Xcode → Settings →
      Components)
    * Android: the Android SDK with an NDK (`ANDROID_HOME`, default
      `~/Library/Android/sdk`), a JDK 17 or later, and Gradle for the first build
  """

  use Mix.Task

  alias CauldronNative.Build.{
    Android,
    App,
    Apple,
    DriverTab,
    Nifs,
    Otp,
    Platform,
    Release,
    Simulator
  }

  @switches [
    install: :boolean,
    run: :boolean,
    simulator: :boolean,
    team: :string,
    device: :string,
    log: :boolean,
    release: :boolean
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, rest} = OptionParser.parse!(argv, strict: @switches)

    case rest do
      [system] when system in ["ios", "tvos", "macos", "android"] ->
        build(String.to_atom(system), argv, opts)

      _other ->
        Mix.raise(
          "Usage: mix cauldron_native.build ios|tvos|macos|android [--simulator] [--install] [--run] [--team TEAM] [--device ID] [--log] [--release]"
        )
    end
  end

  defp build(platform, argv, opts) do
    if Mix.target() == platform,
      do: build_here(platform, opts),
      else: build_under_target(platform, argv)
  end

  defp build_under_target(platform, argv) do
    env = [
      {"MIX_TARGET", Atom.to_string(platform)},
      {"MIX_ENV", System.get_env("MIX_ENV") || "prod"}
    ]

    mix = System.find_executable("mix")
    Mix.shell().info("Compiling for #{platform} (MIX_TARGET=#{platform})")

    {_, _} =
      System.cmd(mix, ["deps.get"],
        env: env,
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

    case System.cmd(mix, ["cauldron_native.build" | argv],
           env: env,
           into: IO.stream(:stdio, :line),
           stderr_to_stdout: true
         ) do
      {_, 0} -> :ok
      {_, status} -> Mix.raise("The #{platform} build failed (exit #{status})")
    end
  end

  defp build_here(system, opts) do
    refuse_conflicts!(system, opts[:release] == true, opts[:simulator] == true, install?(opts))
    app = App.from_project!()
    platform = Platform.fetch!(Platform.named(system, opts[:simulator] == true))
    otp = Otp.ensure!(platform)
    builds = Path.join(Mix.Project.build_path(), "cauldron_native")
    drop_other_layouts!(builds)
    folder = Path.join(builds, Atom.to_string(platform.name))
    deps = Mix.Project.deps_paths()

    source =
      Map.get(deps, :cauldron_native) ||
        Mix.raise("cauldron_native is not a dependency for #{system}")

    Mix.shell().info("Assembling the release")
    release = Path.join(folder, "release")
    Release.assemble!(app, release, log: opts[:log] == true)
    Release.add_programs!(release, otp.programs)

    Mix.shell().info("Compiling the NIFs for #{platform.name}")
    nifs = Nifs.build!(deps, platform, otp, Path.join(folder, "nifs"))

    driver_tab =
      DriverTab.compile!(
        Enum.map(nifs, & &1.name),
        platform,
        otp,
        Path.join(folder, "driver_tab")
      )

    linked = %{
      objects: [driver_tab],
      archives:
        otp.libraries ++
          Enum.map(nifs, & &1.archive) ++
          Enum.map(otp.nifs, &elem(&1, 1)) ++ otp.system_libraries,
      ldflags: Enum.flat_map(nifs, & &1.ldflags)
    }

    deliver(opts[:release] == true, platform, app, source, folder, release, linked, opts)
    drop_older_builds(system)
  end

  defp refuse_conflicts!(_system, true, _simulator?, true),
    do: Mix.raise("--release makes a build for the store, which is not installed from here")

  defp refuse_conflicts!(_system, true, true, _install?),
    do: Mix.raise("--release makes a build for the store, which a simulator does not run")

  defp refuse_conflicts!(:android, _release?, true, _install?),
    do: Mix.raise("--simulator is for Apple's systems; an Android emulator is a device to adb")

  defp refuse_conflicts!(:macos, _release?, true, _install?),
    do: Mix.raise("--simulator is for iOS and tvOS; a Mac app runs on this Mac")

  defp refuse_conflicts!(_system, _release?, _simulator?, _install?), do: :ok

  defp drop_other_layouts!(builds) do
    names = Enum.map(Platform.names(), &Atom.to_string/1)

    if File.dir?(builds),
      do:
        for(
          entry <- File.ls!(builds),
          entry not in names,
          do: File.rm_rf!(Path.join(builds, entry))
        )
  end

  defp drop_older_builds(system) do
    build = Mix.Project.build_path()

    for other <- Path.wildcard(Path.join(Path.dirname(build), "#{system}_*")),
        other != build,
        do: File.rm_rf!(Path.join(other, "cauldron_native"))
  end

  defp deliver(true, %Platform{os: :android}, app, source, folder, release, linked, opts),
    do: store_android(app, source, folder, release, linked, opts)

  defp deliver(true, platform, app, source, folder, release, linked, opts),
    do: store_apple(app, platform, source, folder, release, linked, opts)

  defp deliver(false, platform, app, source, folder, release, linked, opts),
    do: package(platform, app, source, folder, release, linked, opts)

  defp package(%Platform{name: name} = platform, app, source, folder, release, linked, opts)
       when name in [:ios_simulator, :tvos_simulator] do
    install? = install?(opts)
    device = if install?, do: Simulator.device!(platform.os, opts[:device])

    project =
      Apple.project!(
        app,
        platform,
        source,
        Path.join(folder, "xcode"),
        release,
        linked,
        :development
      )

    log = Path.join(folder, "xcode.log")
    Mix.shell().info("Building the #{platform.os} app for the simulator (log: #{log})")
    bundle = Apple.build!(project, platform, nil, device, log)
    Mix.shell().info("Built #{bundle}")

    if install? do
      Mix.shell().info("Installing in the simulator #{device}")
      Simulator.install!(bundle, device, log)
      if opts[:run], do: Simulator.run!(app, device)
    end
  end

  defp package(%Platform{os: os} = platform, app, source, folder, release, linked, opts)
       when os in [:ios, :tvos] do
    team = ios_team(app, opts)
    install? = install?(opts)
    if install? && team == nil, do: missing_team!()
    device = if install?, do: Apple.device!(os, opts[:device])

    project =
      Apple.project!(
        %{app | team: team},
        platform,
        source,
        Path.join(folder, "xcode"),
        release,
        linked,
        :development
      )

    log = Path.join(folder, "xcode.log")
    Mix.shell().info("Building the #{os} app (log: #{log})")
    bundle = Apple.build!(project, platform, team, device, log)
    Mix.shell().info("Built #{bundle}" <> unsigned_note(team))
    if install?, do: install_ios(app, bundle, device, log, opts)
  end

  defp package(%Platform{os: :macos} = platform, app, source, folder, release, linked, opts) do
    team = ios_team(app, opts)

    project =
      Apple.project!(
        %{app | team: team},
        platform,
        source,
        Path.join(folder, "xcode"),
        release,
        linked,
        :development
      )

    log = Path.join(folder, "xcode.log")
    Mix.shell().info("Building the macOS app (log: #{log})")
    bundle = Apple.build!(project, platform, team, nil, log)
    Mix.shell().info("Built #{bundle}")

    if opts[:install],
      do: Mix.shell().info("Installed #{Apple.install_mac!(bundle, app.name)}")

    if opts[:run], do: Apple.run_mac!(bundle)
  end

  defp package(%Platform{os: :android}, app, source, folder, release, linked, opts) do
    platform = Platform.fetch!(:android)
    library = Android.library!(platform, source, Path.join(folder, "android_lib"), linked)
    gradle = Path.join(folder, "android")
    Mix.shell().info("Building the Android app (log: #{Path.join(gradle, "gradle.log")})")
    apk = Android.apk!(app, source, gradle, %{library: library, release: release})
    Mix.shell().info("Built #{apk}")

    if opts[:install] || opts[:run] do
      device = opts[:device] || Android.device() || Mix.raise("adb lists no device or emulator")
      Mix.shell().info("Installing on #{device}")
      Android.install!(apk, device, Path.join(gradle, "adb.log"))
      if opts[:run], do: Android.run!(app, device)
    end
  end

  defp store_apple(app, platform, source, folder, release, linked, opts) do
    team = ios_team(app, opts) || missing_team!()

    project =
      Apple.project!(
        %{app | team: team},
        platform,
        source,
        Path.join(folder, "xcode"),
        release,
        linked,
        :store
      )

    log = Path.join(folder, "xcode.log")
    Mix.shell().info("Archiving the #{platform.os} app for the App Store (log: #{log})")
    ipa = Apple.archive!(project, platform, team, log)

    Mix.shell().info("""
    Built #{ipa}
    Upload it to App Store Connect with the Transporter app, Xcode's Organizer, or
    xcrun altool --upload-app -f #{ipa} -t #{if platform.os == :tvos, do: "appletvos", else: "ios"} --apiKey KEY --apiIssuer ISSUER
    """)
  end

  defp store_android(app, source, folder, release, linked, _opts) do
    platform = Platform.fetch!(:android)
    library = Android.library!(platform, source, Path.join(folder, "android_lib"), linked)
    gradle = Path.join(folder, "android")
    Mix.shell().info("Building the Android App Bundle (log: #{Path.join(gradle, "gradle.log")})")
    bundle = Android.bundle!(app, source, gradle, %{library: library, release: release})

    Mix.shell().info("""
    Built #{bundle}
    Upload it in the Play Console under Test and release, with Play App Signing on.
    """)
  end

  defp ios_team(app, opts),
    do: opts[:team] || System.get_env("CAULDRON_NATIVE_TEAM") || app.team

  defp install?(opts), do: opts[:install] == true or opts[:run] == true

  defp unsigned_note(nil), do: " (unsigned: give a team to install it)"
  defp unsigned_note(_team), do: ""

  defp install_ios(app, bundle, device, log, opts) do
    Mix.shell().info("Installing on #{device}")
    Apple.install!(bundle, device, log)
    if opts[:run], do: Apple.run!(app, device)
  end

  defp missing_team! do
    Mix.raise("""
    The iOS app needs a development team to sign it. Give it with --team, the
    CAULDRON_NATIVE_TEAM environment variable, or :team in the project's
    :cauldron_native config. Xcode shows the team ID under Settings → Accounts once an
    Apple ID is added there; a free Apple ID's personal team works for your own devices.
    """)
  end
end
