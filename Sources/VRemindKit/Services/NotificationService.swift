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
    public static let updateCategoryIdentifier = "VREMIND_UPDATE_AVAILABLE"
    public static let updateNotificationCategory = "VREMIND_UPDATE_AVAILABLE"
    public static let devBirthdayEmailURL = URL(string: "mailto:y2karyl@disroot.org?subject=Happy%20Birthday%20Caitlyn!")!

    @Published public private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    public private(set) var liveNotificationCount: Int = 0
    public private(set) var upcomingNotificationCount: Int = 0

    public let center: NotificationCenterProtocol
    private let urlOpener: (URL) -> Void
    public var onUpdateClicked: ((GitHubRelease?) -> Void)?

    public init(
        center: NotificationCenterProtocol? = nil,
        urlOpener: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        onUpdateClicked: ((GitHubRelease?) -> Void)? = nil
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
        self.onUpdateClicked = onUpdateClicked
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

    public func notifyDeveloperBirthday(year: Int, playSound: Bool) async {
        let content = UNMutableNotificationContent()
        content.title = "🎉 Happy Birthday to the Developer!"
        content.body = "Today is Caitlyn Momochi's birthday! Click to send a birthday wish."
        content.userInfo = [
            "mailtoURL": Self.devBirthdayEmailURL.absoluteString
        ]
        content.sound = playSound ? .default : nil

        let identifier = "dev-birthday-\(year)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        do {
            try await center.add(request)
        } catch {
            // Silently handle error or log
        }
    }

    public func handleNotificationClick(userInfo: [AnyHashable: Any]) {
        if let isUpdate = userInfo["isUpdateNotification"] as? Bool, isUpdate {
            let release = Self.decodeRelease(from: userInfo)
            onUpdateClicked?(release)
            return
        } else if userInfo["isUpdateNotification"] != nil {
            let release = Self.decodeRelease(from: userInfo)
            onUpdateClicked?(release)
            return
        }

        if let mailtoString = userInfo["mailtoURL"] as? String,
           let mailtoURL = URL(string: mailtoString),
           mailtoURL.scheme == "mailto" {
            urlOpener(mailtoURL)
            return
        }

        guard let videoId = userInfo["videoId"] as? String,
              !videoId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)") else {
            return
        }
        urlOpener(url)
    }

    public func makeUpdateNotificationRequest(release: GitHubRelease) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "VRemind Update Available"
        content.body = "Version \(release.tagName) is available on GitHub. Click to view release notes and download."
        content.categoryIdentifier = Self.updateCategoryIdentifier
        content.sound = .default

        var userInfo: [String: Any] = [
            "isUpdateNotification": true,
            "tagName": release.tagName,
            "htmlURL": release.htmlURL.absoluteString
        ]
        if let name = release.name {
            userInfo["name"] = name
        }
        if let body = release.body {
            userInfo["body"] = body
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(release),
           let jsonString = String(data: data, encoding: .utf8) {
            userInfo["releaseJSON"] = jsonString
        }
        content.userInfo = userInfo

        return UNNotificationRequest(
            identifier: Self.updateCategoryIdentifier,
            content: content,
            trigger: nil
        )
    }

    public func notifyUpdate(release: GitHubRelease) async {
        let request = makeUpdateNotificationRequest(release: release)
        do {
            try await center.add(request)
        } catch {
            // Silently handle error or log
        }
    }

    private static func decodeRelease(from userInfo: [AnyHashable: Any]) -> GitHubRelease? {
        if let jsonString = userInfo["releaseJSON"] as? String,
           let data = jsonString.data(using: .utf8) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode(GitHubRelease.self, from: data) {
                return decoded
            }
        }
        if let tagName = userInfo["tagName"] as? String {
            let htmlURL = (userInfo["htmlURL"] as? String).flatMap { URL(string: $0) } ?? URL(string: "https://github.com")!
            return GitHubRelease(
                tagName: tagName,
                name: userInfo["name"] as? String,
                body: userInfo["body"] as? String,
                htmlURL: htmlURL
            )
        }
        return nil
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
        let options: UNNotificationPresentationOptions = notification.request.content.sound != nil ? [.banner, .sound] : [.banner]
        completionHandler(options)
    }
}
