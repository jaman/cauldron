defmodule CauldronNative.Build.StoreKit do
  @moduledoc """
  The Xcode project's StoreKit testing: `App.storekit`, a StoreKit configuration with
  the app's products (`:purchases` in its config) at their configured names and prices,
  and the shared `App` scheme, which runs the app with it. An app run from Xcode then
  buys from the configuration instead of the App Store; Xcode's Debug ▸ StoreKit ▸
  Manage Transactions shows and changes the purchases.
  """

  alias CauldronNative.Build.App

  @types %{consumable: "Consumable", non_consumable: "NonConsumable"}
  @periods %{
    week: "P1W",
    month: "P1M",
    two_months: "P2M",
    quarter: "P3M",
    half_year: "P6M",
    year: "P1Y"
  }

  @doc "Write `App.storekit` into `folder` and the scheme into `project`, whose app target is `target`."
  @spec write!(App.t(), String.t(), String.t(), String.t()) :: :ok
  def write!(app, folder, project, target) do
    File.write!(Path.join(folder, "App.storekit"), configuration(app))
    schemes = Path.join(project, "xcshareddata/xcschemes")
    File.mkdir_p!(schemes)
    File.write!(Path.join(schemes, "App.xcscheme"), scheme(target))
  end

  defp configuration(app) do
    {subscriptions, products} = Enum.split_with(app.purchases, &(&1.type == :subscription))

    JSON.encode!(%{
      identifier: uuid(app.id),
      nonRenewingSubscriptions: [],
      products: Enum.map(products, &product(app, &1)),
      settings: %{},
      subscriptionGroups: groups(app, subscriptions),
      version: %{major: 4, minor: 0}
    })
  end

  defp product(app, purchase) do
    %{
      displayPrice: purchase.price,
      familyShareable: false,
      internalID: internal_id(app, purchase),
      localizations: localizations(purchase),
      productID: app.id <> "." <> Atom.to_string(purchase.key),
      referenceName: purchase.name,
      type: Map.fetch!(@types, purchase.type)
    }
  end

  defp groups(_app, []), do: []

  defp groups(app, subscriptions) do
    group = internal_id(app, %{key: :subscriptions})

    [
      %{
        id: group,
        localizations: [],
        name: app.name,
        subscriptions:
          subscriptions
          |> Enum.with_index(1)
          |> Enum.map(fn {purchase, rank} -> subscription(app, purchase, rank, group) end)
      }
    ]
  end

  defp subscription(app, purchase, rank, group) do
    app
    |> product(%{purchase | type: :non_consumable})
    |> Map.merge(%{
      adHocOffers: [],
      codeOffers: [],
      groupNumber: rank,
      introductoryOffer: intro(app, purchase),
      recurringSubscriptionPeriod: Map.fetch!(@periods, purchase.period),
      subscriptionGroupID: group,
      type: "RecurringSubscription",
      winbackOffers: []
    })
  end

  @modes %{pay_as_you_go: "payAsYouGo", pay_up_front: "payUpFront", free: "free"}

  defp intro(_app, %{intro: nil}), do: nil

  defp intro(app, %{intro: intro} = purchase) do
    offer = %{
      displayPrice: intro.price,
      internalID: internal_id(app, %{key: :"#{purchase.key}_intro"}),
      paymentMode: Map.fetch!(@modes, intro.mode),
      subscriptionPeriod: Map.fetch!(@periods, intro.period)
    }

    if intro.mode == :pay_as_you_go,
      do: Map.put(offer, :numberOfPeriods, intro.periods),
      else: offer
  end

  defp localizations(purchase),
    do: [%{description: purchase.description, displayName: purchase.name, locale: "en_US"}]

  defp internal_id(app, purchase) do
    :crypto.hash(:md5, app.id <> ":" <> Atom.to_string(purchase.key))
    |> :binary.decode_unsigned()
    |> rem(1_000_000_000)
    |> Kernel.+(6_000_000_000)
    |> Integer.to_string()
  end

  defp uuid(seed) do
    <<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4),
      e::binary-size(12)>> =
      :crypto.hash(:md5, seed) |> Base.encode16()

    Enum.join([a, b, c, d, e], "-")
  end

  defp scheme(target) do
    reference = """
    <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "#{target}" BuildableName = "App.app" BlueprintName = "App" ReferencedContainer = "container:App.xcodeproj"></BuildableReference>
    """

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <Scheme LastUpgradeVersion = "1600" version = "1.7">
       <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
          <BuildActionEntries>
             <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
                #{reference}
             </BuildActionEntry>
          </BuildActionEntries>
       </BuildAction>
       <LaunchAction buildConfiguration = "Release" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
          <BuildableProductRunnable runnableDebuggingMode = "0">
             #{reference}
          </BuildableProductRunnable>
          <StoreKitConfigurationFileReference identifier = "../App.storekit"></StoreKitConfigurationFileReference>
       </LaunchAction>
       <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
          <BuildableProductRunnable runnableDebuggingMode = "0">
             #{reference}
          </BuildableProductRunnable>
       </ProfileAction>
       <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"></ArchiveAction>
    </Scheme>
    """
  end
end
