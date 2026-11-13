import AppKit
import Foundation
import Testing
import UserNotifications
@testable import VRemindKit

@MainActor
final class MockNotificationCenter: NotificationCenterProtocol {
    weak var delegate: UNUserNotificationCenterDelegate?
    var requests: [UNNotificationRequest] = []
    var requestAuthorizationResult: Bool = true
    var requestAuthorizationError: Error? = nil
    var authorizationStatusResult: UNAuthorizationStatus = .notDetermined
    var requestedOptions: UNAuthorizationOptions?

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        requestedOptions = options
        if let error = requestAuthorizationError {
            throw error
        }
        if requestAuthorizationResult {
            authorizationStatusResult = .authorized
        } else {
            authorizationStatusResult = .denied
        }
        return requestAuthorizationResult
    }

    func add(_ request: UNNotificationRequest) async throws {
        requests.append(request)
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        return authorizationStatusResult
    }
}

struct NotificationServiceTests {
    @Test @MainActor func notificationRequestPayloadConstructionLive() async throws {
        let mockCenter = MockNotificationCenter()
        let service = NotificationService(center: mockCenter)
        await service.notifyLive(
            channelName: "Caitlyn Momochi",
            title: "Late Night Chat",
            videoId: "xyz789",
            channelHandle: "@bukancaitlyn",
            playSound: true
        )

        #expect(mockCenter.requests.count == 1)
        let request = try #require(mockCenter.requests.first)
        #expect(request.content.title == "Caitlyn Momochi")
        #expect(request.content.body == "🔴 LIVE: Late Night Chat")
        #expect(request.content.userInfo["videoId"] as? String == "xyz789")
        #expect(request.content.userInfo["channelHandle"] as? String == "@bukancaitlyn")
        #expect(request.content.sound == .default)
        #expect(service.liveNotificationCount == 1)
    }

    @Test @MainActor func notifyLiveWithoutSound() async throws {
        let mockCenter = MockNotificationCenter()
        let service = NotificationService(center: mockCenter)
        await service.notifyLive(
            channelName: "Caitlyn Momochi",
            title: "Silent Stream",
            videoId: "xyz123",
            playSound: false
        )

        #expect(mockCenter.requests.count == 1)
        let request = try #require(mockCenter.requests.first)
        #expect(request.content.sound == nil)
        #expect(service.liveNotificationCount == 1)
    }

    @Test @MainActor func notificationRequestPayloadConstructionUpcoming() async throws {
        let mockCenter = MockNotificationCenter()
        let service = NotificationService(center: mockCenter)
        await service.notifyUpcoming(
            channelName: "Caitlyn Momochi",
            title: "Karaoke Stream",
            videoId: "abc456",
            channelHandle: "@bukancaitlyn",
            playSound: true
        )

        #expect(mockCenter.requests.count == 1)
        let request = try #require(mockCenter.requests.first)
        #expect(request.content.title == "Caitlyn Momochi")
        #expect(request.content.body == "⏳ UPCOMING: Karaoke Stream")
        #expect(request.content.userInfo["videoId"] as? String == "abc456")
        #expect(request.content.userInfo["channelHandle"] as? String == "@bukancaitlyn")
        #expect(request.content.sound == .default)
        #expect(service.upcomingNotificationCount == 1)
    }

    @Test @MainActor func notifyUpcomingWithoutSound() async throws {
        let mockCenter = MockNotificationCenter()
        let service = NotificationService(center: mockCenter)
        await service.notifyUpcoming(
            channelName: "Caitlyn Momochi",
            title: "Silent Upcoming",
            videoId: "abc789",
            playSound: false
        )

        #expect(mockCenter.requests.count == 1)
        let request = try #require(mockCenter.requests.first)
        #expect(request.content.sound == nil)
        #expect(service.upcomingNotificationCount == 1)
    }

    @Test @MainActor func handleNotificationClickOpensYouTubeURL() {
        var openedURL: URL?
        let service = NotificationService(
            center: MockNotificationCenter(),
            urlOpener: { openedURL = $0 }
        )

        service.handleNotificationClick(userInfo: ["videoId": "xyz789", "channelHandle": "@bukancaitlyn"])
        #expect(openedURL == URL(string: "https://www.youtube.com/watch?v=xyz789"))
    }

    @Test @MainActor func handleNotificationClickIgnoresInvalidUserInfo() {
        var openedURL: URL?
        let service = NotificationService(
            center: MockNotificationCenter(),
            urlOpener: { openedURL = $0 }
        )

        service.handleNotificationClick(userInfo: [:])
        #expect(openedURL == nil)

        service.handleNotificationClick(userInfo: ["videoId": ""])
        #expect(openedURL == nil)

        service.handleNotificationClick(userInfo: ["videoId": "   "])
        #expect(openedURL == nil)

        service.handleNotificationClick(userInfo: ["videoId": 12345])
        #expect(openedURL == nil)
    }

    @Test @MainActor func requestAuthorizationSuccessAndStatusUpdate() async {
        let mockCenter = MockNotificationCenter()
        mockCenter.requestAuthorizationResult = true
        let service = NotificationService(center: mockCenter)

        #expect(service.authorizationStatus == .notDetermined)
        let granted = await service.requestAuthorization()
        #expect(granted == true)
        #expect(service.authorizationStatus == .authorized)
        #expect(mockCenter.requestedOptions == [.alert, .sound, .badge])
    }

