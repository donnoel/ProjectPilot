import AppKit
import CloudKit
import OSLog

final class TicksCloudNotificationDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "dn.ProjectPilot", category: "TicksCloud")

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        guard TicksCloudAccess.isConfigured else { return }
        NSApplication.shared.registerForRemoteNotifications()
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo)?.subscriptionID == TicksStore.subscriptionID else {
            return
        }
        NotificationCenter.default.post(name: .ticksCloudChanged, object: nil)
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        logger.error("Ticks notifications unavailable; foreground refresh and periodic retry remain enabled.")
    }
}

extension Notification.Name {
    static let ticksCloudChanged = Notification.Name("projectpilot.ticks.cloudChanged")
}
