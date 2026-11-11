import AppKit
import Foundation
import UserNotifications

@MainActor
public protocol NotificationCenterProtocol: AnyObject {
    var delegate: UNUserNotificationCenterDelegate? { get set }
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func authorizationStatus() async -> UNAuthorizationStatus
    func getNotificationSettings() async -> UNNotificationSettings?
}

public extension NotificationCenterProtocol {
    func getNotificationSettings() async -> UNNotificationSettings? {
        nil
    }
}

@MainActor
public final class SystemNotificationCenter: NotificationCenterProtocol {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter) {
        self.center = center
    }

    public var delegate: UNUserNotificationCenterDelegate? {
        get { center.delegate }
        set { center.delegate = newValue }
    }

    public func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    public func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    public func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    public func getNotificationSettings() async -> UNNotificationSettings? {
        await center.notificationSettings()
    }
}

@MainActor
public final class NoOpNotificationCenter: NotificationCenterProtocol {
    public weak var delegate: UNUserNotificationCenterDelegate?
    public var status: UNAuthorizationStatus

    public init(status: UNAuthorizationStatus = .notDetermined) {
        self.status = status
    }

    public func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        false
    }

    public func add(_ request: UNNotificationRequest) async throws {}

    public func authorizationStatus() async -> UNAuthorizationStatus {
        status
    }

    public func getNotificationSettings() async -> UNNotificationSettings? {
        nil
    }
}

@MainActor
public final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published public private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    public private(set) var liveNotificationCount: Int = 0
    public private(set) var upcomingNotificationCount: Int = 0

    public let center: NotificationCenterProtocol
    private let urlOpener: (URL) -> Void

    public init(
        center: NotificationCenterProtocol? = nil,
        urlOpener: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        let resolvedCenter: NotificationCenterProtocol
        if let center = center {
            resolvedCenter = center
        } else if Bundle.main.bundleURL.pathExtension == "app" {
            resolvedCenter = SystemNotificationCenter(center: UNUserNotificationCenter.current())
        } else {
            resolvedCenter = NoOpNotificationCenter()
        }
        self.center = resolvedCenter
        self.urlOpener = urlOpener
        super.init()
        self.center.delegate = self
    }

    @discardableResult
    public func refreshAuthorizationStatus() async -> UNAuthorizationStatus {
        let status = await center.authorizationStatus()
        self.authorizationStatus = status
        return status
    }

    @discardableResult
    public func requestAuthorization(options: UNAuthorizationOptions = [.alert, .sound, .badge]) async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: options)
            await refreshAuthorizationStatus()
            return granted
        } catch {
            await refreshAuthorizationStatus()
            return false
        }
    }

    public func notifyLive(
        channelName: String,
        title: String,
        videoId: String,
        channelHandle: String = "",
        playSound: Bool
    ) async {
        liveNotificationCount += 1

        let content = UNMutableNotificationContent()
        content.title = channelName
        content.body = "🔴 LIVE: \(title)"
        content.userInfo = [
            "videoId": videoId,
            "channelHandle": channelHandle
        ]
        content.sound = playSound ? .default : nil

        let identifier = "live-\(videoId.isEmpty ? UUID().uuidString : videoId)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        do {
            try await center.add(request)
        } catch {
            // Silently handle error or log
        }
    }

    public func notifyUpcoming(
        channelName: String,
        title: String,
        videoId: String,
        channelHandle: String = "",
        playSound: Bool
    ) async {
        upcomingNotificationCount += 1

        let content = UNMutableNotificationContent()
        content.title = channelName
        content.body = "⏳ UPCOMING: \(title)"
        content.userInfo = [
            "videoId": videoId,
            "channelHandle": channelHandle
        ]
        content.sound = playSound ? .default : nil

        let identifier = "upcoming-\(videoId.isEmpty ? UUID().uuidString : videoId)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        do {
            try await center.add(request)
        } catch {
            // Silently handle error or log
        }
    }

    public func handleNotificationClick(userInfo: [AnyHashable: Any]) {
        guard let videoId = userInfo["videoId"] as? String,
              !videoId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)") else {
            return
        }
        urlOpener(url)
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor in
            self.handleNotificationClick(userInfo: userInfo)
            completionHandler()
        }
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
