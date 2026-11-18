import AppKit
import SwiftUI

struct MenuBarInstaller: View {
    let node: UINode

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { MenuBarHost.shared.show(node) }
            .onChange(of: node.string("title")) { MenuBarHost.shared.show(node) }
            .onDisappear { MenuBarHost.shared.hide(node.id) }
    }
}

struct MenuBarContent: View {
    let id: String

    var body: some View {
        if let node = UIStore.shared.nodes[id] {
            VStack(spacing: 0) { Children(node: node) }
                .frame(width: 360)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

@MainActor
final class MenuBarHost: NSObject {
    static let shared = MenuBarHost()
    private var items: [String: (item: NSStatusItem, popover: NSPopover)] = [:]

    func show(_ node: UINode) {
        let entry = items[node.id] ?? made(node.id)
        let title = node.string("title") ?? ""
        let symbol = node.string("ios") ?? symbolName(node.string("icon"))
        entry.item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        entry.item.button?.toolTip = title
        items[node.id] = entry
    }

    func hide(_ id: String) {
        guard let entry = items.removeValue(forKey: id) else { return }
        NSStatusBar.system.removeStatusItem(entry.item)
    }

    private func made(_ id: String) -> (item: NSStatusItem, popover: NSPopover) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let popover = NSPopover()
        popover.behavior = .transient
        let hosting = NSHostingController(rootView: MenuBarContent(id: id))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        item.button?.identifier = NSUserInterfaceItemIdentifier(id)
        item.button?.target = self
        item.button?.action = #selector(toggle(_:))
        return (item, popover)
    }

    @objc private func toggle(_ sender: NSStatusBarButton) {
        guard let id = sender.identifier?.rawValue, let entry = items[id] else { return }
        if entry.popover.isShown {
            entry.popover.performClose(sender)
        } else {
            entry.popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            entry.popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func symbolName(_ name: String?) -> String { symbol(name) }
}
