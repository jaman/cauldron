defmodule CauldronNative.Build.Release do
  @moduledoc """
  The project's release as an app carries it: `mix release` of the current target,
  with the OTP applications it names copied from this machine's OTP (the same version
  the app's emulator is built from), without ERTS (the app links its own emulator),
  without the native libraries compiled for this machine, with the app's `:files` copied
  in beside it and its `:env` in `releases/env`, and with `releases/start_args`, the emulator's arguments
  one per line, `$ROOT` standing for the release's folder in the app and `$HOME` for
  the app's writable folder.

  Nothing is logged on the device: Elixir's default log handler is off
  (`-logger default_handler false`), unless the build asks for it with `log: true`.

  Schedulers do not spin while idle (`+sbwt none` and its dirty twins), so a phone at
  rest is not kept awake by them.
  """

  alias CauldronNative.Build.App

  @spinless ~w(-sbwt none -sbwtdcpu none -sbwtdio none)

  @doc """
  Assemble the release for `app` into `folder`, and return its version. With `log: true`
  Elixir's default log handler stays on and `releases/env` sets `CAULDRON_NATIVE_LOG=1`,
  which on Android sends the runtime's output to logcat under the tag `cauldron`, for a
  development build whose output is watched (`mix cauldron_native.build --log --run`).
  """
  @spec assemble!(App.t(), String.t(), keyword()) :: String.t()
  def assemble!(app, folder, opts \\ []) do
    File.rm_rf!(folder)

    Mix.Task.run("release", [
      Atom.to_string(app.release),
      "--path",
      folder,
      "--overwrite",
      "--quiet"
    ])

    version = Mix.Project.config()[:version]
    copy_otp_apps!(folder, app.release, version)
    drop_host_native!(folder)

    log? = Keyword.get(opts, :log, false)
    File.write!(Path.join([folder, "releases", "start_args"]), start_args(app, version, log?))
    File.write!(Path.join([folder, "releases", "env"]), env_lines(logged(app.env, log?)))
    copy_files!(app.files, folder)

    File.rm_rf!(Path.join(folder, "bin"))
    for erts <- Path.wildcard(Path.join(folder, "erts-*")), do: File.rm_rf!(erts)
    version
  end

  @doc """
  Copy the emulator's helper `programs` (`CauldronNative.Build.Otp`'s `:programs`) into
  the release's `bin` folder, the `BINDIR` the app starts the BEAM with.
  """
  @spec add_programs!(String.t(), [String.t()]) :: :ok
  def add_programs!(_folder, []), do: :ok

  def add_programs!(folder, programs) do
    bin = Path.join(folder, "bin")
    File.mkdir_p!(bin)

    for program <- programs do
      unless File.exists?(program), do: Mix.raise("The OTP build has no #{program}")
      target = Path.join(bin, Path.basename(program))
      File.cp!(program, target)
      File.chmod!(target, 0o755)
    end

    :ok
  end

  @doc "The emulator's arguments for a release of `version`, one per line; `log?` keeps Elixir's log on."
  @spec start_args(App.t(), String.t(), boolean()) :: String.t()
  def start_args(app, version, log?) do
    release = "$ROOT/releases/#{version}"

    (@spinless ++
       app.emulator_flags ++
       ~w(-- -root $ROOT -bindir $ROOT/bin -progname erl -- -home $HOME --) ++
       [
         "-noshell",
         "-noinput",
         "-boot",
         release <> "/start",
         "-boot_var",
         "RELEASE_LIB",
         "$ROOT/lib",
         "-config",
         release <> "/sys",
         "-mode",
         "embedded",
         "-start_epmd",
         "false",
         "-elixir",
         "ansi_enabled",
         "false"
       ] ++ quiet(log?))
    |> Enum.map_join(&(&1 <> "\n"))
  end

  @doc "The app's environment variables as `releases/env` holds them, one `NAME=value` a line."
  @spec env_lines(%{String.t() => String.t()}) :: String.t()
  def env_lines(env), do: Enum.map_join(env, fn {name, value} -> "#{name}=#{value}\n" end)

  defp copy_files!(files, folder) do
    for {from, to} <- files do
      unless File.exists?(from), do: Mix.raise("#{from}, named in :files, does not exist")
      target = Path.join(folder, to)
      File.mkdir_p!(Path.dirname(target))
      File.cp_r!(from, target)
    end
  end

  defp logged(env, true), do: Map.put(env, "CAULDRON_NATIVE_LOG", "1")
  defp logged(env, false), do: env

  defp quiet(true), do: []
  defp quiet(false), do: ~w(-logger default_handler false)

  defp copy_otp_apps!(folder, release, version) do
    rel = Path.join([folder, "releases", version, "#{release}.rel"])
    {:ok, [{:release, _name, _erts, apps}]} = :file.consult(String.to_charlist(rel))

    for {app, vsn, _mode} <- Enum.map(apps, &with_mode/1),
        target = Path.join([folder, "lib", "#{app}-#{vsn}"]),
        not File.dir?(target) do
      source = :code.lib_dir(app) |> to_string()

      if Path.basename(source) != "#{app}-#{vsn}",
        do: Mix.raise("#{app} #{vsn} is in the release but this machine has #{source}")

      File.mkdir_p!(target)
      File.cp_r!(Path.join(source, "ebin"), Path.join(target, "ebin"))
      priv = Path.join(source, "priv")
      if File.dir?(priv), do: File.cp_r!(priv, Path.join(target, "priv"))
    end
  end

  defp with_mode({app, vsn}), do: {app, vsn, :permanent}
  defp with_mode({app, vsn, mode}), do: {app, vsn, mode}

  defp drop_host_native!(folder) do
    for path <- Path.wildcard(Path.join(folder, "lib/*/priv/**/*.{so,dylib,dll}")),
        do: File.rm!(path)

    for path <- Path.wildcard(Path.join(folder, "lib/*/priv/native")), do: File.rm_rf!(path)
  end
end
