import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

let attachedTypes: Set<String> = ["toolbar", "sheet", "alert", "confirm", "dialog", "menu_bar_extra"]
let tappedItself: Set<String> = ["button", "chip", "menu", "link"]

func symbol(_ name: String?, _ node: UINode? = nil) -> String {
    if let own = node?.string("ios") { return own }
    switch name {
    case "add": return "plus"
    case "add_circle": return "plus.circle"
    case "back": return "chevron.backward"
    case "forward": return "chevron.forward"
    case "phone": return "phone"
    case "check": return "checkmark"
    case "check_circle": return "checkmark.circle"
    case "close": return "xmark"
    case "calendar": return "calendar"
    case "delete": return "trash"
    case "edit": return "pencil"
    case "mail": return "envelope"
    case "favorite": return "heart.fill"
    case "favorite_border": return "heart"
    case "home": return "house"
    case "info": return "info.circle"
    case "location": return "mappin.and.ellipse"
    case "lock": return "lock"
    case "menu": return "line.3.horizontal"
    case "more": return "ellipsis.circle"
    case "notifications": return "bell"
    case "person": return "person"
    case "account": return "person.crop.circle"
    case "play": return "play.fill"
    case "refresh": return "arrow.clockwise"
    case "search": return "magnifyingglass"
    case "send": return "paperplane"
    case "settings": return "gear"
    case "share": return "square.and.arrow.up"
    case "cart": return "cart"
    case "star": return "star.fill"
    case "thumb_up": return "hand.thumbsup"
    case "warning": return "exclamationmark.triangle"
    case "list": return "list.bullet"
    case "face": return "face.smiling"
    case "build": return "hammer"
    case let other?: return other
    case nil: return "questionmark"
    }
}

struct NodeIcon: View {
    let node: UINode
    var body: some View {
        if let asset = node.string("asset") { Image(asset) } else { Image(systemName: symbol(node.string("name"), node)) }
    }
}

struct NodeImage: View {
    let node: UINode

