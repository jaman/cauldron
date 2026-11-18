import SwiftUI

struct PlusMarketingView: CauldronNativeView {
    static let name = "plus_marketing"
    let node: UINode
    let events: UIEvents
    #if os(macOS)
    @Environment(\.colorScheme) private var colorScheme
    #endif

    init(node: UINode, events: UIEvents) {
        self.node = node
        self.events = events
    }

    var body: some View {
        VStack(alignment: .center, spacing: 5) {
            Text("Get Social Feed+")
                .font(.title2)
                .bold()
            Text("The definitive social-feed experience")
                .font(.subheadline)
            Button {
                events.send("start")
            } label: {
                Text("Get Started")
                    .bold()
                    .padding(.vertical, 2)
                    #if os(macOS)
                    .foregroundStyle(colorScheme == .light ? Color.accentColor : .white)
                    #endif
            }
            #if os(macOS)
            .buttonStyle(.bordered)
            #else
            .buttonStyle(.borderedProminent)
            .foregroundStyle(Color.accentColor)
            #endif
            .tint(.white)
            .padding(.top)
        }
        .foregroundStyle(.white)
        .padding(10)
        .frame(maxWidth: .infinity)
        #if os(macOS)
        .background(.indigo.gradient)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        #else
        .listRowBackground(Rectangle().fill(.indigo.gradient))
        #endif
    }
}

struct SubscriptionStoreView: CauldronNativeView {
    static let name = "subscription_store"
    let node: UINode
    let events: UIEvents
    @State private var chosen: String?

    init(node: UINode, events: UIEvents) {
        self.node = node
        self.events = events
    }

    private var plans: [[String: Any]] { node.props["plans"] as? [[String: Any]] ?? [] }

    var body: some View {
        Group {
            #if os(macOS)
            VStack(spacing: 0) {
                header.frame(maxWidth: .infinity).background(.indigo.gradient)
                cells
            }
            .safeAreaInset(edge: .bottom) { purchase }
            .overlay(alignment: .topTrailing) { close.padding() }
            .frame(minWidth: 400, minHeight: 400)
            #else
            GeometryReader { proxy in
                if proxy.size.height > proxy.size.width {
                    VStack(spacing: 0) {
                        header.frame(maxWidth: .infinity).background(.indigo.gradient)
                        cells
                    }
                    .safeAreaInset(edge: .bottom) { purchase }
                    .overlay(alignment: .topTrailing) { close.padding() }
                } else {
                    HStack(spacing: 0) {
                        header.frame(maxWidth: .infinity, maxHeight: .infinity).background(.indigo.gradient)
                        Divider().ignoresSafeArea()
                        VStack {
                            cells.padding(.top, 30).frame(width: 400).ignoresSafeArea()
                            purchase.padding(.horizontal, 30)
                        }
                    }
                    .ignoresSafeArea()
                    .overlay(alignment: .topTrailing) { close.padding(.top, 8) }
                }
            }
            #endif
        }
        #if os(iOS)
        .background(Color(uiColor: .systemGray6))
        #endif
        .onAppear { if chosen == nil { chosen = plans.first?["key"] as? String } }
    }

    private var header: some View {
        VStack {
            Text("Social Feed+")
                .font(.largeTitle)
                .bold()
                .padding()
            Group {
                Text("Top social-media providers.")
                Text("Advanced engagement tools.")
                Text("All in one place.")
            }
            .font(.headline)
        }
        .padding(.top, 5)
        .padding(.bottom, 30)
        .foregroundStyle(.white)
    }

    private var cells: some View {
        ScrollView(.vertical) {
            VStack {
                ForEach(plans.indices, id: \.self) { index in
                    PlanCell(plan: plans[index], chosen: $chosen)
                }
                if let note = node.string("note") {
                    Text(note).font(.footnote).foregroundStyle(.secondary).padding()
                }
            }
            .padding(.top)
        }
    }

