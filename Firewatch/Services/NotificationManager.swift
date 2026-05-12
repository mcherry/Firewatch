import UserNotifications

final class NotificationManager: NSObject, Sendable, UNUserNotificationCenterDelegate {

    func setup() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("Notification permission error: \(error)")
            return false
        }
    }

    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func sendStatusChangeNotification(service: ServiceInfo, previousHealth: ServiceHealth) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        guard settings.authorizationStatus == .authorized else {
            NSLog("[Firewatch] Notification blocked: authorization status is \(settings.authorizationStatus.rawValue), not authorized")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "\(service.name) Status Change"
        content.body = "\(service.name) is now \(service.health.displayName) (was \(previousHealth.displayName))"
        content.sound = .default
        content.categoryIdentifier = "STATUS_CHANGE"

        let identifier = "status-\(service.id)-\(Int(Date().timeIntervalSince1970))"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
            NSLog("[Firewatch] Notification delivered: [\(identifier)] \(content.body)")
        } catch {
            NSLog("[Firewatch] Notification FAILED: [\(identifier)] \(error)")
        }
    }

    // Show notifications even when the app is in the foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
