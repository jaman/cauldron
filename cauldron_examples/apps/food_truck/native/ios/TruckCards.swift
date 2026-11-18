import SwiftUI

private var tileFill: Color {
    #if os(macOS)
    Color(nsColor: .quaternaryLabelColor).opacity(0.5)
    #elseif os(tvOS)
    Color.secondary.opacity(0.15)
    #else
    Color(uiColor: .tertiarySystemFill)
    #endif
}

private var tagFill: Color {
    #if os(macOS)
    Color(nsColor: .quaternaryLabelColor).opacity(0.5)
    #elseif os(tvOS)
    Color.secondary.opacity(0.1)
    #else
    Color(uiColor: .quaternarySystemFill)
    #endif
}

struct OrderTilesView: CauldronNativeView {
    static let name = "order_tiles"
    let node: UINode
    let events: UIEvents

    init(node: UINode, events: UIEvents) {
        self.node = node
        self.events = events
    }

    var body: some View {
        let orders = node.props["orders"] as? [[String: Any]] ?? []
        HeroSquareTilingLayout {
            ForEach(orders.indices, id: \.self) { index in
                let order = orders[index]
                let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
                DonutStack(donuts: order["donuts"] as? [[String]] ?? [])
                    .padding(6)
                    .background(tileFill, in: shape)
                    .overlay { shape.strokeBorder(.quaternary, lineWidth: 0.5) }
                    .id(order["number"] as? NSNumber)
                    .transition(.asymmetric(
                        insertion: .offset(x: -100).combined(with: .opacity),
                        removal: .scale.combined(with: .opacity)
                    ))
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .aspectRatio(2, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: 250)
        .animation(.spring(response: 0.4, dampingFraction: 1), value: orders.compactMap { ($0["number"] as? NSNumber)?.intValue })
        .accessibilityHidden(true)
    }
}

struct HeroSquareTilingLayout: Layout {
    var spacing: Double = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let size = proposal.replacingUnspecifiedDimensions(by: CGSize(width: 100, height: 100))
        let hero = min((size.width - spacing) * 0.5, size.height)
        return CGSize(width: hero * 2 + spacing, height: hero)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let hero = min((bounds.width - spacing) * 0.5, bounds.height)
        let width = hero * 2 + spacing
        let half = CGSize(width: hero, height: hero)
        let origin = CGPoint(x: bounds.origin.x + (bounds.width - width) * 0.5, y: bounds.origin.y + (bounds.height - hero) * 0.5)
        let tile = (hero - 10) * 0.5
        let tiles = CGRect(origin: CGPoint(x: origin.x + hero + spacing, y: origin.y), size: half)
        for index in subviews.indices {
            if index == 0 {
                subviews[index].place(at: origin, anchor: .topLeading, proposal: ProposedViewSize(half))
            } else {
                let x: Double = (index - 1) % 2 == 0 ? 0 : 1
                let y: Double = index - 1 < 2 ? 0 : 1
                subviews[index].place(
                    at: CGPoint(x: tiles.minX + x * tiles.width, y: tiles.minY + y * tiles.height),
                    anchor: UnitPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: tile, height: tile)
                )
            }
        }
    }
}

struct DonutLatticeView: CauldronNativeView {
    static let name = "donut_lattice"
    let node: UINode
    let events: UIEvents

    init(node: UINode, events: UIEvents) {
        self.node = node
        self.events = events
    }

