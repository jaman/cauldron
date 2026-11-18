defmodule CauldronNative.Build.NativeViews do
  @moduledoc """
  An app's own native views (`CauldronNative.UI.native/2`): the Swift files under the
  app's `native/ios` and the Kotlin files under its `native/android`, compiled into the
  app, and the registry that names each view.

  A Swift view is a `struct` that conforms to `CauldronNativeView`; a Kotlin view is an
  `object` that implements `CauldronNativeView`. Each gives its `name`, the one Elixir
  places it by:

      struct MapView: CauldronNativeView {
          static let name = "map_view"
          let node: UINode
          let events: UIEvents
          init(node: UINode, events: UIEvents) { self.node = node; self.events = events }
          var body: some View { ... }
      }

      object MapView : CauldronNativeView {
          override val name = "map_view"
          @Composable override fun Content(node: UiNode, events: UiEvents) { ... }
      }
  """

  alias CauldronNative.Build.App

  @doc "The app's native source files for `platform`."
  @spec files(App.t(), :ios | :android) :: [String.t()]
  def files(app, :ios), do: Path.wildcard(Path.join([app.native, "ios", "**", "*.swift"]))
  def files(app, :android), do: Path.wildcard(Path.join([app.native, "android", "**", "*.kt"]))

  @doc "The source of the registry naming every view in `files`, for `platform`."
  @spec registry(:ios | :android, [String.t()]) :: String.t()
  def registry(:ios, files) do
    entries =
      for type <- Enum.flat_map(files, &swift_views/1),
          do: "    #{type}.name: { AnyView(#{type}(node: $0, events: $1)) },\n"

    """
    import SwiftUI

    let cauldronNativeViews: [String: (UINode, UIEvents) -> AnyView] = [
    #{if entries == [], do: "    :\n", else: Enum.join(entries)}]
    """
  end

  def registry(:android, files) do
    objects = Enum.flat_map(files, &kotlin_views/1)

    """
    package cauldron.app

    val cauldronNativeViews: Map<String, CauldronNativeView> =
        listOf<CauldronNativeView>(#{Enum.join(objects, ", ")}).associateBy { it.name }
    """
  end

  defp swift_views(file) do
    ~r/\bstruct\s+(\w+)\s*:[^{]*\bCauldronNativeView\b/
    |> Regex.scan(File.read!(file), capture: :all_but_first)
    |> List.flatten()
  end

  defp kotlin_views(file) do
    text = File.read!(file)

    package =
      case Regex.run(~r/^\s*package\s+([\w.]+)/m, text, capture: :all_but_first) do
        [name] -> name <> "."
        nil -> ""
      end

    ~r/\bobject\s+(\w+)\s*:[^{]*\bCauldronNativeView\b/
    |> Regex.scan(text, capture: :all_but_first)
    |> List.flatten()
    |> Enum.map(&(package <> &1))
  end
end
