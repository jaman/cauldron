import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@Observable
final class UINode {
    let id: String
    var type: String
    var props: [String: Any]
    var events: Set<String>
    var children: [String]

    init(id: String, type: String, props: [String: Any], events: Set<String>, children: [String]) {
        self.id = id
        self.type = type
        self.props = props
        self.events = events
        self.children = children
    }

    func string(_ key: String) -> String? { props[key] as? String }
    func bool(_ key: String) -> Bool { props[key] as? Bool ?? false }
    func double(_ key: String) -> Double? { (props[key] as? NSNumber)?.doubleValue }
    var modifiers: [[Any]] { props["modifiers"] as? [[Any]] ?? [] }
}

struct UIEvents {
    let id: String

    func send(_ kind: String, _ value: Any? = nil) {
        var message: [String: Any] = ["id": id, "kind": kind]
        if let value { message["value"] = value }
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        data.withUnsafeBytes { bytes in
            cn_ui_event(bytes.bindMemory(to: UInt8.self).baseAddress, data.count)
        }
    }
}

protocol CauldronNativeView: View {
    static var name: String { get }
    init(node: UINode, events: UIEvents)
}

@Observable
final class UIStore {
    static let shared = UIStore()

    var root: String?
    var nodes: [String: UINode] = [:]

    func apply(_ patch: [String: Any]) {
        for record in patch["nodes"] as? [[String: Any]] ?? [] { update(record) }
        for id in patch["removed"] as? [String] ?? [] { nodes.removeValue(forKey: id) }
        if let root = patch["root"] as? String, self.root != root { self.root = root }
    }

    private func update(_ record: [String: Any]) {
        guard let id = record["id"] as? String, let type = record["type"] as? String else { return }
        let props = record["props"] as? [String: Any] ?? [:]
        let events = Set(record["events"] as? [String] ?? [])
        let children = record["children"] as? [String] ?? []

        guard let node = nodes[id] else {
            nodes[id] = UINode(id: id, type: type, props: props, events: events, children: children)
            return
        }
        if node.type != type { node.type = type }
        if !NSDictionary(dictionary: node.props).isEqual(to: props) { node.props = props }
        if node.events != events { node.events = events }
        if node.children != children { node.children = children }
    }
}

@_cdecl("cn_platform_ui")
func cnPlatformUI(_ json: UnsafePointer<UInt8>, _ size: Int) {
    let data = Data(bytes: json, count: size)
    guard let patch = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
    DispatchQueue.main.async {
        UIStore.shared.apply(patch)
        UIHost.show()
    }
}

struct RootView: View {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var compact: Bool { sizeClass == .compact }
    #else
    private let compact = false
    #endif

