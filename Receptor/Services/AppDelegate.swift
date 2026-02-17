#if os(iOS)
import UIKit
import SwiftData
import BackgroundTasks
import os.log

private let lifecycleLog = OSLog(subsystem: "com.alexmiller.receptor", category: "Lifecycle")

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let pid = ProcessInfo.processInfo.processIdentifier
        let proc = ProcessInfo.processInfo.processName
        let keys = launchOptions?.keys.map { "\($0)" }.joined(separator: ", ") ?? "none"
        os_log("[LIFECYCLE] didFinishLaunchingWithOptions — pid=%d proc=%{public}@ launchKeys=[%{public}@]", log: lifecycleLog, type: .default, pid, proc, keys)
        DebugFileLog.write("[LIFECYCLE] didFinishLaunchingWithOptions pid=\(pid) proc=\(proc) keys=[\(keys)]")

        // Register background task
        SyncManager.registerBackgroundTask()

        // Request notification permissions
        SyncManager.requestNotificationPermission()

        // Reconnect background URLSession to pick up in-flight upload tasks
        SyncManager.shared.reconnectBackgroundSession()

        os_log("[LIFECYCLE] didFinishLaunchingWithOptions — complete", log: lifecycleLog, type: .default)
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        let pid = ProcessInfo.processInfo.processIdentifier
        os_log("[LIFECYCLE] applicationDidBecomeActive — pid=%d", log: lifecycleLog, type: .default, pid)
        Task { @MainActor in
            // Reduce .distantFuture locks to short grace period so delegate can fire
            SyncManager.shared.reduceSendingLocks()
            // Also trigger background uploads for any pending/failed thoughts
            SyncManager.shared.requestFlush(trigger: .appBecameActive)
        }
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        let pid = ProcessInfo.processInfo.processIdentifier
        os_log("[LIFECYCLE] applicationDidEnterBackground — pid=%d", log: lifecycleLog, type: .default, pid)
        SyncManager.scheduleBackgroundSync()
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let proc = ProcessInfo.processInfo.processName
        let matches = identifier == SyncManager.backgroundSessionIdentifier
        os_log("[LIFECYCLE] handleEventsForBackgroundURLSession — identifier=%{public}@ matches=%{public}d pid=%d proc=%{public}@", log: lifecycleLog, type: .default, identifier, matches ? 1 : 0, pid, proc)
        DebugFileLog.write("[LIFECYCLE] handleEventsForBackgroundURLSession id=\(identifier) matches=\(matches) pid=\(pid)")

        if matches {
            Task { @MainActor in
                // Ensure modelContainer exists when OS relaunches app for background session delivery.
                // ReceptorApp.init() normally sets this up, but if the OS relaunches us solely for
                // background session events, we need to make sure the container is ready.
                if SyncManager.shared.modelContainer == nil {
                    os_log("[LIFECYCLE] modelContainer is nil — creating for background session delivery", log: lifecycleLog, type: .default)
                    DebugFileLog.write("[LIFECYCLE] Creating modelContainer for background session delivery")
                    do {
                        let dbURL = Configuration.sharedContainerURL!.appendingPathComponent("Receptor.sqlite")
                        let config = ModelConfiguration(url: dbURL)
                        let container = try ModelContainer(for: Thought.self, SyncLogEntry.self, configurations: config)
                        SyncManager.shared.configure(with: container)
                        os_log("[LIFECYCLE] modelContainer created successfully for background delivery", log: lifecycleLog, type: .default)
                    } catch {
                        os_log("[LIFECYCLE] FAILED to create modelContainer: %{public}@", log: lifecycleLog, type: .fault, error.localizedDescription)
                        DebugFileLog.write("[LIFECYCLE] FAILED to create modelContainer: \(error.localizedDescription)")
                    }
                }

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
