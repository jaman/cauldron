import SwiftUI
import WidgetKit

enum WidgetStore {
    static var group: String? { Bundle.main.object(forInfoDictionaryKey: "CauldronAppGroup") as? String }

    static func file(_ kind: String) -> URL? {
        guard let group,
              let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        return folder.appendingPathComponent("Library/Widgets", isDirectory: true).appendingPathComponent(kind + ".json")
    }

    static func entries(_ kind: String) -> [WidgetEntry] {
        guard let file = file(kind), let data = try? Data(contentsOf: file),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let entries = json["entries"] as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard let at = (entry["at"] as? NSNumber)?.doubleValue else { return nil }
            return WidgetEntry(date: Date(timeIntervalSince1970: at), sizes: entry["sizes"] as? [String: Any] ?? [:])
        }
    }
}

struct WidgetEntry: TimelineEntry {
    let date: Date
    let sizes: [String: Any]

    func content(_ family: WidgetFamily) -> [String: Any]? {
        (sizes[WidgetEntry.size(family)] ?? sizes["default"]) as? [String: Any]
    }

    static func size(_ family: WidgetFamily) -> String {
        switch family {
        case .systemSmall: "small"
        case .systemMedium: "medium"
        case .systemLarge: "large"
        case .systemExtraLarge: "extra_large"
        case .accessoryCircular: "circular"
        case .accessoryRectangular: "rectangular"
        case .accessoryInline: "inline"
        default: "default"
        }
    }
}

struct WidgetTimeline: TimelineProvider {
    let kind: String

    func placeholder(in context: Context) -> WidgetEntry { WidgetEntry(date: .now, sizes: [:]) }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(current() ?? WidgetEntry(date: .now, sizes: [:]))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let entries = WidgetStore.entries(kind)
        let past = entries.filter { $0.date <= .now }.last
        let coming = entries.filter { $0.date > .now }
        let shown = (past.map { [WidgetEntry(date: .now, sizes: $0.sizes)] } ?? []) + coming
        completion(Timeline(entries: shown.isEmpty ? [placeholder(in: context)] : shown, policy: .never))
    }

    private func current() -> WidgetEntry? {
        let entries = WidgetStore.entries(kind)
        return entries.filter { $0.date <= .now }.last ?? entries.first
    }
}

struct WidgetBody: View {
    let entry: WidgetEntry
    let name: String
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let content = entry.content(family) {
                WidgetNode(node: content)
            } else {
                Text(name).font(.headline).foregroundStyle(.secondary)
            }
        }
        .containerBackground(for: .widget) { background }
    }

    @ViewBuilder private var background: some View {
        if let content = entry.content(family),
           let colours = ((content["props"] as? [String: Any])?["modifiers"] as? [String: Any])?["gradient"] as? [Any] {
            LinearGradient(colors: colours.map { widgetColour($0) }, startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            Color.clear.background(.fill.tertiary)
        }
    }
}

struct WidgetNode: View {
    let node: [String: Any]

    private var props: [String: Any] { node["props"] as? [String: Any] ?? [:] }
    private var children: [[String: Any]] { node["children"] as? [[String: Any]] ?? [] }

    var body: some View {
        content.widgetModifiers(props["modifiers"] as? [String: Any] ?? [:])
    }

    @ViewBuilder private var content: some View {
        switch node["type"] as? String {
        case "text": Text(props["content"] as? String ?? "")
        case "label": Label { Text(props["title"] as? String ?? "") } icon: { glyph }
        case "icon": glyph
        case "image": picture
        case "gauge": WidgetGauge(props: props)
        case "vstack": VStack(alignment: horizontal, spacing: spacing) { nodes }
        case "hstack": HStack(alignment: vertical, spacing: spacing) { nodes }
        case "zstack": ZStack { nodes }
        case "spacer": Spacer(minLength: 0)
        case "divider": Divider()
        case "progress": ProgressView(value: (props["value"] as? NSNumber)?.doubleValue ?? 0)
        default: EmptyView()
        }
    }

    @ViewBuilder private var glyph: some View {
        if let asset = props["asset"] as? String { Image(asset) } else { Image(systemName: symbol) }
    }

    @ViewBuilder private var picture: some View {
        if let asset = props["asset"] as? String {
            Image(asset).resizable().scaledToFit()
        }
    }

    private var nodes: some View {
        ForEach(children.indices, id: \.self) { WidgetNode(node: children[$0]) }
    }

    private var spacing: CGFloat? { (props["spacing"] as? NSNumber).map { CGFloat($0.doubleValue) } }

    private var horizontal: HorizontalAlignment {
        switch props["alignment"] as? String {
        case "leading": .leading
        case "trailing": .trailing
        case "center": .center
        default: .leading
        }
    }

    private var vertical: VerticalAlignment {
        switch props["alignment"] as? String {
        case "top": .top
        case "bottom": .bottom
        default: .center
        }
    }