    var body: some View {
        Group {
            if let root = UIStore.shared.root {
                NodeView(id: root)
            } else {
                backgroundColour.ignoresSafeArea()
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { WindowReport.send($0, compact: compact) }
        .onChange(of: compact) { WindowReport.send(WindowReport.last, compact: compact) }
    }
}

enum WindowReport {
    static var last = CGSize.zero

    static func send(_ size: CGSize, compact: Bool) {
        last = size
        let message: [String: Any] = ["window": ["width": size.width, "height": size.height, "compact": compact]]
        guard size != .zero, let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        data.withUnsafeBytes { bytes in
            cn_ui_event(bytes.bindMemory(to: UInt8.self).baseAddress, data.count)
        }
    }
}

struct NodeView: View {
    let id: String

    var body: some View {
        if let node = UIStore.shared.nodes[id] {
            NodeContent(node: node)
                .modifiers(node.modifiers)
                .accessible(node)
                .tappable(node)
                .disabled(node.bool("disabled"))
        }
    }
}

struct Children: View {
    let node: UINode

    var body: some View {
        ForEach(shown, id: \.self) { NodeView(id: $0) }
    }

    private var shown: [String] {
        node.children.filter { !attachedTypes.contains(UIStore.shared.nodes[$0]?.type ?? "") }
    }
}

struct NodeContent: View {
    let node: UINode

    var body: some View {
        switch node.type {
        case "text": Text(node.string("content") ?? "")
        case "button": NodeButton(node: node)
        case "text_field", "secure_field": NodeTextField(node: node)
        case "toggle": NodeToggle(node: node)
        case "slider": NodeSlider(node: node)
        case "vstack":
            VStack(alignment: horizontalAlignment(node.string("alignment")), spacing: spacing(node)) { Children(node: node) }
        case "hstack":
            HStack(alignment: verticalAlignment(node.string("alignment")), spacing: spacing(node)) { Children(node: node) }
        case "zstack": ZStack(alignment: alignment(node.string("alignment"))) { Children(node: node) }
        case "spacer": Spacer()
        case "divider": Divider()
        case "scroll":
            ScrollView(node.string("axis") == "horizontal" ? .horizontal : .vertical) {
                if node.string("axis") == "horizontal" {
                    LazyHStack { Children(node: node) }
                } else {
                    LazyVStack { Children(node: node) }
                }
            }
        case "list": List { Children(node: node) }
        case "form": NodeForm(node: node)
        case "section": NodeSection(node: node)
        case "navigation": NodeNavigation(node: node)
        case "screen": NodeScreen(node: node)
        case "native": NodeNative(node: node)
        case "icon": NodeIcon(node: node)
        case "image": NodeImage(node: node)
        case "gauge": NodeGauge(node: node)
        case "label": NodeLabel(node: node)
        case "link": NodeLink(node: node)
        case "menu": NodeMenu(node: node)
        case "chip": NodeChip(node: node)
        case "picker": NodePicker(node: node)
        case "date_picker": NodeDatePicker(node: node)
        case "stepper": NodeStepper(node: node)
        case "progress": NodeProgress(node: node)
        case "text_editor": NodeTextField(node: node)
        case "card": NodeCard(node: node)
        case "grid": NodeGrid(node: node)
        case "disclosure": NodeDisclosure(node: node)
        case "tabs": NodeTabs(node: node)
        case "tab": TabPage(tab: node)
        case "video": NodeVideo(node: node)
        case "camera_preview": NodeCameraPreview(node: node)
        case "chart": NodeChart(node: node)
        case "map": NodeMap(node: node)
        case "split": NodeSplit(node: node)
        case "table": NodeTable(node: node)
        case "theme": NodeTheme(node: node)
        default: EmptyView()
        }
    }

    private func spacing(_ node: UINode) -> CGFloat? { node.double("spacing").map { CGFloat($0) } }
}

struct NodeButton: View {
    let node: UINode
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let button = Button(role: role) { UIEvents(id: node.id).send("tap") } label: {
            if enabled {
                title
            } else {
                title.foregroundStyle(.secondary)
            }
        }
        switch node.string("style") {
        case "prominent": button.buttonStyle(.borderedProminent)
        case "bordered": button.buttonStyle(.bordered)
        case "plain": button.buttonStyle(.plain)
        case "icon": button.labelStyle(.iconOnly).buttonStyle(.borderless)
        default: button
        }
    }

    @ViewBuilder private var title: some View {
        if let icon = node.string("icon") {
            Label(node.string("title") ?? "", systemImage: symbol(icon, node))
        } else {
            Text(node.string("title") ?? "")
        }
    }

    private var role: ButtonRole? {
        switch node.string("role") {
        case "destructive": .destructive
        case "cancel": .cancel
        default: nil
        }
    }
}

struct NodeTextField: View {
    let node: UINode
    @State private var text = ""
    @State private var sent: [String] = []

    var body: some View {
        field
            #if !os(macOS)
            .keyboardType(keyboard)
            .textInputAutocapitalization(capitalization)
            #endif
            .autocorrectionDisabled(node.props["autocorrect"] as? Bool == false)
            .onAppear { text = node.string("value") ?? "" }
            .onChange(of: node.string("value") ?? "") { _, value in received(value) }
            .onChange(of: text) { _, value in
                if node.events.contains("change"), value != (node.string("value") ?? ""), value != sent.last {
                    sent.append(value)
                    UIEvents(id: node.id).send("change", value)
                }
            }
            .onSubmit { if node.events.contains("submit") { UIEvents(id: node.id).send("submit", text) } }
    }

    private func received(_ value: String) {
        if let echoed = sent.firstIndex(of: value) {
            sent.removeFirst(echoed + 1)
        } else if value != text {
            sent.removeAll()
            text = value
        }
    }

