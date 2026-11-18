defmodule CauldronNative.Build.Otp do
  @moduledoc """
  The Erlang runtime for a platform: OpenSSL and the OTP release this machine runs,
  cross-compiled from source, with the NIFs of `crypto` and `asn1` linked statically.
  Only the emulator and those two NIFs are compiled; the BEAM files an app carries
  come from this machine's OTP, which is the same version.

  tvOS declares `fork` and `exec` unavailable, which iOS refuses only when called: for
  tvOS the emulator's calls of them are compiled as a `fork` that fails, so on both the
  BEAM starts no child processes and runs without its child process helper.

  Builds are kept under the cache folder (`$XDG_CACHE_HOME/cauldron_native`, else
  `~/.cache/cauldron_native`), one per OTP version and platform, and reused. The OTP
  version is the running one's exact version (`OTP_VERSION`), so the BEAM files a
  release copies from this machine match the runtime they load into. Once a version's
  runtime is ready, the cache keeps only it and its sources: other versions' runtimes and
  sources are removed.

  `ensure!/1` gives what an app links:

    * `:libraries` — the emulator (`libbeam.a`, without its `driver_tab.o`), its
      internal libraries, zlib, zstd, PCRE and ryu
    * `:nifs` — `crypto.a` and `asn1rt_nif.a`, as `{name, archive}`
    * `:system_libraries` — OpenSSL's `libcrypto.a`
    * `:driver_tab` — the `driver_tab.c` OTP generated, which names the NIFs the
      emulator carries
    * `:driver_tab_flags` — the compiler flags that file is compiled with
    * `:nif_include` — the folder with `erl_nif.h` for this platform
    * `:jit?` — whether the emulator has the JIT (Android and macOS do; iOS and tvOS
      cannot)
    * `:triple` — OTP's name for the platform, which names its build folders
    * `:programs` — on macOS, the emulator's helper programs a release carries in its
      `bin` folder: `erl_child_setup`, which starts the programs `System.cmd/3` and ports
      run, and `inet_gethost`, the system's name lookup; none elsewhere, where the BEAM
      starts no programs
  """

  alias CauldronNative.Build.{Platform, Shell}

  @openssl "3.5.4"

  @enforce_keys [
    :version,
    :root,
    :libraries,
    :nifs,
    :system_libraries,
    :driver_tab,
    :driver_tab_flags,
    :nif_include,
    :jit?,
    :triple,
    :programs
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          version: String.t(),
          root: String.t(),
          libraries: [String.t()],
          nifs: [{String.t(), String.t()}],
          system_libraries: [String.t()],
          driver_tab: String.t(),
          driver_tab_flags: [String.t()],
          nif_include: String.t(),
          jit?: boolean(),
          triple: String.t(),
          programs: [String.t()]
        }

  @doc "The runtime for `platform`, building it first when the cache has none."
  @spec ensure!(Platform.t()) :: t()
  def ensure!(platform) do
    version = otp_version()
    folder = Path.join([cache(), version, Atom.to_string(platform.name)])
    openssl = Path.join(folder, "openssl")
    otp = Path.join(folder, "otp")

    unless built?(openssl), do: build_openssl!(platform, openssl)
    unless built?(otp), do: build_otp!(platform, otp, openssl, version)
    pruned!(version)

    described(platform, version, otp, openssl)
  end

  @doc "The folder builds and downloads are kept in."
  @spec cache() :: String.t()
  def cache do
    base = System.get_env("XDG_CACHE_HOME") || Path.expand("~/.cache")
    Path.join(base, "cauldron_native")
  end

  @doc "The exact OTP version this machine runs, such as `\"29.0\"`."
  @spec otp_version() :: String.t()
  def otp_version do
    [:code.root_dir(), "releases", System.otp_release(), "OTP_VERSION"]
    |> Path.join()
    |> File.read!()
    |> String.trim()
  end

  defp pruned!(version) do
    for entry <- File.ls!(cache()),
        entry not in [version, "src"],
        do: File.rm_rf!(Path.join(cache(), entry))

    sources = Path.join(cache(), "src")
    kept = ["otp_src_#{version}", "openssl-#{@openssl}"]

    if File.dir?(sources),
      do:
        for(
          entry <- File.ls!(sources),
          entry not in kept,
          do: File.rm_rf!(Path.join(sources, entry))
        )
  end

  defp built?(folder), do: File.exists?(Path.join(folder, ".built"))

  defp mark_built!(folder), do: File.write!(Path.join(folder, ".built"), "")

  defp build_openssl!(platform, prefix) do
    source = unpacked_source!("openssl-#{@openssl}", openssl_url())
    work = prefix <> "-work"
    File.rm_rf!(work)
    File.rm_rf!(prefix)
    File.mkdir_p!(Path.dirname(work))
    File.cp_r!(source, work)
    log = Path.join(Path.dirname(prefix), "openssl.log")
    Mix.shell().info("Building OpenSSL #{@openssl} for #{platform.name} (log: #{log})")

    Shell.run!(
      "./Configure",
      openssl_target(platform) ++
        ~w(no-shared no-tests no-apps no-docs no-engine no-async) ++ ["--prefix=#{prefix}"],
      cd: work,
      log: log,
      env: openssl_env(platform)
    )

    Shell.run!("make", ["-j", Shell.jobs(), "build_libs"],
      cd: work,
      log: log,
      env: openssl_env(platform)
    )

    Shell.run!("make", ["install_dev"], cd: work, log: log, env: openssl_env(platform))
    File.rm_rf!(work)
    mark_built!(prefix)
  end

  defp openssl_target(%Platform{os: :android}),
    do: ["android-arm64", "-D__ANDROID_API__=#{Platform.minimum(:android)}"]

  defp openssl_target(%Platform{}), do: ["darwin64-arm64"]

  defp openssl_env(%Platform{os: :android} = platform) do
    bin = Path.dirname(platform.cc)
    [{"ANDROID_NDK_ROOT", platform.ndk}, {"PATH", bin <> ":" <> System.get_env("PATH")}]
  end

  defp openssl_env(%Platform{} = platform),
    do: [{"CC", platform.cc}, {"AR", platform.ar}, {"RANLIB", platform.ranlib}]

  defp build_otp!(platform, otp, openssl, version) do
    source = unpacked_source!("otp_src_#{version}", otp_url(version))
    File.rm_rf!(otp)
    File.mkdir_p!(Path.dirname(otp))
    File.cp_r!(source, otp)
    log = Path.join(Path.dirname(otp), "otp.log")
    conf = Path.join(otp, "xcomp/cauldron.conf")
    File.write!(conf, xcomp_conf(platform, openssl))
    if platform.os == :tvos, do: without_fork!(otp)
    env = [{"ERL_TOP", otp}]
    Mix.shell().info("Building OTP #{version} for #{platform.name} (log: #{log})")

    Shell.run!("./otp_build", ["configure", "--xcomp-conf=#{conf}"], cd: otp, log: log, env: env)

    triple = triple(platform, otp)

    for part <- ~w(erts/lib_src erts/emulator) do
      Shell.run!("make", ["-j", Shell.jobs(), "-C", part, "opt", "TARGET=#{triple}"],
        cd: otp,
        log: log,
        env: env
      )
    end

    for program <- built_programs(platform, otp, triple) do
      Shell.run!(
        "make",
        [
          "-C",
          "erts/etc/common",
          "-f",
          "#{triple}/Makefile",
          program,
          "TARGET=#{triple}",
          "TYPE=opt"
        ],
        cd: otp,
        log: log,
        env: env
      )
    end

    archive = "../priv/lib/#{triple}"
    target = ["TARGET=#{triple}", "TYPE=opt"]

    Shell.run!(
      "make",
      ["-j", Shell.jobs(), "-f", "#{triple}/Makefile", "#{archive}/crypto.a"] ++ target,
      cd: Path.join(otp, "lib/crypto/c_src"),
      log: log,
      env: env
    )

    Shell.run!("make", ["#{archive}/asn1rt_nif.a"] ++ target,
      cd: Path.join(otp, "lib/asn1/c_src"),
      log: log,
      env: env
    )

    prepare_nif_include!(triple, otp)
    without_driver_tab!(platform, triple, otp)
    mark_built!(otp)
  end

  @forks [
    {"erts/emulator/sys/unix/sys_drivers.c",
     [
       {"    i = fork();\n", "    i = -1;\n"},
       {"        execv(child_setup_prog, cs_argv);\n", ""}
     ]},
    {"erts/emulator/sys/unix/erl_child_setup.c",
     [
       {"            os_pid = fork();\n", "            os_pid = -1;\n"},
       {"        execve(cmd, args, new_environ);\n", ""},
       {"        execle(SHELL, \"sh\", \"-c\", cmd, (char *) NULL, new_environ);\n", ""}
     ]}
  ]

  defp without_fork!(otp) do
    for {file, changes} <- @forks do
      path = Path.join(otp, file)
      File.write!(path, Enum.reduce(changes, File.read!(path), &replaced!(&2, &1, file)))
    end
  end

  defp replaced!(text, {old, new}, file) do
    case String.split(text, old) do
      [before, rest] ->
        before <> new <> rest

      _other ->
        Mix.raise("#{file} no longer has #{inspect(old)}; the tvOS build cannot run without fork")
    end
  end

  defp triple(platform, otp),
    do: Shell.output!(Path.join(otp, "make/autoconf/config.sub"), [platform.otp_host])

  defp xcomp_conf(platform, openssl) do
    flags =
      ~w(--without-termcap --without-wx --without-javac --without-odbc --without-debugger
         --without-observer --without-cdv --without-et --without-megaco --without-diameter
         --without-snmp --without-jinterface --disable-dynamic-ssl-lib --enable-builtin-zlib
         --enable-static-nifs=yes --enable-static-drivers) ++
        ["--with-ssl=#{openssl}"] ++ platform_flags(platform)

    """
    erl_xcomp_build=guess
    erl_xcomp_host=#{platform.otp_host}
    erl_xcomp_configure_flags="#{Enum.join(flags, " ")}"
    CC="#{platform.cc}"
    CXX="#{platform.cxx}"
    CFLAGS="#{otp_cflags(platform)}"
    CXXFLAGS="#{otp_cflags(platform)}"
    LDFLAGS="#{otp_ldflags(platform)}"
    LIBS="-L#{openssl}/lib -lcrypto"
    AR="#{platform.ar}"
    RANLIB="#{platform.ranlib}"
    erl_xcomp_sysroot=#{sysroot(platform)}
    """
  end

  defp platform_flags(%Platform{os: os}) when os in [:ios, :tvos],
    do: ~w(--disable-jit --disable-security-hardening-flags)

  defp platform_flags(%Platform{}), do: []

  defp otp_cflags(%Platform{os: os} = platform) when os in [:ios, :tvos],
    do: platform.cflags <> " -D__IOS__=yes"

  defp otp_cflags(platform), do: platform.cflags

  defp otp_ldflags(%Platform{os: :android}), do: "-static-libstdc++"
  defp otp_ldflags(platform), do: "-L#{Platform.sdk_path(platform)}/usr/lib -lc++"

  defp sysroot(%Platform{os: :android} = platform),
    do: Path.join(Path.dirname(Path.dirname(platform.cc)), "sysroot")

  defp sysroot(platform), do: Platform.sdk_path(platform)

  defp prepare_nif_include!(triple, otp) do
    include = Path.join(otp, "cauldron_include")
    File.mkdir_p!(include)

    for file <- ~w(erl_nif.h erl_nif_api_funcs.h erl_drv_nif.h erl_driver.h),
        do: File.cp!(Path.join([otp, "erts/emulator/beam", file]), Path.join(include, file))

    File.cp!(
      Path.join([otp, "erts/include", triple, "erl_int_sizes_config.h"]),
      Path.join(include, "erl_int_sizes_config.h")
    )

    fixed = Path.join([otp, "erts/include", triple, "erl_fixed_size_int_types.h"])
    if File.exists?(fixed), do: File.cp!(fixed, Path.join(include, "erl_fixed_size_int_types.h"))
  end

  defp without_driver_tab!(platform, triple, otp) do
    libbeam = Path.join([otp, "bin", triple, "libbeam.a"])
    stripped = Path.join([otp, "cauldron_include", "libbeam.a"])
    File.cp!(libbeam, stripped)
    log = Path.join(Path.dirname(otp), "otp.log")
    [ar | ar_arguments] = String.split(platform.ar)
    Shell.run!(ar, ar_arguments ++ ["d", stripped, "driver_tab.o"], log: log)
  end

  defp described(platform, version, otp, openssl) do
    triple = triple(platform, otp)
    emulator = Path.join(otp, "erts/emulator")
    flavour = if platform.jit?, do: "jit", else: "emu"

    %__MODULE__{
      version: version,
      root: otp,
      libraries: [
        Path.join([otp, "cauldron_include", "libbeam.a"]),
        Path.join([otp, "erts/lib/internal", triple, "liberts_internal_r.a"]),
        Path.join([otp, "erts/lib/internal", triple, "libethread.a"]),
        Path.join([emulator, "zlib/obj", triple, "opt/libz.a"]),
        Path.join([emulator, "zstd/obj", triple, "opt/libzstd.a"]),
        Path.join([emulator, "pcre/obj", triple, "opt/libepcre.a"]),
        Path.join([emulator, "ryu/obj", triple, "opt/libryu.a"])
      ],
      nifs: [
        {"crypto", Path.join([otp, "lib/crypto/priv/lib", triple, "crypto.a"])},
        {"asn1rt_nif", Path.join([otp, "lib/asn1/priv/lib", triple, "asn1rt_nif.a"])}
      ],
      system_libraries: [Path.join(openssl, "lib/libcrypto.a")],
      driver_tab: Path.join([emulator, triple, "opt", flavour, "driver_tab.c"]),
      driver_tab_flags:
        ~w(-DHAVE_CONFIG_H -DUSE_THREADS -D_THREAD_SAFE -D_REENTRANT -DPOSIX_THREADS) ++
          source_flags(platform) ++
          Enum.map(
            [
              Path.join([otp, "erts", triple]),
              Path.join([emulator, triple, "opt", flavour]),
              Path.join(emulator, "beam"),
              Path.join(emulator, "sys/unix"),
              Path.join(emulator, "sys/common"),
              Path.join(emulator, triple),
              Path.join(emulator, "zstd"),
              Path.join(emulator, "ryu"),
              Path.join(emulator, "pcre"),
              Path.join(otp, "erts/include"),
              Path.join([otp, "erts/include", triple]),
              Path.join(otp, "erts/include/internal"),
              Path.join([otp, "erts/include/internal", triple])
            ],
            &("-I" <> &1)
          ),
      nif_include: Path.join(otp, "cauldron_include"),
      jit?: platform.jit?,
      triple: triple,
      programs: programs(platform, otp, triple)
    }
  end

  defp built_programs(%Platform{os: :macos}, otp, triple),
    do: [Path.join([otp, "bin", triple, "inet_gethost"])]

  defp built_programs(_platform, _otp, _triple), do: []

  defp programs(%Platform{os: :macos}, otp, triple),
    do: Enum.map(~w(erl_child_setup inet_gethost), &Path.join([otp, "bin", triple, &1]))

  defp programs(_platform, _otp, _triple), do: []

  defp source_flags(%Platform{os: :android}), do: ["-D_GNU_SOURCE"]
  defp source_flags(_platform), do: []

  defp unpacked_source!(name, url) do
    sources = Path.join(cache(), "src")
    folder = Path.join(sources, name)

    unless File.dir?(folder) do
      File.mkdir_p!(sources)
      archive = folder <> ".tar.gz"
      log = Path.join(sources, "download.log")
      Mix.shell().info("Downloading #{url}")
      Shell.run!("curl", ["-sSLf", "-o", archive, url], log: log)
      Shell.run!("tar", ["xzf", archive, "-C", sources], log: log)
      File.rm!(archive)
    end

    folder
  end

  defp otp_url(version),
    do: "https://github.com/erlang/otp/releases/download/OTP-#{version}/otp_src_#{version}.tar.gz"

  defp openssl_url,
    do:
      "https://github.com/openssl/openssl/releases/download/openssl-#{@openssl}/openssl-#{@openssl}.tar.gz"
end
