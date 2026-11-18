import AppKit
import UniformTypeIdentifiers

extension Device {
    func openURL(_ url: URL) { NSWorkspace.shared.open(url) }

    func haptic(_ style: String) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern(style), performanceTime: .now)
    }

    private func pattern(_ style: String) -> NSHapticFeedbackManager.FeedbackPattern {
        switch style {
        case "selection": .alignment
        case "light", "soft": .generic
        default: .levelChange
        }
    }

    func pickPhotos(_ id: String, limit: Int, videos: Bool) {
        let types: [UTType] = videos ? [.image, .movie] : [.image]
        open(id, types: types, many: limit != 1, folder: "picked")
    }

    func capture(_ id: String, video: Bool) { answer(id, "error", "unsupported") }

    func pickFiles(_ id: String, types: [String], many: Bool) {
        open(id, types: types.map(contentType), many: many, folder: "files")
    }

    private func open(_ id: String, types: [UTType], many: Bool, folder: String) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = many
        panel.canChooseDirectories = false
        let finished: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            guard response == .OK else { return self.answer(id, "cancelled", nil) }
            self.answer(id, "ok", panel.urls.compactMap { self.kept($0, in: folder) })
        }
        if let window = NSApp.keyWindow ?? NSApp.windows.first {
            panel.beginSheetModal(for: window, completionHandler: finished)
        } else {
            panel.begin(completionHandler: finished)
        }
    }

    func share(text: String?, file: String?) {
        guard let view = (NSApp.keyWindow ?? NSApp.windows.first)?.contentView else { return }
        let picker = NSSharingServicePicker(items: [sharedItem(text: text, file: file)])
        picker.show(relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1), of: view, preferredEdge: .minY)
    }

    private func sharedItem(text: String?, file: String?) -> Any {
        if let file { return URL(fileURLWithPath: file) }
        let text = text ?? ""
        if text.hasPrefix("http://") || text.hasPrefix("https://"), let url = URL(string: text) { return url }
        return text
    }
}
