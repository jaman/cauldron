import SwiftUI
import UIKit

final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        application.isIdleTimerDisabled = true
        Refresh.register()
        Purchases.listen()
        Notifier.shared.start()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Notifier.shared.registered(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Notifier.shared.failed()
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Notifier.shared.received(userInfo)
        completionHandler(.newData)
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = Screen.shared
        window.makeKeyAndVisible()
        Hinge.watch(window)
        self.window = window
        Resolver.watch()
        Controllers.shared.start()
        connectionOptions.urlContexts.forEach { linkOpened($0.url) }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        URLContexts.forEach { linkOpened($0.url) }
    }

    func sceneDidBecomeActive(_ scene: UIScene) { cn_lifecycle(Int32(CN_LIFECYCLE_ACTIVE)) }
    func sceneWillResignActive(_ scene: UIScene) { cn_lifecycle(Int32(CN_LIFECYCLE_INACTIVE)) }
    func sceneDidEnterBackground(_ scene: UIScene) { cn_lifecycle(Int32(CN_LIFECYCLE_BACKGROUND)) }
}

enum UIHost {
    private static var shown = false

    static func show() {
        guard !shown, let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else { return }
        shown = true
        window.rootViewController = UIHostingController(rootView: RootView())
    }
}

@_cdecl("cn_platform_quit")
func cnPlatformQuit() {}
