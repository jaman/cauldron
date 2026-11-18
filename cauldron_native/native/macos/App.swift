import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make(name: appName)
        Notifier.shared.start()
        Purchases.listen()
        let size = Bundle.main.object(forInfoDictionaryKey: "CauldronWindow") as? [String: Double] ?? [:]
        let width = size["width"] ?? 1100
        let height = size["height"] ?? 760
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = appName
        window.contentViewController = Screen.shared
        window.setContentSize(NSSize(width: width, height: height))
        window.contentMinSize = NSSize(width: size["min_width"] ?? 480, height: size["min_height"] ?? 360)
        window.center()
        window.setFrameAutosaveName("Main")
        window.makeKeyAndOrderFront(nil)
        self.window = window
        Controllers.shared.start()
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func application(_ application: NSApplication, open urls: [URL]) { urls.forEach(linkOpened) }

    func applicationDidBecomeActive(_ notification: Notification) { cn_lifecycle(Int32(CN_LIFECYCLE_ACTIVE)) }
    func applicationDidResignActive(_ notification: Notification) { cn_lifecycle(Int32(CN_LIFECYCLE_INACTIVE)) }
    func applicationDidHide(_ notification: Notification) { cn_lifecycle(Int32(CN_LIFECYCLE_BACKGROUND)) }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Notifier.shared.registered(deviceToken)
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Notifier.shared.failed()
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        Notifier.shared.received(userInfo)
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ProcessInfo.processInfo.processName
    }
}

enum MainMenu {
    static func make(name: String) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenu(name, [
            item("About \(name)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Hide \(name)", #selector(NSApplication.hide(_:)), "h"),
            item("Quit \(name)", #selector(NSApplication.terminate(_:)), "q")
        ]))
        menu.addItem(submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "Z"),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a")
        ]))
        menu.addItem(submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f")
        ]))
        return menu
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let holder = NSMenuItem()
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        holder.submenu = menu
        return holder
    }

    private static func item(_ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
        NSMenuItem(title: title, action: action, keyEquivalent: key)
    }
}

enum UIHost {
    private static var shown = false

    static func show() {
        guard !shown, let window = (NSApp.delegate as? AppDelegate)?.window else { return }
        shown = true
        let frame = window.frame
        let least = window.contentMinSize
        window.contentViewController = NSHostingController(rootView: RootView())
        window.contentMinSize = least
        window.setFrame(frame, display: true)
    }
}

@_cdecl("cn_platform_quit")
func cnPlatformQuit() {
    DispatchQueue.main.async { NSApp.terminate(nil) }
}
