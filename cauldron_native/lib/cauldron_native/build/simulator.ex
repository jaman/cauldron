defmodule CauldronNative.Build.Simulator do
  @moduledoc """
  Apple's simulators on this Mac, through `xcrun simctl`: choosing one for an app,
  starting it, and installing and starting the app in it.

  A simulator is chosen by its name or identifier (`--device "iPhone Duo"`), the newest
  runtime's first when several share a name; without one, the simulator of that system
  already running is used. The simulator is shown in Xcode's Simulator app, or in
  DeviceHub where Xcode has that instead. Simulators are made in Xcode under Window →
  Devices and Simulators, or with `xcrun simctl create`.
  """

  alias CauldronNative.Build.{App, Platform, Shell}

  @runtimes %{
    ios: "com.apple.CoreSimulator.SimRuntime.iOS-",
    tvos: "com.apple.CoreSimulator.SimRuntime.tvOS-"
  }

  @doc """
  The identifier of the `os` simulator named or identified by `wanted`, or of the one
  running when `wanted` is `nil`; started and shown in the Simulator app. Raises, naming
  the simulators there are, when none fits.
  """
  @spec device!(Platform.os(), String.t() | nil) :: String.t()
  def device!(os, wanted) do
    devices = devices(os)

    case chosen(devices, wanted) do
      nil -> Mix.raise(none_fits(os, devices, wanted))
      device -> started!(device)
    end
  end

  @doc "Install the `.app` at `bundle` in the simulator `device`."
  @spec install!(String.t(), String.t(), String.t()) :: :ok
  def install!(bundle, device, log),
    do: Shell.run!("xcrun", ["simctl", "install", device, bundle], log: log)

  @doc "Start `app` in the simulator `device`, its output streamed here until it exits."
  @spec run!(App.t(), String.t()) :: :ok
  def run!(app, device) do
    {_, _status} =
      System.cmd(
        "xcrun",
        ["simctl", "launch", "--console-pty", "--terminate-running-process", device, app.id],
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

    :ok
  end

  defp devices(os) do
    prefix = Map.fetch!(@runtimes, os)
    listing = Shell.output!("xcrun", ["simctl", "list", "devices", "available", "--json"])

    listing
    |> JSON.decode!()
    |> Map.fetch!("devices")
    |> Enum.filter(fn {runtime, _devices} -> String.starts_with?(runtime, prefix) end)
    |> Enum.sort_by(fn {runtime, _devices} -> runtime_version(runtime, prefix) end, :desc)
    |> Enum.flat_map(fn {_runtime, devices} -> devices end)
  end

  defp runtime_version(runtime, prefix),
    do:
      runtime
      |> String.replace_prefix(prefix, "")
      |> String.split("-")
      |> Enum.map(&String.to_integer/1)

  defp chosen(devices, nil), do: Enum.find(devices, &(&1["state"] == "Booted"))

  defp chosen(devices, wanted),
    do: Enum.find(devices, &(&1["udid"] == wanted or &1["name"] == wanted))

  defp started!(%{"udid" => udid, "state" => "Booted"}), do: shown(udid)

  defp started!(%{"udid" => udid}) do
    _ = Shell.output!("xcrun", ["simctl", "boot", udid])
    _ = Shell.output!("xcrun", ["simctl", "bootstatus", udid, "-b"])
    shown(udid)
  end

  defp shown(udid) do
    simulator = ["-b", "com.apple.iphonesimulator", "--args", "-CurrentDeviceUDID", udid]

    case System.cmd("open", simulator, stderr_to_stdout: true) do
      {_, 0} -> udid
      {_, _missing} -> device_hub(udid)
    end
  end

  defp device_hub(udid) do
    _ = Shell.output!("open", ["-b", "com.apple.dt.Devices"])
    udid
  end

  defp none_fits(os, [], _wanted),
    do:
      "There is no #{os} simulator. Add a runtime in Xcode → Settings → Components, then a simulator under Window → Devices and Simulators."

  defp none_fits(os, devices, wanted) do
    names = devices |> Enum.map(&"  #{&1["name"]} (#{&1["udid"]})") |> Enum.uniq()

    lead =
      if wanted,
        do: "No #{os} simulator is called #{wanted}",
        else: "No #{os} simulator is running"

    Enum.join([lead <> "; name one with --device:" | names], "\n")
  end
end
