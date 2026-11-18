import SwiftUI

struct NodeGauge: View {
    let node: UINode

    private var value: Double { node.double("value") ?? 0 }
    private var low: Double { node.double("min") ?? 0 }
    private var high: Double { max(node.double("max") ?? 1, low + 0.0001) }
    private var clamped: Double { min(max(value, low), high) }

    var body: some View {
        #if os(tvOS)
        VStack(alignment: .leading) {
            if let title = node.string("title") { Text(title) }
            ProgressView(value: clamped - low, total: high - low)
        }
        #else
        switch node.string("style") {
        case "circular":
            Gauge(value: clamped, in: low...high) { EmptyView() } currentValueLabel: { current }
                .gaugeStyle(.accessoryCircularCapacity)
        case "segmented":
            VStack(alignment: .leading, spacing: 4) {
                if let title = node.string("title") { Text(title) }
                HStack(spacing: 3) {
                    ForEach(0..<max(Int(high), 1), id: \.self) { index in
                        Capsule().fill(.tint).opacity(Double(index) < value ? 1 : 0.35)
                    }
                }
                .frame(height: 11)
            }
        default:
            Gauge(value: clamped, in: low...high) {
                if let title = node.string("title") { Text(title) }
            } currentValueLabel: { current }
        }
        #endif
    }

    @ViewBuilder private var current: some View {
        if let images = node.props["image"] as? [String] {
            ZStack { ForEach(images, id: \.self) { Image($0).resizable().scaledToFit() } }
        } else if let text = node.string("current") {
            Text(text)
        }
    }
}
