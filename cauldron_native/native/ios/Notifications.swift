#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import UserNotifications

final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private let pushKey = "cauldron.push"

    func start() {
        UNUserNotificationCenter.current().delegate = self
    }

    func schedule(_ id: String, _ request: [String: Any]) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    self.add(id, request)
                case .notDetermined:
                    center.requestAuthorization(options: [.alert, .sound, .badge]) { allowed, _ in
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: .cauldronPermissionsChanged, object: nil)
                            allowed ? self.add(id, request) : answerRequest(id, "error", "denied")
                        }
                    }
                default:
                    answerRequest(id, "error", "denied")
                }
            }
        }
    }

    #if os(tvOS)
    private func add(_ id: String, _ request: [String: Any]) {
        answerRequest(id, "error", "unsupported")
    }

    func cancel(_ id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
    #else
    private func add(_ id: String, _ request: [String: Any]) {
        let content = UNMutableNotificationContent()
        content.title = request["title"] as? String ?? ""
        content.body = request["body"] as? String ?? ""
        if request["sound"] as? Bool ?? true { content.sound = .default }
        content.userInfo = ["cauldron_id": id]
        let after = (request["after"] as? NSNumber)?.doubleValue ?? 0
        let trigger = after >= 1 ? UNTimeIntervalNotificationTrigger(timeInterval: after, repeats: false) : nil
        let notification = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(notification) { error in
            DispatchQueue.main.async {
                error == nil ? answerRequest(id, "ok", "scheduled") : answerRequest(id, "error", "unavailable")
            }
        }
    }

    func cancel(_ id: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }
    #endif

    func registerPush(_ id: String) {
        guard Bundle.main.object(forInfoDictionaryKey: "CauldronPush") as? Bool == true else {
            return answerRequest(id, "error", "not_configured")
        }
        UserDefaults.standard.set(id, forKey: pushKey)
        #if os(macOS)
        NSApplication.shared.registerForRemoteNotifications()
        #else
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }

    func registered(_ token: Data) {
        guard let id = pushId else { return }
        let hex = token.map { String(format: "%02x", $0) }.joined()
        answerRequest(id, "ok", ["token": hex, "service": "apns"])
    }

    func failed() {
        guard let id = pushId else { return }
        answerRequest(id, "error", "unavailable")
    }

    func received(_ info: [AnyHashable: Any]) {
        guard let id = pushId else { return }
        answerRequest(id, "ok", ["received": Notifier.payload(info)])
    }

    private var pushId: String? { UserDefaults.standard.string(forKey: pushKey) }

    #if !os(tvOS)
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let info = notification.request.content.userInfo
        let silentToo = (info["aps"] as? [String: Any])?["content-available"] as? Int == 1
        if notification.request.trigger is UNPushNotificationTrigger, !silentToo { received(info) }
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let id = info["cauldron_id"] as? String {
            answerRequest(id, "ok", "opened")
        } else if let id = pushId {
            answerRequest(id, "ok", ["opened": Notifier.payload(info)])
        }
        completionHandler()
    }
    #endif

    private static func payload(_ info: [AnyHashable: Any]) -> [String: Any] {
        var payload: [String: Any] = [:]
        for (key, value) in info {
            guard let key = key as? String, JSONSerialization.isValidJSONObject([key: value]) else { continue }
            payload[key] = value
        }
        return payload
    }
}