    var body: some View {
        let donuts = node.props["donuts"] as? [[String]] ?? []
        DonutLatticeLayout {
            ForEach(Array(donuts.prefix(14).enumerated()), id: \.offset) { entry in
                DonutLayers(layers: entry.element)
            }
        }
        .frame(minHeight: 180, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

struct DonutLatticeLayout: Layout {
    var columns = 5
    var rows = 3
    var spacing: Double = 10

    private let unbounded = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let size = proposal.replacingUnspecifiedDimensions(by: unbounded)
        let cell = min(size.width / Double(columns), size.height / Double(rows))
        return CGSize(width: cell * Double(columns), height: cell * Double(rows))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let size = proposal.replacingUnspecifiedDimensions(by: unbounded)
        let cell = min(size.width / Double(columns), size.height / Double(rows))
        let used = CGSize(width: cell * Double(columns), height: cell * Double(rows))
        let origin = CGPoint(x: bounds.minX + (bounds.width - used.width), y: bounds.minY + (bounds.height - used.height))
        var index = 0
        for row in 0..<rows {
            let even = row.isMultiple(of: 2)
            for column in 0..<(even ? columns : columns - 1) {
                guard index < subviews.count else { return }
                let x = origin.x + cell * Double(column) + (even ? 0 : cell * 0.5)
                let rect = CGRect(x: x, y: origin.y + cell * Double(row), width: cell, height: cell)
                    .insetBy(dx: spacing * 0.5, dy: spacing * 0.5)
                subviews[index].place(at: rect.origin, proposal: ProposedViewSize(rect.size))
                index += 1
            }
        }
    }
}

struct TagFlowView: CauldronNativeView {
    static let name = "tag_flow"
    let node: UINode
    let events: UIEvents

    init(node: UINode, events: UIEvents) {
        self.node = node
        self.events = events
    }

    var body: some View {
        let tags = node.props["tags"] as? [[String: Any]] ?? []
        let leading = node.string("alignment") == "leading"
        FlowLayout(alignment: leading ? .topLeading : .center) {
            ForEach(tags.indices, id: \.self) { index in
                TagLabel(tag: tags[index])
            }
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .center)
    }
}

struct TagLabel: View {
    let tag: [String: Any]
    @ScaledMetric(relativeTo: .footnote) private var iconWidth = 14.0

    var body: some View {
        HStack {
            icon
                .foregroundStyle(.secondary)
                .frame(width: iconWidth)
            Text(tag["title"] as? String ?? "")
        }
        .padding(6)
        .background(tagFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .font(.caption)
    }

    @ViewBuilder private var icon: some View {
        switch tag["kind"] as? String {
        case "donut": DonutLayers(layers: tag["layers"] as? [String] ?? []).padding(-3)
        case "city": Image(systemName: "building.2")
        default: Image(systemName: "tag")
        }
    }
}

struct FlowLayout: Layout {
    var alignment: Alignment = .center
    var spacing: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        Flow(width: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing).bounds
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let flow = Flow(width: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        let across = alignment.horizontal == .leading ? 0.0 : alignment.horizontal == .trailing ? 1.0 : 0.5
        let down = alignment.vertical == .top ? 0.0 : alignment.vertical == .bottom ? 1.0 : 0.5
        for row in flow.rows {
            let rowX = (bounds.width - row.frame.width) * across
            for index in row.range {
                let x = rowX + row.frame.minX + row.offsets[index - row.range.lowerBound] + bounds.minX
                let y = row.frame.minY + (row.frame.height - subviews[index].sizeThatFits(.unspecified).height) * down + bounds.minY
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            }
        }
    }

    struct Row {
        var range: Range<Int>
        var offsets: [Double]
        var frame: CGRect
    }

    struct Flow {
        var bounds = CGSize.zero
        var rows: [Row] = []

        init(width: Double, subviews: Subviews, spacing: CGFloat?) {
            let available = width.isFinite ? width : .greatestFiniteMagnitude
            var start = 0
            var remaining = available
            var top = 0.0
            var height = 0.0
            var offsets: [Double] = []
            let gap = spacing ?? ViewSpacing().distance(to: ViewSpacing(), along: .vertical)

            func before(_ index: Int) -> Double {
                guard index > start else { return 0 }
                return spacing ?? subviews[index - 1].spacing.distance(to: subviews[index].spacing, along: .horizontal)
            }

            func finish(_ end: Int) {
                let used = available - remaining
                rows.append(Row(range: start..<end, offsets: offsets, frame: CGRect(x: 0, y: top, width: used, height: height)))
                bounds.width = max(bounds.width, used)
                bounds.height += height + (rows.count > 1 ? gap : 0)
                top += height + gap
                start = end
                height = 0
                offsets = []
                remaining = available
            }

            for index in subviews.indices {
                let ideal = subviews[index].sizeThatFits(.unspecified)
                if index > start && ideal.width + before(index) > remaining { finish(index) }
                let lead = before(index)
                offsets.append(available - remaining + lead)
                remaining -= ideal.width + lead
                height = max(height, ideal.height)
            }
            if start < subviews.count { finish(subviews.count) }
        }
    }
}