    private var symbol: String {
        props["ios"] as? String ?? props["name"] as? String ?? props["icon"] as? String ?? "circle"
    }
}

struct WidgetGauge: View {
    let props: [String: Any]

    private var value: Double { (props["value"] as? NSNumber)?.doubleValue ?? 0 }
    private var low: Double { (props["min"] as? NSNumber)?.doubleValue ?? 0 }
    private var high: Double { max((props["max"] as? NSNumber)?.doubleValue ?? 1, low + 0.0001) }

    var body: some View {
        switch props["style"] as? String {
        case "circular":
            Gauge(value: min(max(value, low), high), in: low...high) {
                EmptyView()
            } currentValueLabel: {
                current
            }
            .gaugeStyle(.accessoryCircular)
        case "segmented":
            SegmentedGauge(value: Int(value), total: Int(high)) {
                if let title = props["title"] as? String { Text(title) }
            }
        default:
            Gauge(value: min(max(value, low), high), in: low...high) {
                if let title = props["title"] as? String { Text(title) }
            } currentValueLabel: {
                current
            }
        }
    }

    @ViewBuilder private var current: some View {
        if let images = props["image"] as? [String] {
            ZStack { ForEach(images, id: \.self) { Image($0).resizable().scaledToFit() } }
        } else if let text = props["current"] as? String {
            Text(text)
        }
    }
}

struct SegmentedGauge<Title: View>: View {
    let value: Int
    let total: Int
    @ViewBuilder let title: () -> Title
    @Environment(\.layoutDirection) private var direction

    var body: some View {
        let total = max(total, 1)
        let filled = min(value, total)
        VStack(alignment: .leading, spacing: 4) {
            title()
            HStack(spacing: 3) {
                ForEach(0..<total, id: \.self) { index in
                    Segment(position: position(index, total), direction: direction)
                        .fill(.tint)
                        .opacity(index < filled ? 1 : 0.35)
                }
            }
            .frame(height: 11)
        }
    }

    private func position(_ index: Int, _ total: Int) -> Segment.Position {
        if total <= 1 { return .single }
        switch index {
        case 0: return .leading
        case total - 1: return .trailing
        default: return .middle
        }
    }
}

struct Segment: Shape {
    enum Position { case leading, trailing, middle, single }

    let position: Position
    let direction: LayoutDirection

    func path(in rect: CGRect) -> Path {
        let square: CGFloat = 2
        let round = rect.height / 2
        var position = position
        if direction == .rightToLeft {
            if position == .leading { position = .trailing } else if position == .trailing { position = .leading }
        }
        let leading = position == .leading || position == .single ? round : square
        let trailing = position == .trailing || position == .single ? round : square
        return Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(
            topLeading: leading, bottomLeading: leading, bottomTrailing: trailing, topTrailing: trailing
        ))
    }
}

func widgetColour(_ value: Any?) -> Color {
    if let pair = value as? [Any], pair.count == 2, pair[0] as? String == "asset", let name = pair[1] as? String {
        return Color(name)
    }
    switch value as? String {
    case "secondary": return .secondary
    case "accent": return .accentColor
    case "destructive": return .red
    case "white": return .white
    case let text? where text.hasPrefix("#"):
        let digits = String(text.dropFirst())
        guard digits.count == 6, let rgb = UInt32(digits, radix: 16) else { return .primary }
        return Color(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    default: return .primary
    }
}

extension View {
    @ViewBuilder func widgetModifiers(_ modifiers: [String: Any]) -> some View {
        self
            .font(font(modifiers["font"] as? String))
            .fontWeight(modifiers["bold"] as? Bool == true ? .bold : nil)
            .widgetForeground(modifiers["foreground"].map { widgetColour($0) })
            .tint(modifiers["tint"].map { widgetColour($0) })
            .padding(CGFloat((modifiers["padding"] as? NSNumber)?.doubleValue ?? 0))
            .frame(
                width: (modifiers["frame"] as? [String: Any])?["width"].flatMap { ($0 as? NSNumber).map { CGFloat($0.doubleValue) } },
                height: (modifiers["frame"] as? [String: Any])?["height"].flatMap { ($0 as? NSNumber).map { CGFloat($0.doubleValue) } }
            )
            .frame(
                maxWidth: (modifiers["frame"] as? [String: Any])?["max_width"] as? String == "infinity" ? .infinity : nil,
                maxHeight: (modifiers["frame"] as? [String: Any])?["max_height"] as? String == "infinity" ? .infinity : nil,
                alignment: .leading
            )
    }

    @ViewBuilder func widgetForeground(_ colour: Color?) -> some View {
        if let colour { foregroundStyle(colour) } else { self }
    }

    private func font(_ name: String?) -> Font? {
        switch name {
        case "large_title": .largeTitle
        case "title": .title
        case "title2": .title2
        case "title3": .title3
        case "headline": .headline
        case "subheadline": .subheadline
        case "callout": .callout
        case "footnote": .footnote
        case "caption": .caption
        case "body": .body
        default: nil
        }
    }
}
