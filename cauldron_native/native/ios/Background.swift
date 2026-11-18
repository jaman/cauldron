import Foundation
#if os(macOS)
import AppKit
#else
import BackgroundTasks
#endif

enum Refresh {
    static var identifier: String { (Bundle.main.bundleIdentifier ?? "cauldron") + ".refresh" }

    static var declared: Bool {
        #if os(macOS)
        true
        #else
        (Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String])?.contains(identifier) == true
        #endif
    }

    #if os(macOS)
    private static var scheduler: NSBackgroundActivityScheduler?
    private static var finish: NSBackgroundActivityScheduler.CompletionHandler?

    static func register() {}

    static func schedule(_ id: String, minutes: Double) {
        scheduler?.invalidate()
        let created = NSBackgroundActivityScheduler(identifier: identifier)
        created.repeats = true
        created.interval = minutes * 60
        created.tolerance = minutes * 6
        created.schedule { completion in
            DispatchQueue.main.async {
                finish = completion
                cn_background()
            }
        }
        scheduler = created
        answerRequest(id, "ok", "scheduled")
    }

    static func done() {
        finish?(.finished)
        finish = nil
    }

    static func cancel() {
        scheduler?.invalidate()
        scheduler = nil
    }
    #else
    private static var interval: TimeInterval = 15 * 60
    private static var running: BGAppRefreshTask?

    static func register() {
        guard declared else { return }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            submit()
            running = task
            task.expirationHandler = { finish(false) }
            cn_background()
        }
    }

    static func schedule(_ id: String, minutes: Double) {
        guard declared else { return answerRequest(id, "error", "not_configured") }
        interval = max(minutes, 15) * 60
        submit()
        answerRequest(id, "ok", "scheduled")
    }

    static func done() { finish(true) }

    static func cancel() { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier) }

    private static func submit() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func finish(_ success: Bool) {
        running?.setTaskCompleted(success: success)
        running = nil
    }
    #endif
}
