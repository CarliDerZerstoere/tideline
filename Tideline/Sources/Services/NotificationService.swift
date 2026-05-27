import Foundation
import UserNotifications

/// Wraps `UNUserNotificationCenter` for the notification scaffolding
/// (task #85). Same shape as `AppLockService`:
///   - `@MainActor` because UN* callbacks come back on arbitrary queues
///     and we always hop back to main before publishing state.
///   - No SwiftUI dependency — settings UI consumes it via a Service.
///   - Pure logic (status mapping, content builder) is testable; the
///     UN* passthrough wrappers are not (they need the iOS runtime).
@MainActor
final class NotificationService {

    /// Probe current authorization state. Cheap; safe to call on every
    /// `.onAppear` / `.onChange(of: scenePhase)` to surface iOS-Settings
    /// changes made while the app was backgrounded.
    func authorizationStatus() async -> NotificationAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return mapAuthorizationStatus(settings.authorizationStatus)
    }

    /// Request authorization. iOS shows its system prompt exactly once
    /// per install; subsequent calls return the previously-decided
    /// status without re-prompting. We request the standard alert +
    /// sound + badge set; critical/provisional are not requested.
    func requestAuthorization() async -> NotificationAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // The throws path covers entitlement / configuration errors,
            // not user-denied. Treat as unknown — the caller will re-poll
            // `authorizationStatus()` to discover the real state.
            return .unknown
        }
        let settings = await center.notificationSettings()
        return mapAuthorizationStatus(settings.authorizationStatus)
    }

    /// Build a notification content object whose lockscreen-visible
    /// fields are deliberately generic (CLAUDE.md hard rule). The
    /// detail payload lands in `userInfo` and is only surfaced once
    /// the app is opened — `userInfo` is NOT visible on the lock
    /// screen, only `title` / `subtitle` / `body` are.
    ///
    /// Callers MUST use this method instead of constructing a raw
    /// `UNMutableNotificationContent`. Test pins the privacy
    /// invariants on the returned object.
    func makePrivacyContent(
        category: NotificationCategory,
        privatePayload: [String: String] = [:]
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        // Lockscreen-safe surface — never reveals cycle/pregnancy state.
        content.title = "Tideline"
        content.body = "Eine neue Beobachtung ist verfügbar."
        content.sound = .default
        // Detail payload lives here; on app open the route picks the
        // right destination by reading `userInfo["category"]`.
        var info: [String: Any] = ["category": category.rawValue]
        for (k, v) in privatePayload {
            // Defence in depth: reject keys that would shadow the
            // category routing key.
            guard k != "category" else { continue }
            info[k] = v
        }
        content.userInfo = info
        return content
    }

    /// Schedule a notification. Returns the identifier when the schedule
    /// succeeds, nil when authorization is missing (no-op on deny —
    /// defence in depth on top of `NotificationGate.shouldDeliver`).
    @discardableResult
    func schedule(
        identifier: String,
        content: UNMutableNotificationContent,
        trigger: UNCalendarNotificationTrigger
    ) async -> String? {
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else {
            return nil
        }
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            return identifier
        } catch {
            return nil
        }
    }

    /// Cancel a pending notification by identifier.
    func cancel(identifier: String) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [identifier]
        )
    }

    /// Cancel every pending notification — used when the user turns
    /// the master toggle off so we don't deliver scheduled work
    /// against an explicitly-revoked permission.
    func cancelAll() async {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}

/// Authorization state with our own enum (instead of leaking
/// `UNAuthorizationStatus`) so callers can switch exhaustively without
/// importing `UserNotifications`.
public enum NotificationAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unknown
}

/// Pure mapping function from `UNAuthorizationStatus` to our enum.
/// Lives outside the actor so it can be unit-tested without
/// constructing a `UNNotificationSettings` (which has no public
/// initialiser; the only way to get one is via the system).
@MainActor
func mapAuthorizationStatus(_ status: UNAuthorizationStatus) -> NotificationAuthorizationStatus {
    switch status {
    case .notDetermined: return .notDetermined
    case .denied:        return .denied
    case .authorized:    return .authorized
    case .provisional:   return .provisional
    case .ephemeral:     return .ephemeral
    @unknown default:    return .unknown
    }
}
