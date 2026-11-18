defmodule CauldronNative.Build.Nifs do
  @moduledoc """
  The NIFs of a project's dependencies, compiled for a platform as static archives.

  A dependency takes part by giving its `Makefile` a `static` target. The build runs
  `make static` in the dependency's folder with:

    * `CC`, `AR` — the platform's compiler and archiver
    * `CFLAGS` — the platform's flags; the Makefile may add its own
    * `ERTS_INCLUDE_DIR` — the folder with the platform's `erl_nif.h`
    * `STATIC_DIR` — an empty folder for the results
    * `CAULDRON_TARGET` — the system the app runs on: `ios`, `tvos`, `macos` or
      `android`, the same for a device and its simulator
    * `APPLE_SDK` — on Apple's platforms, the SDK compiled against (`iphoneos`,
      `iphonesimulator`, `appletvos`, `appletvsimulator`, `macosx`), for `xcrun -sdk`
    * `APPLE_TARGET` — on Apple's platforms, the clang and Swift target, such as
      `arm64-apple-ios18.0-simulator`, for a Swift or Metal compile
    * `IOS_MINIMUM` — the lowest iOS version an iOS app runs on

  and the target writes, for each NIF, `<name>.a` into `STATIC_DIR`, compiled with
  `-DSTATIC_ERLANG_NIF_LIBNAME=<name>` so that it exports `<name>_nif_init`. It may also
  write `<name>.ldflags`, the linker flags the app needs for it (frameworks, system
  libraries), on one line.

  A dependency with a `c_src` folder and no `static` target is reported: its NIF is
  not in the app, and the module that loads it runs without it.
  """

  alias CauldronNative.Build.{Otp, Platform, Shell}

  @type nif :: %{name: String.t(), archive: String.t(), ldflags: [String.t()]}

  @doc "Every dependency's NIFs for `platform`, built under `folder`."
  @spec build!(%{atom() => String.t()}, Platform.t(), Otp.t(), String.t()) :: [nif()]
  def build!(deps_paths, platform, otp, folder) do
    File.rm_rf!(folder)

    deps_paths
    |> Enum.sort()
    |> Enum.flat_map(fn {app, path} -> dependency(app, path, platform, otp, folder) end)
  end

  defp dependency(app, path, platform, otp, folder) do
    makefile = Path.join(path, "Makefile")

    cond do
      File.exists?(makefile) and static_target?(makefile) ->
        build_dependency!(path, platform, otp, Path.join(folder, Atom.to_string(app)))

      File.dir?(Path.join(path, "c_src")) ->
        Mix.shell().info(
          "#{app} has native code but no static target in its Makefile; it is left out of the app"
        )

        []

      true ->
        []
    end
  end

  defp static_target?(makefile),
    do:
      makefile
      |> File.read!()
      |> String.split("\n")
      |> Enum.any?(&String.starts_with?(&1, "static:"))

  defp build_dependency!(path, platform, otp, out) do
    File.mkdir_p!(out)

    Shell.run!(
      "make",
      [
        "-C",
        path,
        "static",
        "CC=#{platform.cc}",
        "AR=#{platform.ar}",
        "CFLAGS=#{platform.cflags}",
        "ERTS_INCLUDE_DIR=#{otp.nif_include}",
        "STATIC_DIR=#{out}",
        "CAULDRON_TARGET=#{platform.os}",
        "APPLE_SDK=#{platform.sdk}",
        "APPLE_TARGET=#{platform.target}",
        "IOS_MINIMUM=#{Platform.minimum(:ios)}"
      ],
      log: Path.join(Path.dirname(out), "nifs.log")
    )

    for archive <- Path.wildcard(Path.join(out, "*.a")) do
      name = Path.basename(archive, ".a")
      ldflags_file = Path.join(out, name <> ".ldflags")

      ldflags =
        if File.exists?(ldflags_file),
          do: ldflags_file |> File.read!() |> String.split(),
          else: []

      %{name: name, archive: archive, ldflags: ldflags}
    end
  end
end
