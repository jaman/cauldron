import SwiftUI

struct FlavorProfileView: CauldronNativeView {
    static let name = "flavor_profile"
    let node: UINode
    let events: UIEvents

    init(node: UINode, events: UIEvents) {
        self.node = node
        self.events = events
    }

    var body: some View {
        let flavors = node.props["flavors"] as? [[String: Any]] ?? []
        let top = max(node.double("top") ?? 1, 1)
        Grid {
            ForEach(flavors.indices, id: \.self) { index in
                let flavor = flavors[index]
                let strongest = flavor["strongest"] as? Bool ?? false
                let value = max((flavor["value"] as? NSNumber)?.doubleValue ?? 0, 0)
                GridRow {
                    symbol(flavor)
                        .foregroundStyle(strongest ? .primary : .secondary)
                    Text(flavor["title"] as? String ?? "")
                        .gridCellAnchor(.leading)
                        .foregroundStyle(strongest ? .primary : .secondary)
                    #if os(tvOS)
                    ProgressView(value: value, total: top)
                        .tint(strongest ? Color.accentColor : Color.secondary)
                    #else
                    Gauge(value: value, in: 0...top) { EmptyView() }
                        .tint(strongest ? Color.accentColor : Color.secondary)
                        .labelsHidden()
                    #endif
                    Text(Int(value).formatted())
                        .gridCellAnchor(.trailing)
                        .foregroundStyle(strongest ? .primary : .secondary)
                }
            }
        }
    }

    private func symbol(_ flavor: [String: Any]) -> Image {
        if let asset = flavor["asset"] as? String { return Image(asset) }
        return Image(systemName: flavor["ios"] as? String ?? "circle")
    }
}
