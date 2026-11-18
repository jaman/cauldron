defmodule CauldronNative.Build.Privacy do
  @moduledoc """
  The iOS privacy manifest (`PrivacyInfo.xcprivacy`) every app carries for the App
  Store: whether the app tracks users, the domains it tracks with, the data it collects,
  and the reasons for the system interfaces Apple asks a reason for.

  The reasons for the interfaces Cauldron's runtime uses are written for every app: file
  timestamps inside the app's own storage (`C617.1`), the time since the phone started,
  for measuring elapsed time (`35F9.1`), and the app's own settings storage (`CA92.1`).

  The rest comes from the app's `:privacy` config:

      privacy: [
        tracking: false,
        tracking_domains: [],
        collects: [
          email: [linked: true, tracking: false, purposes: [:app_functionality]],
          crash_data: [linked: false, purposes: [:analytics]]
        ]
      ]

  Each collected type is one of the atoms in `types/0`, with `linked` (tied to the user's
  identity), `tracking` (used to track them across other companies' apps and sites) and
  `purposes`, any of `:third_party_advertising`, `:developer_advertising`, `:analytics`,
  `:personalization`, `:app_functionality` and `:other`. The same answers are what App
  Store Connect's privacy questions and Google Play's data safety form ask.
  """

  @types %{
    name: "Name",
    email: "EmailAddress",
    phone: "PhoneNumber",
    address: "PhysicalAddress",
    other_contact: "OtherUserContactInfo",
    health: "Health",
    fitness: "Fitness",
    payment: "PaymentInfo",
    credit: "CreditInfo",
    other_financial: "OtherFinancialInfo",
    precise_location: "PreciseLocation",
    coarse_location: "CoarseLocation",
    sensitive: "SensitiveInfo",
    contacts: "Contacts",
    messages: "EmailsOrTextMessages",
    photos_or_videos: "PhotosorVideos",
    audio: "AudioData",
    gameplay: "GameplayContent",
    customer_support: "CustomerSupport",
    other_content: "OtherUserContent",
    browsing_history: "BrowsingHistory",
    search_history: "SearchHistory",
    user_id: "UserID",
    device_id: "DeviceID",
    purchases: "PurchaseHistory",
    product_interaction: "ProductInteraction",
    advertising_data: "AdvertisingData",
    other_usage: "OtherUsageData",
    crash_data: "CrashData",
    performance: "PerformanceData",
    other_diagnostics: "OtherDiagnosticData",
    environment_scanning: "EnvironmentScanning",
    hands: "Hands",
    head: "Head",
    other: "OtherDataTypes"
  }

  @purposes %{
    third_party_advertising: "ThirdPartyAdvertising",
    developer_advertising: "DeveloperAdvertising",
    analytics: "Analytics",
    personalization: "ProductPersonalization",
    app_functionality: "AppFunctionality",
    other: "Other"
  }

  @reasons [
    {"NSPrivacyAccessedAPICategoryFileTimestamp", "C617.1"},
    {"NSPrivacyAccessedAPICategorySystemBootTime", "35F9.1"},
    {"NSPrivacyAccessedAPICategoryUserDefaults", "CA92.1"}
  ]

  @doc "The data types `:collects` takes."
  @spec types() :: [atom()]
  def types, do: @types |> Map.keys() |> Enum.sort()

  @doc "The `:privacy` config, checked; raises naming what is wrong."
  @spec validate!(keyword()) :: keyword()
  def validate!(privacy) do
    for {type, opts} <- Keyword.get(privacy, :collects, []) do
      unless Map.has_key?(@types, type),
        do:
          Mix.raise(":privacy collects #{inspect(type)}, which is not one of #{inspect(types())}")

      for purpose <- Keyword.get(opts, :purposes, []),
          not Map.has_key?(@purposes, purpose),
          do:
            Mix.raise(
              ":privacy's #{inspect(type)} has purpose #{inspect(purpose)}, not one of #{inspect(Map.keys(@purposes))}"
            )
    end

    privacy
  end

  @doc "The manifest for the `:privacy` config, as a property list."
  @spec manifest(keyword()) :: String.t()
  def manifest(privacy) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>NSPrivacyTracking</key>#{boolean(Keyword.get(privacy, :tracking, false))}
      <key>NSPrivacyTrackingDomains</key>
      <array>#{Enum.map_join(Keyword.get(privacy, :tracking_domains, []), &"<string>#{&1}</string>")}</array>
      <key>NSPrivacyCollectedDataTypes</key>
      <array>
    #{Enum.map_join(Keyword.get(privacy, :collects, []), "\n", &collected/1)}
      </array>
      <key>NSPrivacyAccessedAPITypes</key>
      <array>
    #{Enum.map_join(@reasons, "\n", &reason/1)}
      </array>
    </dict>
    </plist>
    """
  end

  defp collected({type, opts}) do
    purposes =
      opts
      |> Keyword.get(:purposes, [:app_functionality])
      |> Enum.map_join(
        &"<string>NSPrivacyCollectedDataTypePurpose#{Map.fetch!(@purposes, &1)}</string>"
      )

    """
        <dict>
          <key>NSPrivacyCollectedDataType</key><string>NSPrivacyCollectedDataType#{Map.fetch!(@types, type)}</string>
          <key>NSPrivacyCollectedDataTypeLinked</key>#{boolean(Keyword.get(opts, :linked, false))}
          <key>NSPrivacyCollectedDataTypeTracking</key>#{boolean(Keyword.get(opts, :tracking, false))}
          <key>NSPrivacyCollectedDataTypePurposes</key><array>#{purposes}</array>
        </dict>\
    """
  end

  defp reason({category, code}) do
    """
        <dict>
          <key>NSPrivacyAccessedAPIType</key><string>#{category}</string>
          <key>NSPrivacyAccessedAPITypeReasons</key><array><string>#{code}</string></array>
        </dict>\
    """
  end

  defp boolean(true), do: "<true/>"
  defp boolean(false), do: "<false/>"
end
