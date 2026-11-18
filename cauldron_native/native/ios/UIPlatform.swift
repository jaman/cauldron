import SwiftUI

#if os(macOS)
func localImage(_ path: String) -> Image? { NSImage(contentsOfFile: path).map { Image(nsImage: $0) } }
#else
func localImage(_ path: String) -> Image? { UIImage(contentsOfFile: path).map { Image(uiImage: $0) } }
#endif

#if os(tvOS)
let cardBackground = AnyShapeStyle(.regularMaterial)
let backgroundColour = Color.clear
let secondaryBackgroundColour = Color.primary.opacity(0.1)

struct NodeSlider: View {
    let node: UINode
    @FocusState private var focused: Bool

    var body: some View {
        let low = node.double("min") ?? 0, high = node.double("max") ?? 1
        let value = node.double("value") ?? low
        let step = node.double("step") ?? (high - low) / 20
        ProgressView(value: value - low, total: high - low)
            .padding()
            .background(focused ? secondaryBackgroundColour : .clear, in: RoundedRectangle(cornerRadius: 12))
            .focusable()
            .focused($focused)
            .onMoveCommand { direction in
                switch direction {
                case .left: send(max(low, value - step))
                case .right: send(min(high, value + step))
                default: break
                }
            }
    }

    private func send(_ value: Double) { UIEvents(id: node.id).send("change", value) }
}

struct NodeDatePicker: View {
    let node: UINode

    var body: some View {
        let mode = node.string("mode") ?? "date"
        let date = DateText.parse(node.string("value") ?? "", mode) ?? Date()
        let year = Calendar.current.component(.year, from: date)
        VStack(alignment: .leading) {
            if let title = node.string("title"), !title.isEmpty { Text(title) }
            HStack {
                if mode != "time" {
                    part("Day", .day, 1...days(date), date, mode)
                    part("Month", .month, 1...12, date, mode)
                    part("Year", .year, (year - 100)...(year + 100), date, mode)
                }
                if mode != "date" {
                    part("Hour", .hour, 0...23, date, mode)
                    part("Minute", .minute, 0...59, date, mode)
                }
            }
        }
    }

    private func part(_ title: String, _ component: Calendar.Component, _ range: ClosedRange<Int>,
                      _ date: Date, _ mode: String) -> some View {
        Picker(title, selection: Binding(
            get: { Calendar.current.component(component, from: date) },
            set: { value in
                guard let changed = changing(date, component, value) else { return }
                UIEvents(id: node.id).send("change", DateText.format(changed, mode))
            }
        )) {
            ForEach(Array(range), id: \.self) { Text(label(component, $0)).tag($0) }
        }
        .pickerStyle(.menu)
    }

    private func changing(_ date: Date, _ component: Calendar.Component, _ value: Int) -> Date? {
        let calendar = Calendar.current
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        parts.setValue(value, for: component)
        parts.day = 1
        guard let month = calendar.date(from: parts),
              let length = calendar.range(of: .day, in: .month, for: month)?.count else { return nil }
        let day = component == .day ? value : calendar.component(.day, from: date)
        parts.day = min(day, length)
        return calendar.date(from: parts)
    }

    private func days(_ date: Date) -> Int {
        Calendar.current.range(of: .day, in: .month, for: date)?.count ?? 31
    }

    private func label(_ component: Calendar.Component, _ value: Int) -> String {
        switch component {
        case .month: Calendar.current.monthSymbols[value - 1]
        case .minute: String(format: "%02d", value)
        default: String(value)
        }
    }
}

struct NodeStepper: View {
    let node: UINode

    var body: some View {
        let value = node.double("value") ?? 0
        let low = node.double("min") ?? -Double.infinity, high = node.double("max") ?? Double.infinity
        let step = node.double("step") ?? 1
        HStack {
            Text("\(node.string("title") ?? ""): \(number(value))")
            Spacer()
            Button { send(max(low, value - step)) } label: { Image(systemName: "minus") }
                .disabled(value - step < low)
            Button { send(min(high, value + step)) } label: { Image(systemName: "plus") }
                .disabled(value + step > high)
        }
    }

    private func send(_ value: Double) { UIEvents(id: node.id).send("change", value) }

    private func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

struct NodeDisclosure: View {
    let node: UINode

    var body: some View {
        let expanded = node.bool("expanded")
        VStack(alignment: .leading) {
            Button { UIEvents(id: node.id).send("toggle", !expanded) } label: {
                Label(node.string("title") ?? "", systemImage: expanded ? "chevron.down" : "chevron.right")
            }
            if expanded { Children(node: node) }
        }
    }
}
#elseif os(macOS)
let cardBackground = AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
let backgroundColour = Color(nsColor: .windowBackgroundColor)
let secondaryBackgroundColour = Color(nsColor: .controlBackgroundColor)
#else
let cardBackground = AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
let backgroundColour = Color(uiColor: .systemBackground)
let secondaryBackgroundColour = Color(uiColor: .secondarySystemBackground)
#endif