    private var purchase: some View {
        let plan = plans.first { $0["key"] as? String == chosen }
        return VStack {
            Button {
                if let chosen { events.send("subscribe", chosen) }
            } label: {
                Text(plan?["intro"] as? Bool == true ? "Start trial offer" : "Subscribe")
                    .bold()
                    .padding(5)
                    #if os(iOS)
                    .frame(maxWidth: .infinity)
                    #endif
            }
            .buttonStyle(.borderedProminent)
            .disabled(plan == nil)
            .padding(.horizontal)
            #if os(macOS)
            .tint(.accentColor)
            .controlSize(.large)
            #endif
            #if os(iOS)
            Button("Redeem an offer") { events.send("redeem") }
                .buttonStyle(.borderless)
                .padding(.top)
            #endif
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
        .background(.ultraThinMaterial)
    }

    private var close: some View {
        Button {
            events.send("close")
        } label: {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.secondary, .clear, Color.gray.opacity(0.3))
        }
        .buttonStyle(.borderless)
        .opacity(0.8)
        .font(.title)
        .accessibilityLabel("Close")
    }
}

struct PlanCell: View {
    let plan: [String: Any]
    @Binding var chosen: String?
    @Environment(\.colorScheme) private var colorScheme

    private var key: String { plan["key"] as? String ?? "" }
    private var on: Bool { chosen == key }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 16, style: .continuous) }

    private var fill: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #elseif os(tvOS)
        Color.secondary.opacity(0.2)
        #else
        Color(uiColor: .tertiarySystemBackground)
        #endif
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading) {
                Text(plan["name"] as? String ?? "").font(.headline)
                Text(plan["description"] as? String ?? "").padding(.bottom, 2)
                Text(kerned(plan["price"] as? String ?? "", "/"))
                if let savings = plan["savings"] as? String {
                    Text(kerned(savings, "/()")).foregroundStyle(Color.accentColor)
                }
            }
            Spacer()
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .symbolRenderingMode(.palette)
                .foregroundStyle(on ? Color.white : Color.secondary, Color.clear, Color.accentColor)
                .font(.title2)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(fill, in: shape)
        .overlay {
            #if os(macOS)
            shape.strokeBorder(on ? Color.accentColor : .gray.opacity(0.1), lineWidth: 1)
            #else
            shape.strokeBorder(Color.accentColor, lineWidth: on ? 1 : 0)
            #endif
        }
        .contentShape(shape)
        .onTapGesture { chosen = on ? nil : key }
        .background(.shadow(.drop(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.2), radius: 10)), in: shape.scale(0.99))
        .padding(.horizontal)
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func kerned(_ text: String, _ symbols: String) -> AttributedString {
        var kerned = AttributedString(text)
        for symbol in symbols.map(String.init) {
            if let range = kerned.range(of: symbol) { kerned[range].kern = 1 }
        }
        return kerned
    }
}

struct UnlockFeatureView: CauldronNativeView {
    static let name = "unlock_feature"
    let node: UINode
    let events: UIEvents
    @Environment(\.colorScheme) private var colorScheme

    init(node: UINode, events: UIEvents) {
        self.node = node
        self.events = events
    }

    private var fill: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #elseif os(tvOS)
        Color.secondary.opacity(0.2)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    var body: some View {
        let name = (node.string("name") ?? "").lowercased()
        let price = node.string("price") ?? ""
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
        Group {
            if node.bool("expanded") {
                VStack(spacing: 15) {
                    Text("Unlock a \(name) for only \(price)")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                    Text("Get the full picture with data and insights that cover an entire year.")
                        .font(.subheadline)
                    Button { events.send("unlock") } label: {
                        Text("Unlock").padding(.vertical, 2).padding(.horizontal, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    #if os(iOS)
                    .buttonBorderShape(.capsule)
                    #endif
                }
                .multilineTextAlignment(.center)
                .padding()
                .padding(.top, 30)
                .padding(.bottom)
                .overlay(alignment: .topTrailing) {
                    Button { events.send("collapse") } label: {
                        Label("Dismiss", systemImage: "xmark").labelStyle(.iconOnly)
                    }
                    .controlSize(.mini)
                    .foregroundStyle(.secondary)
                    .padding(.top)
                    .padding(.trailing, 10)
                }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Unlock a \(name)").font(.subheadline.weight(.semibold))
                        Text("for only \(price)").font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { events.send("unlock") } label: {
                        Text("Unlock").font(.subheadline).padding(2)
                    }
                    .buttonStyle(.borderedProminent)
                    #if os(iOS)
                    .buttonBorderShape(.capsule)
                    #endif
                }
                .padding()
                .contentShape(Rectangle())
                .onTapGesture { events.send("expand") }
            }
        }
        .frame(maxWidth: 400)
        .background(fill, in: shape)
        .background(.shadow(.drop(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.2), radius: 10)), in: shape.scale(0.99))
        .padding()
    }
}