    @Test @MainActor func requestAuthorizationFailureAndStatusUpdate() async {
        let mockCenter = MockNotificationCenter()
        mockCenter.requestAuthorizationResult = false
        let service = NotificationService(center: mockCenter)

        let granted = await service.requestAuthorization()
        #expect(granted == false)
        #expect(service.authorizationStatus == .denied)
    }

    @Test @MainActor func refreshAuthorizationStatus() async {
        let mockCenter = MockNotificationCenter()
        mockCenter.authorizationStatusResult = .authorized
        let service = NotificationService(center: mockCenter)

        let status = await service.refreshAuthorizationStatus()
        #expect(status == .authorized)
        #expect(service.authorizationStatus == .authorized)
    }

    @Test @MainActor func defaultInitializerFallsBackToSafeCenterOutsideAppBundle() {
        // Outside an .app bundle (such as in swift test CLI runner),
        // NotificationService() must not crash calling UNUserNotificationCenter.current()
        let service = NotificationService()
        #expect(service.authorizationStatus == .notDetermined)
    }

    @Test("NotificationService posts update available notification payload")
    @MainActor
    func testUpdateNotificationPayload() {
        let service = NotificationService()
        let release = GitHubRelease(
            tagName: "v1.0.2",
            name: "v1.0.2 — Improvements",
            body: "Notes",
            htmlURL: URL(string: "https://github.com")!,
            publishedAt: nil,
            assets: []
        )

        let request = service.makeUpdateNotificationRequest(release: release)
        #expect(request.content.title == "VRemind Update Available")
        #expect(request.content.body.contains("1.0.2"))
        #expect(request.content.userInfo["tagName"] as? String == "v1.0.2")
        #expect(request.content.userInfo["isUpdateNotification"] as? Bool == true)
        #expect(request.content.categoryIdentifier == NotificationService.updateCategoryIdentifier)
        #expect(request.identifier == NotificationService.updateCategoryIdentifier)
    }

    @Test("NotificationService notifyUpdate posts request to notification center")
    @MainActor
    func testNotifyUpdatePostsRequest() async throws {
        let mockCenter = MockNotificationCenter()
        let service = NotificationService(center: mockCenter)
        let release = GitHubRelease(
            tagName: "v1.0.3",
            name: "v1.0.3",
            body: "Release Notes",
            htmlURL: URL(string: "https://github.com")!,
            publishedAt: nil,
            assets: []
        )

        await service.notifyUpdate(release: release)
        #expect(mockCenter.requests.count == 1)
        let request = try #require(mockCenter.requests.first)
        #expect(request.identifier == NotificationService.updateCategoryIdentifier)
        #expect(request.content.title == "VRemind Update Available")
        #expect(request.content.userInfo["tagName"] as? String == "v1.0.3")
    }

    @Test("NotificationService handleNotificationClick invokes update callback for update notification")
    @MainActor
    func testHandleNotificationClickInvokesUpdateCallback() {
        var clickedRelease: GitHubRelease? = nil
        var callbackInvoked = false

        let service = NotificationService(
            center: MockNotificationCenter(),
            onUpdateClicked: { release in
                callbackInvoked = true
                clickedRelease = release
            }
        )

        let release = GitHubRelease(
            tagName: "v1.0.4",
            name: "v1.0.4",
            body: "Notes",
            htmlURL: URL(string: "https://github.com/test")!,
            publishedAt: nil,
            assets: []
        )
        let request = service.makeUpdateNotificationRequest(release: release)

        service.handleNotificationClick(userInfo: request.content.userInfo)
        #expect(callbackInvoked == true)
        #expect(clickedRelease?.tagName == "v1.0.4")
    }

    @Test @MainActor func testNotifyDeveloperBirthdayPayloadAndClick() async throws {
        var openedURL: URL?
        let mockCenter = MockNotificationCenter()
        let service = NotificationService(
            center: mockCenter,
            urlOpener: { openedURL = $0 }
        )

        await service.notifyDeveloperBirthday(year: 2026, playSound: true)

        #expect(mockCenter.requests.count == 1)
        let request = try #require(mockCenter.requests.first)
        #expect(request.identifier == "dev-birthday-2026")
        #expect(request.content.title == "🎉 Happy Birthday to the Developer!")
        #expect(request.content.body.contains("Caitlyn Momochi"))
        #expect(request.content.sound == .default)
        #expect(request.content.userInfo["mailtoURL"] as? String == "mailto:y2karyl@disroot.org?subject=Happy%20Birthday%20Caitlyn!")

        service.handleNotificationClick(userInfo: request.content.userInfo)
        #expect(openedURL?.absoluteString == "mailto:y2karyl@disroot.org?subject=Happy%20Birthday%20Caitlyn!")
    }

    @Test @MainActor func testNotifyDeveloperBirthdaySilent() async throws {
        let mockCenter = MockNotificationCenter()
        let service = NotificationService(center: mockCenter)

        await service.notifyDeveloperBirthday(year: 2026, playSound: false)

        #expect(mockCenter.requests.count == 1)
        let request = try #require(mockCenter.requests.first)
        #expect(request.content.sound == nil)
    }
}