    @ViewBuilder private var field: some View {
        if node.type == "secure_field" {
            SecureField(node.string("placeholder") ?? "", text: $text)
        } else if node.type == "text_editor" {
            TextField(node.string("placeholder") ?? "", text: $text, axis: .vertical).lineLimit(3...10)
        } else {
            TextField(node.string("placeholder") ?? "", text: $text)
        }
    }

    #if !os(macOS)
    private var keyboard: UIKeyboardType {
        switch node.string("keyboard") {
        case "email": .emailAddress
        case "number": .numberPad
        case "decimal": .decimalPad
        case "phone": .phonePad
        case "url": .URL
        default: .default
        }
    }

    private var capitalization: TextInputAutocapitalization {
        switch node.string("capitalize") {
        case "words": .words
        case "characters": .characters
        case "none": .never
        default: .sentences
        }
    }
    #endif
}

struct NodeToggle: View {
    let node: UINode

    var body: some View {
        Toggle(node.string("title") ?? "", isOn: Binding(
            get: { node.bool("value") },
            set: { UIEvents(id: node.id).send("change", $0) }
        ))
    }
}

#if !os(tvOS)
struct NodeSlider: View {
    let node: UINode

    var body: some View {
        let low = node.double("min") ?? 0, high = node.double("max") ?? 1
        let value = Binding(
            get: { node.double("value") ?? low },
            set: { UIEvents(id: node.id).send("change", $0) }
        )
        if let step = node.double("step") {
            Slider(value: value, in: low...high, step: step)
        } else {
            Slider(value: value, in: low...high)
        }
    }
}
#endif

struct NodeSection: View {
    let node: UINode

    var body: some View {
        Section {
            Children(node: node)
        } header: {
            if let title = node.string("title") { Text(title) }
        } footer: {
            if let footer = node.string("footer") { Text(footer) }
        }
    }
}

struct NodeNavigation: View {
    let node: UINode

    var body: some View {
        NavigationStack(path: Binding(
            get: { Array(node.children.dropFirst()) },
            set: { path in
                if path.count < node.children.count - 1 { UIEvents(id: node.id).send("back", path.count + 1) }
            }
        )) {
            if let first = node.children.first {
                NodeView(id: first).navigationDestination(for: String.self) { NodeView(id: $0) }
            }
        }
    }
}

struct NodeScreen: View {
    let node: UINode

    var body: some View {
        content
            .attachments(node)
            .searching(node)
            .navigationTitle(node.string("title") ?? "")
            #if os(iOS)
            .navigationBarTitleDisplayMode(node.props["large_title"] as? Bool == false ? .inline : .automatic)
            #endif
    }

    @ViewBuilder private var content: some View {
        let shown = node.children.filter { !attachedTypes.contains(UIStore.shared.nodes[$0]?.type ?? "") }
        if shown.count == 1, let only = shown.first {
            NodeView(id: only)
        } else {
            VStack { Children(node: node) }
        }
    }
}

struct NodeNative: View {
    let node: UINode

    var body: some View {
        if let make = cauldronNativeViews[node.string("name") ?? ""] {
            make(node, UIEvents(id: node.id))
        } else {
            Text("No native view named \(node.string("name") ?? "")").foregroundStyle(.red)
        }
    }
}

extension View {
    func modifiers(_ list: [[Any]]) -> AnyView {
        list.reduce(AnyView(self)) { view, pair in
            guard pair.count == 2, let name = pair[0] as? String else { return view }
            return view.modifier(name, pair[1])
        }
    }

    func modifier(_ name: String, _ value: Any) -> AnyView {
        switch name {
        case "padding": AnyView(padded(value))
        case "font": AnyView(font(.system(textStyle(value as? String))))
        case "foreground": AnyView(foregroundStyle(color(value)))
        case "background": AnyView(background(color(value)))
        case "gradient": AnyView(background(LinearGradient(colors: (value as? [Any] ?? []).map(color), startPoint: .topLeading, endPoint: .bottomTrailing)))
        case "frame": AnyView(framed(value as? [String: Any] ?? [:]))
        case "corner_radius": AnyView(clipShape(RoundedRectangle(cornerRadius: number(value))))
        case "opacity": AnyView(opacity(number(value)))
        case "bold": AnyView(bold(value as? Bool ?? false))
        case "ios": AnyView(modifiers(value as? [[Any]] ?? []))
        default: AnyView(self)
        }
    }

