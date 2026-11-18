import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif
#if os(iOS)
import ActivityKit
#endif

enum WidgetBridge {
    static func update(_ request: [String: Any]) {
        #if canImport(WidgetKit)
        guard let kind = request["kind"] as? String, let content = request["content"],
              let group = Bundle.main.object(forInfoDictionaryKey: "CauldronAppGroup") as? String,
              let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
                  .appendingPathComponent("Library/Widgets", isDirectory: true),
              let data = try? JSONSerialization.data(withJSONObject: content) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: folder.appendingPathComponent(kind + ".json"), options: .atomic)
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
        #endif
    }
}

enum LiveActivities {
    #if os(iOS)
    static func start(_ id: String, _ request: [String: Any]) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return answerRequest(id, "error", "unavailable") }
        if running(id) != nil {
            update(id, request)
            return answerRequest(id, "ok", "started")
        }
        do {
            _ = try Activity.request(
                attributes: CauldronActivityAttributes(name: id),
                content: ActivityContent(state: state(request), staleDate: nil)
            )
            answerRequest(id, "ok", "started")
        } catch {
            answerRequest(id, "error", "unavailable")
        }
    }

    static func update(_ id: String, _ request: [String: Any]) {
        guard let activity = running(id) else { return }
        let content = ActivityContent(state: state(request), staleDate: nil)
        Task { await activity.update(content) }
    }

    static func finish(_ id: String, _ request: [String: Any]) {
        guard let activity = running(id) else { return }
        let content = ActivityContent(state: state(request), staleDate: nil)
        Task { await activity.end(content, dismissalPolicy: .default) }
    }

    private static func running(_ id: String) -> Activity<CauldronActivityAttributes>? {
        Activity<CauldronActivityAttributes>.activities.first { $0.attributes.name == id }
    }

    private static func state(_ request: [String: Any]) -> CauldronActivityAttributes.ContentState {
        CauldronActivityAttributes.ContentState(
            title: request["title"] as? String ?? "",
            detail: request["detail"] as? String ?? "",
            progress: (request["progress"] as? NSNumber)?.doubleValue,
            icon: request["ios_icon"] as? String ?? "bolt.circle",
            ends: (request["ends_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) },
            endsLabel: request["ends_label"] as? String,
            image: request["image"] as? String,
            compactImage: request["compact_image"] as? String,
            background: request["background"] as? String,
            tint: request["tint"] as? String,
            badge: request["badge"] as? String,
            url: request["url"] as? String
        )
    }
    #else
    static func start(_ id: String, _ request: [String: Any]) { answerRequest(id, "error", "unsupported") }
    static func update(_ id: String, _ request: [String: Any]) {}
    static func finish(_ id: String, _ request: [String: Any]) {}
    #endif
}
