defmodule CauldronNative.Build.Platform do
  @moduledoc """
  The platforms an app is built for, each as the compilers and flags that target it:

    * `:ios` — arm64 iPhones and iPads, iOS 18 and later
    * `:ios_simulator` — the iOS Simulator on an Apple silicon Mac
    * `:tvos` — Apple TV, tvOS 18 and later
    * `:tvos_simulator` — the tvOS Simulator on an Apple silicon Mac
    * `:macos` — Apple silicon Macs, macOS 15 and later
    * `:android` — arm64-v8a phones and tablets, API 33 and later, through the Android NDK

  The Apple platforms compile through Xcode's `xcrun` with the platform's SDK (`:sdk`)
  and clang target (`:target`). `:os` is the system the code runs on, the same for a
  device and its simulator; `:jit?` is whether the BEAM has its JIT, which iOS and tvOS
  forbid.

  The NDK is found under `ANDROID_NDK_HOME`, or the newest under `ANDROID_HOME/ndk`
  (`ANDROID_HOME` defaulting to `~/Library/Android/sdk`).
  """

  alias CauldronNative.Build.Shell

  @enforce_keys [:name, :os, :otp_host, :cc, :cxx, :ar, :ranlib, :cflags, :jit?]
  defstruct @enforce_keys ++ [sdk: nil, target: nil, ndk: nil]

  @type name :: :ios | :ios_simulator | :tvos | :tvos_simulator | :macos | :android
  @type os :: :ios | :tvos | :macos | :android
  @type t :: %__MODULE__{
          name: name(),
          os: os(),
          sdk: String.t() | nil,
          target: String.t() | nil,
          otp_host: String.t(),
          cc: String.t(),
          cxx: String.t(),
          ar: String.t(),
          ranlib: String.t(),
          cflags: String.t(),
          jit?: boolean(),
          ndk: String.t() | nil
        }

  @minimum %{ios: "18.0", tvos: "18.0", macos: "15.0", android: "33"}

  @apple %{
    ios: %{os: :ios, sdk: "iphoneos", suffix: "", otp_host: "arm64-apple-ios"},
    ios_simulator: %{
      os: :ios,
      sdk: "iphonesimulator",
      suffix: "-simulator",
      otp_host: "arm64-apple-iossimulator"
    },
    tvos: %{os: :tvos, sdk: "appletvos", suffix: "", otp_host: "arm64-apple-tvos"},
    tvos_simulator: %{
      os: :tvos,
      sdk: "appletvsimulator",
      suffix: "-simulator",
      otp_host: "arm64-apple-tvossimulator"
    },
    macos: %{os: :macos, sdk: "macosx", suffix: "", otp_host: "aarch64-apple-darwin"}
  }

  @doc "Every platform's name."
  @spec names() :: [name()]
  def names, do: Map.keys(@apple) ++ [:android]

  @doc "The platform that runs `os`, on a device or, with `simulator?`, in its simulator."
  @spec named(os(), boolean()) :: name()
  def named(os, false), do: os
  def named(:ios, true), do: :ios_simulator
  def named(:tvos, true), do: :tvos_simulator

  @doc "The platform called `name`."
  @spec fetch!(name()) :: t()
  def fetch!(:android) do
    ndk = ndk!()
    bin = Path.join(ndk, "toolchains/llvm/prebuilt/darwin-x86_64/bin")
    api = @minimum.android

    %__MODULE__{
      name: :android,
      os: :android,
      otp_host: "aarch64-linux-android",
      cc: Path.join(bin, "aarch64-linux-android#{api}-clang"),
      cxx: Path.join(bin, "aarch64-linux-android#{api}-clang++"),
      ar: Path.join(bin, "llvm-ar"),
      ranlib: Path.join(bin, "llvm-ranlib"),
      cflags: "-O2 -fPIC",
      jit?: true,
      ndk: ndk
    }
  end

  def fetch!(name) when is_map_key(@apple, name) do
    %{os: os, sdk: sdk, suffix: suffix, otp_host: otp_host} = Map.fetch!(@apple, name)
    target = "arm64-apple-#{os}#{@minimum[os]}#{suffix}"
    xcrun = "xcrun -sdk #{sdk}"

    %__MODULE__{
      name: name,
      os: os,
      sdk: sdk,
      target: target,
      otp_host: otp_host,
      cc: "#{xcrun} clang -target #{target}",
      cxx: "#{xcrun} clang++ -target #{target}",
      ar: "#{xcrun} ar",
      ranlib: "#{xcrun} ranlib",
      cflags: "-fno-common -O2",
      jit?: os == :macos
    }
  end

  @doc "Whether `platform` is one of Apple's."
  @spec apple?(t()) :: boolean()
  def apple?(%__MODULE__{sdk: sdk}), do: sdk != nil

  @doc "Whether `platform` is a simulator."
  @spec simulator?(t()) :: boolean()
  def simulator?(%__MODULE__{name: name}), do: name in [:ios_simulator, :tvos_simulator]

  @doc "The lowest version of `os` an app runs on: Apple's version, or Android's API level."
  @spec minimum(os()) :: String.t()
  def minimum(os), do: Map.fetch!(@minimum, os)

  @doc "The path of `platform`'s SDK."
  @spec sdk_path(t()) :: String.t()
  def sdk_path(%__MODULE__{sdk: sdk}) when is_binary(sdk),
    do: Shell.output!("xcrun", ["-sdk", sdk, "--show-sdk-path"])

  @doc "The Android SDK's folder."
  @spec android_sdk() :: String.t()
  def android_sdk,
    do: System.get_env("ANDROID_HOME") || Path.expand("~/Library/Android/sdk")

  defp ndk! do
    case System.get_env("ANDROID_NDK_HOME") do
      nil -> newest_ndk!()
      path -> path
    end
  end

  defp newest_ndk! do
    root = Path.join(android_sdk(), "ndk")

    case root |> Path.join("*") |> Path.wildcard() |> Enum.sort_by(&version/1, :desc) do
      [newest | _] ->
        newest

      [] ->
        Mix.raise(
          "No Android NDK under #{root}. Install one with sdkmanager \"ndk;<version>\", or set ANDROID_NDK_HOME."
        )
    end
  end

  defp version(path),
    do: path |> Path.basename() |> String.split(".") |> Enum.map(&String.to_integer/1)
end
