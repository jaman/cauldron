defmodule CauldronNative.Build.Widgets do
  @moduledoc """
  The iOS app's widget extension: a WidgetKit extension holding the app's widget kinds
  (`:widgets` in its config) and, with `:live_activities`, its Live Activity, built as a
  second target of the Xcode project and embedded in the app.

  The app and the extension share an App Group, `group.<app id>`, whose `Library/Widgets`
  folder holds each widget's content (`CauldronNative.Widget`). The extension's Swift is
  this package's `native/widgets`, with the widget list generated from the config.
  """

  alias CauldronNative.Build.App

  @families %{
    small: ".systemSmall",
    medium: ".systemMedium",
    large: ".systemLarge",
    extra_large: ".systemExtraLarge",
    circular: ".accessoryCircular",
    rectangular: ".accessoryRectangular",
    inline: ".accessoryInline"
  }

  @doc "Whether `app` on `os` has a widget extension."
  @spec extension?(App.t(), atom()) :: boolean()
  def extension?(app, :ios), do: app.widgets != [] or app.live_activities
  def extension?(_app, _os), do: false

  @doc "The App Group the app and its extension share."
  @spec group(App.t()) :: String.t()
  def group(app), do: "group." <> app.id

  @doc """
  Write the extension's files under `folder/Widgets` from this package's `source`; the
  names of its Swift sources.
  """
  @spec write!(App.t(), String.t(), String.t()) :: [String.t()]
  def write!(app, source, folder) do
    widgets = Path.join(folder, "Widgets")
    File.mkdir_p!(widgets)
    copied = Path.wildcard(Path.join([source, "native", "widgets", "*.swift"]))
    for file <- copied, do: File.cp!(file, Path.join(widgets, Path.basename(file)))
    File.write!(Path.join(widgets, "WidgetList.swift"), widget_list(app))
    File.write!(Path.join(widgets, "Info.plist"), info_plist(app))
    File.write!(Path.join(widgets, "Widgets.entitlements"), entitlements(app))
    Enum.map(copied, &Path.basename/1) ++ ["WidgetList.swift"]
  end

  @doc """
  The project's entries for the extension, given its Swift `sources` and the project's
  `id` function, `project` id and app `version`: `:objects` (the entries' text),
  `:target`, `:embed` (the app's phase that embeds it), `:dependency`, `:group` and
  `:product`.
  """
  @spec project(App.t(), [String.t()], (String.t(), String.t() -> String.t()), String.t()) ::
          map()
  def project(app, sources, id, project) do
    files =
      Enum.map_join(sources, "\n", fn file ->
        "\t\t#{id.("wbuild", file)} = {isa = PBXBuildFile; fileRef = #{id.("wref", file)}; };\n" <>
          "\t\t#{id.("wref", file)} = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = #{file}; sourceTree = \"<group>\"; };"
      end)

    objects = """
    #{files}
    \t\t#{id.("wref", "Widgets.appex")} = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = Widgets.appex; sourceTree = BUILT_PRODUCTS_DIR; };
    \t\t#{id.("wbuild", "Widgets.appex")} = {isa = PBXBuildFile; fileRef = #{id.("wref", "Widgets.appex")}; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
    \t\t#{id.("wgroup", "Widgets")} = {isa = PBXGroup; children = (#{Enum.map_join(sources, ", ", &id.("wref", &1))}); path = Widgets; sourceTree = "<group>"; };
    \t\t#{id.("wphase", "embed")} = {isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = (#{id.("wbuild", "Widgets.appex")}); name = "Embed Foundation Extensions"; runOnlyForDeploymentPostprocessing = 0; };
    \t\t#{id.("wphase", "sources")} = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (#{Enum.map_join(sources, ", ", &id.("wbuild", &1))}); runOnlyForDeploymentPostprocessing = 0; };
    \t\t#{id.("wbuild", "Assets.xcassets")} = {isa = PBXBuildFile; fileRef = #{id.("ref", "Assets.xcassets")}; };
    \t\t#{id.("wphase", "resources")} = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (#{id.("wbuild", "Assets.xcassets")}); runOnlyForDeploymentPostprocessing = 0; };
    \t\t#{id.("wphase", "frameworks")} = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
    \t\t#{id.("wtarget", "Widgets")} = {isa = PBXNativeTarget; buildConfigurationList = #{id.("wlist", "Widgets")}; buildPhases = (#{id.("wphase", "sources")}, #{id.("wphase", "frameworks")}, #{id.("wphase", "resources")}); buildRules = (); dependencies = (); name = Widgets; productName = Widgets; productReference = #{id.("wref", "Widgets.appex")}; productType = "com.apple.product-type.app-extension"; };
    \t\t#{id.("wproxy", "Widgets")} = {isa = PBXContainerItemProxy; containerPortal = #{project}; proxyType = 1; remoteGlobalIDString = #{id.("wtarget", "Widgets")}; remoteInfo = Widgets; };
    \t\t#{id.("wdependency", "Widgets")} = {isa = PBXTargetDependency; target = #{id.("wtarget", "Widgets")}; targetProxy = #{id.("wproxy", "Widgets")}; };
    \t\t#{id.("wconfig", "Widgets")} = {isa = XCBuildConfiguration; buildSettings = {#{settings(app)}}; name = Release; };
    \t\t#{id.("wlist", "Widgets")} = {isa = XCConfigurationList; buildConfigurations = (#{id.("wconfig", "Widgets")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };
    """

    %{
      objects: objects,
      target: id.("wtarget", "Widgets"),
      embed: id.("wphase", "embed"),
      dependency: id.("wdependency", "Widgets"),
      group: id.("wgroup", "Widgets"),
      product: id.("wref", "Widgets.appex")
    }
  end

  defp team_settings(%App{team: nil}), do: []
  defp team_settings(%App{team: team}), do: [DEVELOPMENT_TEAM: team]

  defp settings(app) do
    (team_settings(app) ++
       [
         APPLICATION_EXTENSION_API_ONLY: "YES",
         CODE_SIGN_ENTITLEMENTS: "Widgets/Widgets.entitlements",
         CODE_SIGN_STYLE: "Automatic",
         CURRENT_PROJECT_VERSION: App.build_number(app),
         GENERATE_INFOPLIST_FILE: "NO",
         INFOPLIST_FILE: "Widgets/Info.plist",
         LD_RUNPATH_SEARCH_PATHS:
           "\"@executable_path/Frameworks @executable_path/../../Frameworks\"",
         MARKETING_VERSION: app.version,
         PRODUCT_BUNDLE_IDENTIFIER: app.id <> ".widgets",
         PRODUCT_NAME: "Widgets",
         SKIP_INSTALL: "YES",
         SWIFT_VERSION: "5.0",
         TARGETED_DEVICE_FAMILY: "\"1,2\""
       ])
    |> Enum.map_join(" ", fn {key, value} -> "#{key} = #{value};" end)
  end

  defp widget_list(app) do
    structs =
      Enum.map_join(app.widgets, "\n", fn widget ->
        families = Enum.map_join(widget.sizes, ", ", &Map.fetch!(@families, &1))

        """
        struct CauldronWidget_#{widget.kind}: Widget {
            var body: some WidgetConfiguration {
                StaticConfiguration(kind: "#{widget.kind}", provider: WidgetTimeline(kind: "#{widget.kind}")) { entry in
                    WidgetBody(entry: entry, name: #{inspect(widget.name)})
                }
                .configurationDisplayName(#{inspect(widget.name)})
                .description(#{inspect(widget.description)})
                .supportedFamilies([#{families}])
            }
        }
        """
      end)

    members =
      Enum.map(app.widgets, &"        CauldronWidget_#{&1.kind}()") ++
        if(app.live_activities, do: ["        CauldronLiveActivity()"], else: [])

    """
    import SwiftUI
    import WidgetKit

    #{structs}
    @main
    struct CauldronWidgets: WidgetBundle {
        var body: some Widget {
    #{Enum.join(members, "\n")}
        }
    }
    """
  end

  defp info_plist(app) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleDevelopmentRegion</key><string>en</string>
      <key>CFBundleDisplayName</key><string>#{app.name}</string>
      <key>CFBundleExecutable</key><string>$(EXECUTABLE_NAME)</string>
      <key>CFBundleIdentifier</key><string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
      <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
      <key>CFBundleName</key><string>$(PRODUCT_NAME)</string>
      <key>CFBundlePackageType</key><string>XPC!</string>
      <key>CFBundleShortVersionString</key><string>#{app.version}</string>
      <key>CFBundleVersion</key><string>#{App.build_number(app)}</string>
      <key>CauldronAppGroup</key><string>#{group(app)}</string>
      <key>NSExtension</key>
      <dict>
        <key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string>
      </dict>
    </dict>
    </plist>
    """
  end

  defp entitlements(app) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>com.apple.security.application-groups</key><array><string>#{group(app)}</string></array>
    </dict>
    </plist>
    """
  end
end
