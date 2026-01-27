#if os(iOS)
import UIKit
import BackgroundTasks

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register background task
        SyncManager.registerBackgroundTask()

        // Request notification permissions
        SyncManager.requestNotificationPermission()

        // Reconnect background URLSession to pick up in-flight wake pings
        SyncManager.shared.reconnectBackgroundSession()

        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        Task { @MainActor in
            SyncManager.shared.requestFlush(trigger: .appBecameActive)
        }
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        SyncManager.scheduleBackgroundSync()
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        if identifier == SyncManager.backgroundSessionIdentifier {
            Task { @MainActor in
                SyncManager.shared.backgroundSessionCompletionHandler = completionHandler
                // Touching the session re-attaches the delegate so callbacks flow
                SyncManager.shared.reconnectBackgroundSession()
            }
        } else {
            completionHandler()
        }
    }
}
#endif