    var body: some View {
        let source = node.string("source") ?? ""
        if let asset = node.string("asset") {
            fitted(Image(asset))
        } else if source.hasPrefix("http://") || source.hasPrefix("https://"), let url = URL(string: source) {
            AsyncImage(url: url) { phase in
                if let image = phase.image { fitted(image) } else if phase.error != nil {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
        } else if let picture = localImage(source) {
            fitted(picture)
        } else {
            Image(systemName: "photo").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func fitted(_ image: Image) -> some View {
        if node.string("fit") == "fill" {
            Color.clear
                .overlay { image.resizable().scaledToFill() }
                .clipped()
        } else {
            image.resizable().aspectRatio(contentMode: .fit)
        }
    }
}

struct NodeLabel: View {
    let node: UINode
    var body: some View {
        if let asset = node.string("asset") {
            Label { Text(node.string("title") ?? "") } icon: { Image(asset) }
        } else {
            Label(node.string("title") ?? "", systemImage: symbol(node.string("icon"), node))
        }
    }
}

struct NodeLink: View {
    let node: UINode

    var body: some View {
        if let url = URL(string: node.string("url") ?? "") {
            Link(node.string("title") ?? "", destination: url)
        } else {
            Text(node.string("title") ?? "")
        }
    }
}

struct NodeMenu: View {
    let node: UINode

    var body: some View {
        Menu {
            Children(node: node)
        } label: {
            if let icon = node.string("icon") {
                Label(node.string("title") ?? "", systemImage: symbol(icon, node)).labelStyle(.iconOnly)
            } else {
                Text(node.string("title") ?? "")
            }
        }
    }
}

struct NodeChip: View {
    let node: UINode

    var body: some View {
        let button = Button(node.string("title") ?? "") { UIEvents(id: node.id).send("tap") }
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        if node.bool("selected") {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}

struct NodePicker: View {
    let node: UINode

    var body: some View {
        let options = node.props["options"] as? [String] ?? []
        let picker = Picker(node.string("title") ?? "", selection: Binding(
            get: { Int(node.double("value") ?? -1) },
            set: { UIEvents(id: node.id).send("change", $0) }
        )) {
            ForEach(options.indices, id: \.self) { Text(options[$0]).tag($0) }
        }
        switch node.string("style") {
        case "segmented": picker.pickerStyle(.segmented)
        #if os(tvOS)
        case "wheel": picker.pickerStyle(.inline)
        #elseif os(macOS)
        case "wheel": picker.pickerStyle(.radioGroup)
        #else
        case "wheel": picker.pickerStyle(.wheel)
        #endif
        case "inline": picker.pickerStyle(.inline)
        default: picker.pickerStyle(.menu)
        }
    }
}

#if !os(tvOS)
struct NodeDatePicker: View {
    let node: UINode

    var body: some View {
        let mode = node.string("mode") ?? "date"
        let picker = DatePicker(node.string("title") ?? "", selection: Binding(
            get: { DateText.parse(node.string("value") ?? "", mode) ?? Date() },
            set: { UIEvents(id: node.id).send("change", DateText.format($0, mode)) }
        ), displayedComponents: components(mode))
        switch node.string("style") {
        case "graphical": picker.datePickerStyle(.graphical)
        #if os(macOS)
        case "wheel": picker.datePickerStyle(.stepperField)
        #else
        case "wheel": picker.datePickerStyle(.wheel)
        #endif
        default: picker.datePickerStyle(.compact)
        }
    }

    private func components(_ mode: String) -> DatePickerComponents {
        switch mode {
        case "time": [.hourAndMinute]
        case "date_time": [.date, .hourAndMinute]
        default: [.date]
        }
    }
}
#endif

enum DateText {
    static func formatter(_ mode: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.calendar = Calendar(identifier: .gregorian)
        switch mode {
        case "time": formatter.dateFormat = "HH:mm:ss"
        case "date_time": formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        default: formatter.dateFormat = "yyyy-MM-dd"
        }
        return formatter
    }

    static func parse(_ text: String, _ mode: String) -> Date? { formatter(mode).date(from: text) }
    static func format(_ date: Date, _ mode: String) -> String { formatter(mode).string(from: date) }
}

#if !os(tvOS)
struct NodeStepper: View {
    let node: UINode

    var body: some View {
        let value = node.double("value") ?? 0
        let low = node.double("min") ?? -Double.infinity, high = node.double("max") ?? Double.infinity
        Stepper(value: Binding(
            get: { value },
            set: { UIEvents(id: node.id).send("change", $0) }
        ), in: low...high, step: node.double("step") ?? 1) {
            Text("\(node.string("title") ?? ""): \(number(value))")
        }
    }

    private func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
#endif

struct NodeProgress: View {
    let node: UINode

    var body: some View {
        let title = node.string("title")
        let view = Group {
            if let value = node.double("value") {
                ProgressView(value: value) { if let title { Text(title) } }
            } else {
                ProgressView { if let title { Text(title) } }
            }
        }
        if node.string("style") == "circular" {
            view.progressViewStyle(.circular)
        } else {
            view.progressViewStyle(.linear)
        }
    }
}

struct NodeCard: View {
    let node: UINode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { Children(node: node) }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct NodeGrid: View {
    let node: UINode

    var body: some View {
        LazyVGrid(columns: columns, spacing: CGFloat(node.double("spacing") ?? 12)) { Children(node: node) }
    }

    private var columns: [GridItem] {
        if let width = node.double("min_width") { return [GridItem(.adaptive(minimum: CGFloat(width)))] }
        return Array(repeating: GridItem(.flexible()), count: max(1, Int(node.double("columns") ?? 2)))
    }
}

#if !os(tvOS)
struct NodeDisclosure: View {
    let node: UINode

    var body: some View {
        DisclosureGroup(node.string("title") ?? "", isExpanded: Binding(
            get: { node.bool("expanded") },
            set: { UIEvents(id: node.id).send("toggle", $0) }
        )) {
            Children(node: node)
        }
    }
}
#endif

struct NodeTabs: View {
    let node: UINode

    var body: some View {
        TabView(selection: Binding(
            get: { Int(node.double("selected") ?? 0) },
            set: { UIEvents(id: node.id).send("select", $0) }
        )) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                Tab(tab.string("title") ?? "", systemImage: symbol(tab.string("icon"), tab), value: index) {
                    TabPage(tab: tab)
                }
            }
        }
        #if !os(tvOS)
        .tabViewStyle(.sidebarAdaptable)
        #endif
    }

    private var tabs: [UINode] { node.children.compactMap { UIStore.shared.nodes[$0] } }
}

struct TabPage: View {
    let tab: UINode

    var body: some View {
        if tab.children.count == 1, let only = tab.children.first {
            NodeView(id: only)
        } else {
            VStack { Children(node: tab) }
        }
    }
}

extension View {
    func attachments(_ screen: UINode) -> AnyView {
        screen.children.compactMap { UIStore.shared.nodes[$0] }
            .filter { attachedTypes.contains($0.type) }
            .reduce(AnyView(self)) { view, node in view.attach(node) }
    }

    func attach(_ node: UINode) -> AnyView {
        let shown = Binding(
            get: { node.bool("shown") },
            set: { if !$0 { UIEvents(id: node.id).send("dismiss") } }
        )
        switch node.type {
        case "toolbar":
            return AnyView(toolbar {
                ToolbarItemGroup(placement: .primaryAction) { Children(node: node) }
            })
        case "sheet":
            return AnyView(sheet(isPresented: shown) { SheetContent(node: node) })
        case "dialog":
            return AnyView(sheet(isPresented: shown) { DialogContent(node: node) })
        case "alert":
            return AnyView(alert(node.string("title") ?? "", isPresented: shown) {
                Children(node: node)
            } message: {
                if let message = node.string("message") { Text(message) }
            })
        case "menu_bar_extra":
            #if os(macOS)
            return AnyView(background(MenuBarInstaller(node: node)))
            #else
            return AnyView(self)
            #endif
        case "confirm":
            return AnyView(confirmationDialog(node.string("title") ?? "", isPresented: shown, titleVisibility: .visible) {
                Children(node: node)
            } message: {
                if let message = node.string("message") { Text(message) }
            })
        default:
            return AnyView(self)
        }
    }

    func searching(_ screen: UINode) -> AnyView {
        guard screen.props["search"] != nil else { return AnyView(self) }
        return AnyView(searchable(
            text: Binding(
                get: { screen.string("search") ?? "" },
                set: { UIEvents(id: screen.id).send("search", $0) }
            ),
            prompt: screen.string("search_prompt").map { Text($0) }
        ))
    }
}

struct SheetContent: View {
    let node: UINode

    var body: some View {
        NavigationStack {
            Group {
                if node.children.count == 1, let only = node.children.first {
                    NodeView(id: only)
                } else {
                    VStack { Children(node: node) }.padding()
                }
            }
            .navigationTitle(node.string("title") ?? "")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .presentationDetents([.medium, .large])
    }
}
