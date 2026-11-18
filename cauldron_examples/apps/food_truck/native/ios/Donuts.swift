import SwiftUI

let donutThumbnailSize: Double = 128

struct DonutLayers: View {
    let layers: [String]

    var body: some View {
        GeometryReader { proxy in
            let suffix = min(proxy.size.width, proxy.size.height) <= donutThumbnailSize ? "thumb" : "full"
            ZStack {
                ForEach(layers, id: \.self) { layer in
                    Image("\(layer)-\(suffix)")
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFit()
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .compositingGroup()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct DonutView: CauldronNativeView {
    static let name = "donut"
    let node: UINode
    let events: UIEvents

    init(node: UINode, events: UIEvents) {
        self.node = node
        self.events = events
    }

    var body: some View {
        let layers = node.props["layers"] as? [String] ?? []
        if let background = node.string("background") {
            DonutAvatar(layers: layers, background: background)
        } else {
            DonutLayers(layers: layers)
                .accessibilityHidden(true)
        }
    }
}

struct DonutAvatar: View {
    let layers: [String]
    let background: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        DonutLayers(layers: layers)
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            .padding(.top, 5)
            .padding([.horizontal, .bottom], 6)
            .background(Color(background).gradient, in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(lineWidth: 0.5)
                    .foregroundStyle(.tertiary)
                    .blendMode(colorScheme == .light ? .plusDarker : .plusLighter)
            }
            .accessibilityHidden(true)
    }
}

struct DonutStack: View {
    let donuts: [[String]]
    var overflow = false

    var body: some View {
        DiagonalDonutStackLayout {
            ForEach(Array(donuts.prefix(3).enumerated()), id: \.offset) { entry in
                DonutLayers(layers: entry.element)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            let extra = donuts.count - 3
            if extra > 0 && overflow {
                Text("+\(extra)")
                    .foregroundStyle(.secondary)
                    .font(.caption2)
                    .padding(4)
                    .background(.thinMaterial, in: Capsule())
                    .padding(4)
            }
        }
    }
}

struct DonutStackView: CauldronNativeView {
    static let name = "donut_stack"
    let node: UINode
    let events: UIEvents

    init(node: UINode, events: UIEvents) {
        self.node = node
        self.events = events
    }

    var body: some View {
        DonutStack(donuts: node.props["donuts"] as? [[String]] ?? [], overflow: node.bool("overflow"))
            .accessibilityHidden(true)
    }
}

struct DiagonalDonutStackLayout: Layout {
    private let fallback = CGSize(width: 60, height: 60)

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let size = proposal.replacingUnspecifiedDimensions(by: fallback)
        let side = min(size.width, size.height)
        return CGSize(width: side, height: side)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let proposed = proposal.replacingUnspecifiedDimensions(by: fallback)
        let side = min(proposed.width, proposed.height)
        let size = CGSize(width: side, height: side)
        let rect = CGRect(
            origin: CGPoint(x: bounds.minX + bounds.width - side, y: bounds.minY + bounds.height - side),
            size: size
        )
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let shown = subviews.prefix(3)
        for index in shown.indices {
            place(shown[index], index: index, count: shown.count, center: center, side: side, size: size)
        }
    }

    private func place(_ subview: LayoutSubview, index: Int, count: Int, center: CGPoint, side: CGFloat, size: CGSize) {
        let direction: CGFloat = index == 0 ? -1 : 1
        switch (index, count) {
        case (_, 1):
            subview.place(at: center, anchor: .center, proposal: ProposedViewSize(size))
        case (_, 2):
            subview.place(
                at: CGPoint(x: center.x + side * direction * 0.15, y: center.y + side * direction * 0.20),
                anchor: .center,
                proposal: ProposedViewSize(CGSize(width: size.width * 0.7, height: size.height * 0.7))
            )
        case (1, 3):
            subview.place(
                at: center,
                anchor: .center,
                proposal: ProposedViewSize(CGSize(width: size.width * 0.65, height: size.height * 0.65))
            )
        default:
            subview.place(
                at: CGPoint(x: center.x + side * direction * 0.15, y: center.y + side * direction * 0.23),
                anchor: .center,
                proposal: ProposedViewSize(CGSize(width: size.width * 0.7, height: size.height * 0.65))
            )
        }
    }
}

struct DonutBoxView: CauldronNativeView {
    static let name = "donut_box"
    let node: UINode
    let events: UIEvents
    @State private var closed = false
    @State private var bounce = false

    init(node: UINode, events: UIEvents) {
        self.node = node
        self.events = events
    }

    var body: some View {
        GeometryReader { proxy in
            let length = min(proxy.size.width, proxy.size.height)
            ZStack {
                Image("box/Inside").resizable().scaledToFit()
                DonutLayers(layers: node.props["layers"] as? [String] ?? [])
                    .padding(floor(length * 0.15))
                    .frame(width: length, height: length)
                Image("box/Bottom").resizable().scaledToFit()
                if closed {
                    Image("box/Lid")
                        .resizable()
                        .scaledToFit()
                        .transition(
                            .scale(scale: 0.75, anchor: .bottom)
                                .combined(with: .offset(y: -length * 0.5))
                                .combined(with: .opacity)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .offset(y: bounce ? 15 : 0)
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .onTapGesture { Task { @MainActor in await toggle() } }
        .task { @MainActor in
            try? await Task.sleep(nanoseconds: 750_000_000)
            await toggle()
        }
        .accessibilityHidden(true)
    }

    @MainActor private func toggle() async {
        withAnimation(.spring(response: 0.35, dampingFraction: 1)) { closed.toggle() }
        guard closed else { return }
        try? await Task.sleep(nanoseconds: 150_000_000)
        withAnimation(.spring()) { bounce = true }
        try? await Task.sleep(nanoseconds: 150_000_000)
        withAnimation(.spring()) { bounce = false }
    }
}