    @ViewBuilder func padded(_ value: Any) -> some View {
        if let edges = value as? [String: Any] {
            padding(.top, number(edges["top"] ?? edges["vertical"] ?? edges["all"] ?? 0))
                .padding(.bottom, number(edges["bottom"] ?? edges["vertical"] ?? edges["all"] ?? 0))
                .padding(.leading, number(edges["leading"] ?? edges["horizontal"] ?? edges["all"] ?? 0))
                .padding(.trailing, number(edges["trailing"] ?? edges["horizontal"] ?? edges["all"] ?? 0))
        } else if value as? Bool == true {
            padding()
        } else {
            padding(number(value))
        }
    }

    func framed(_ frame: [String: Any]) -> some View {
        self
            .frame(width: optionalNumber(frame["width"]), height: optionalNumber(frame["height"]))
            .frame(
                minWidth: optionalNumber(frame["min_width"]),
                maxWidth: extent(frame["max_width"]),
                minHeight: optionalNumber(frame["min_height"]),
                maxHeight: extent(frame["max_height"])
            )
    }

    func accessible(_ node: UINode) -> AnyView {
        var view = AnyView(self)
        if let label = node.string("label") { view = AnyView(view.accessibilityLabel(Text(label))) }
        if let hint = node.string("hint") { view = AnyView(view.accessibilityHint(Text(hint))) }
        return view
    }

    func tappable(_ node: UINode) -> AnyView {
        guard node.events.contains("tap"), !tappedItself.contains(node.type) else { return AnyView(self) }
        return AnyView(
            contentShape(Rectangle())
                .onTapGesture { UIEvents(id: node.id).send("tap") }
                .accessibilityAddTraits(.isButton)
        )
    }
}

private func number(_ value: Any) -> CGFloat { CGFloat((value as? NSNumber)?.doubleValue ?? 0) }

private func optionalNumber(_ value: Any?) -> CGFloat? { (value as? NSNumber).map { CGFloat($0.doubleValue) } }

private func extent(_ value: Any?) -> CGFloat? {
    if value as? String == "infinity" { return .infinity }
    return optionalNumber(value)
}

private func color(_ value: Any) -> Color {
    if let pair = value as? [Any], pair.count == 2, pair[0] as? String == "asset", let name = pair[1] as? String {
        return Color(name)
    }
    return switch value as? String {
    case "primary": .primary
    case "secondary": .secondary
    case "accent": .accentColor
    case "background": backgroundColour
    case "secondary_background": secondaryBackgroundColour
    case "destructive": .red
    case let hex?: hexColour(hex) ?? .primary
    case nil: .primary
    }
}

func hexColour(_ value: Any?) -> Color? {
    guard let text = value as? String else { return nil }
    let digits = text.hasPrefix("#") ? String(text.dropFirst()) : text
    guard digits.count == 6, let rgb = UInt32(digits, radix: 16) else { return nil }
    return Color(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
}

private func textStyle(_ name: String?) -> Font.TextStyle {
    switch name {
    case "large_title": .largeTitle
    case "title": .title
    case "title2": .title2
    case "title3": .title3
    case "headline": .headline
    case "callout": .callout
    case "subheadline": .subheadline
    case "footnote": .footnote
    case "caption": .caption
    default: .body
    }
}

private func horizontalAlignment(_ name: String?) -> HorizontalAlignment {
    switch name {
    case "leading": .leading
    case "trailing": .trailing
    default: .center
    }
}

private func verticalAlignment(_ name: String?) -> VerticalAlignment {
    switch name {
    case "top": .top
    case "bottom": .bottom
    default: .center
    }
}

private func alignment(_ name: String?) -> Alignment {
    switch name {
    case "top": .top
    case "bottom": .bottom
    case "leading": .leading
    case "trailing": .trailing
    case "top_leading": .topLeading
    case "top_trailing": .topTrailing
    case "bottom_leading": .bottomLeading
    case "bottom_trailing": .bottomTrailing
    default: .center
    }
}
