import SwiftUI

struct SidebarRow: Identifiable {
    let id: Int
    let node: String
}

struct SidebarGroup: Identifiable {
    let id: Int
    let title: String?
    let rows: [SidebarRow]
}

struct NodeSplit: View {
    let node: UINode

    var body: some View {
        let parts = node.children.compactMap { UIStore.shared.nodes[$0] }
        NavigationSplitView {
            List(selection: selection) {
                ForEach(groups(parts.first { $0.type == "sidebar" })) { group in
                    if let title = group.title {
                        Section(title) { rows(group) }
                    } else {
                        rows(group)
                    }
                }
            }
            .navigationTitle(node.string("title") ?? "")
        } detail: {
            if let detail = parts.first(where: { $0.type == "detail" }) { Children(node: detail) }
        }
    }

    private func rows(_ group: SidebarGroup) -> some View {
        ForEach(group.rows) { row in NodeView(id: row.node).tag(Optional(row.id)) }
    }

    private var selection: Binding<Int?> {
        Binding(
            get: {
                let index = Int(node.double("selected") ?? -1)
                return index >= 0 ? index : nil
            },
            set: { UIEvents(id: node.id).send("select", $0) }
        )
    }

    private func groups(_ sidebar: UINode?) -> [SidebarGroup] {
        var next = 0
        var groups: [SidebarGroup] = []
        var loose: [SidebarRow] = []
        for id in sidebar?.children ?? [] {
            guard let child = UIStore.shared.nodes[id] else { continue }
            if child.type == "section" {
                if !loose.isEmpty { groups.append(SidebarGroup(id: groups.count, title: nil, rows: loose)) }
                loose = []
                let rows = child.children.map { row -> SidebarRow in
                    defer { next += 1 }
                    return SidebarRow(id: next, node: row)
                }
                groups.append(SidebarGroup(id: groups.count, title: child.string("title"), rows: rows))
            } else {
                loose.append(SidebarRow(id: next, node: id))
                next += 1
            }
        }
        if !loose.isEmpty { groups.append(SidebarGroup(id: groups.count, title: nil, rows: loose)) }
        return groups
    }
}

struct TableLine: Identifiable {
    let id: Int
    let cells: [Any]

    func text(_ index: Int) -> String? {
        guard index < cells.count, !(cells[index] is [String: Any]) else { return nil }
        return "\(cells[index])"
    }

    func control(_ index: Int) -> Int? {
        guard index < cells.count else { return nil }
        return ((cells[index] as? [String: Any])?["child"] as? NSNumber)?.intValue
    }
}

struct NodeTable: View {
    let node: UINode
    @State private var chosen: Int?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var size
    #endif

    var body: some View {
        let columns = node.props["columns"] as? [String] ?? []
        let lines = (node.props["rows"] as? [[Any]] ?? []).enumerated().map { entry in
            TableLine(id: entry.offset, cells: entry.element)
        }
        if compact {
            List(lines) { line in compactLine(line) }
        } else {
            wide(lines, columns)
        }
    }

    private var compact: Bool {
        #if os(iOS)
        size == .compact
        #elseif os(tvOS)
        true
        #else
        false
        #endif
    }

    @ViewBuilder private func wide(_ lines: [TableLine], _ columns: [String]) -> some View {
        #if os(tvOS)
        List(lines) { line in compactLine(line) }
        #else
        Table(lines, selection: Binding(get: { chosen }, set: { picked in
            chosen = picked
            if let picked, node.events.contains("select") { UIEvents(id: node.id).send("select", picked) }
        })) {
            TableColumnForEach(columns.indices, id: \.self) { index in
                TableColumn(columns[index]) { line in cell(line, index) }
                    .width(min: width(index), max: width(index))
            }
        }
        #endif
    }

    @ViewBuilder private func cell(_ line: TableLine, _ index: Int) -> some View {
        if let control = line.control(index), control < node.children.count {
            NodeView(id: node.children[control])
        } else {
            Text(line.text(index) ?? "")
        }
    }

    private func width(_ index: Int) -> CGFloat? {
        let widths = node.props["widths"] as? [Any] ?? []
        guard index < widths.count else { return nil }
        return (widths[index] as? NSNumber).map { CGFloat($0.doubleValue) }
    }

    @ViewBuilder private func compactLine(_ line: TableLine) -> some View {
        let rest = line.cells.indices.dropFirst().compactMap { line.text($0) }.filter { !$0.isEmpty }
        let content = VStack(alignment: .leading, spacing: 2) {
            cell(line, 0).font(.headline)
            if !rest.isEmpty {
                Text(rest.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        if node.events.contains("select") {
            Button { UIEvents(id: node.id).send("select", line.id) } label: { content }
                .foregroundStyle(.primary)
        } else {
            content
        }
    }
}

struct NodeTheme: View {
    let node: UINode

    var body: some View {
        Group { Children(node: node) }
            .attachments(node)
            .preferredColorScheme(scheme)
            .tint(hexColour(node.props["accent"]))
    }

    private var scheme: ColorScheme? {
        switch node.string("scheme") {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}

struct NodeForm: View {
    let node: UINode

    var body: some View {
        #if os(macOS)
        Form { Children(node: node) }.formStyle(.grouped)
        #else
        Form { Children(node: node) }
        #endif
    }
}

struct DialogContent: View {
    let node: UINode

    var body: some View {
        let parts = node.children.compactMap { UIStore.shared.nodes[$0] }
        let buttons = parts.first { $0.type == "dialog_actions" }?.children.compactMap { UIStore.shared.nodes[$0] } ?? []
        NavigationStack {
            Group {
                if let content = parts.first(where: { $0.type == "dialog_content" }) {
                    if content.children.count == 1, let only = content.children.first {
                        NodeView(id: only)
                    } else {
                        Form { Children(node: content) }
                    }
                }
            }
            .navigationTitle(node.string("title") ?? "")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItemGroup(placement: .cancellationAction) {
                    ForEach(buttons.filter { $0.string("role") == "cancel" }, id: \.id) { NodeView(id: $0.id) }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    ForEach(buttons.filter { $0.string("role") != "cancel" }, id: \.id) { NodeView(id: $0.id) }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }
}
