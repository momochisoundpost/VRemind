import Foundation
import Testing
@testable import VRemindKit

struct WidgetSnapshotTests {
    // MARK: - Codable Tests

    @Test func snapshotCodableRoundTripAllFieldsPopulated() throws {
        let referenceDate = Date(timeIntervalSince1970: 1731400000)
        let liveDate = Date(timeIntervalSince1970: 1731401000)
        let upcomingDate = Date(timeIntervalSince1970: 1731405000)
        let lastStreamDate = Date(timeIntervalSince1970: 1731300000)

        let channel1 = WidgetChannelItem(
            handle: "@bukancaitlyn",
            displayName: "Caitlyn Momochi",
            avatarFilename: "bukancaitlyn.jpg",
            avatarURL: URL(string: "https://example.com/avatar1.jpg"),
            statusKind: .live,
            streamTitle: "Karaoke Stream ~ Sing along!",
            videoId: "liveVid123",
            liveStartedAt: liveDate,
            upcomingStartTime: nil,
            lastStreamedAt: lastStreamDate
        )

        let channel2 = WidgetChannelItem(
            handle: "@othercreator",
            displayName: "Other Creator",
            avatarFilename: "othercreator.jpg",
            avatarURL: URL(string: "https://example.com/avatar2.jpg"),
            statusKind: .upcoming,
            streamTitle: "Tomorrow's Gaming Stream",
            videoId: "upcVid456",
            liveStartedAt: nil,
            upcomingStartTime: upcomingDate,
            lastStreamedAt: nil
        )

        let channel3 = WidgetChannelItem(
            handle: "@offlinecreator",
            displayName: "Offline Creator",
            avatarFilename: nil,
            avatarURL: nil,
            statusKind: .offline,
            streamTitle: nil,
            videoId: nil,
            liveStartedAt: nil,
            upcomingStartTime: nil,
            lastStreamedAt: lastStreamDate
        )

        let snapshot = WidgetSnapshot(
            generatedAt: referenceDate,
            channels: [channel1, channel2, channel3]
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(WidgetSnapshot.self, from: data)

        #expect(decoded == snapshot)
        #expect(decoded.channels.count == 3)
        #expect(decoded.channels[0].handle == "@bukancaitlyn")
        #expect(decoded.channels[0].displayName == "Caitlyn Momochi")
        #expect(decoded.channels[0].avatarFilename == "bukancaitlyn.jpg")
        #expect(decoded.channels[0].statusKind == .live)
        #expect(decoded.channels[0].streamTitle == "Karaoke Stream ~ Sing along!")
        #expect(decoded.channels[0].videoId == "liveVid123")
        #expect(decoded.channels[0].liveStartedAt == liveDate)
        #expect(decoded.channels[0].upcomingStartTime == nil)
        #expect(decoded.channels[0].lastStreamedAt == lastStreamDate)
    }

    @Test func snapshotCodableEmptyChannels() throws {
        let referenceDate = Date(timeIntervalSince1970: 1731400000)
        let snapshot = WidgetSnapshot(generatedAt: referenceDate, channels: [])

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

        #expect(decoded == snapshot)
        #expect(decoded.channels.isEmpty)
    }

    // MARK: - Identifiable & StatusKind Tests

    @Test func channelItemIdentifierUsesHandle() {
        let item = WidgetChannelItem(
            handle: "@bukancaitlyn",
            displayName: "Caitlyn Momochi"
        )
        #expect(item.id == "@bukancaitlyn")
    }

    @Test func statusKindRawValues() {
        #expect(StatusKind.live.rawValue == "live")
        #expect(StatusKind.upcoming.rawValue == "upcoming")
        #expect(StatusKind.offline.rawValue == "offline")
        #expect(StatusKind.unknown.rawValue == "unknown")
    }

    // MARK: - Deep Link Generation Tests

    @Test func deepLinkWithVideoIdConstructsOpenStreamURL() throws {
        let item = WidgetChannelItem(
            handle: "@bukancaitlyn",
            displayName: "Caitlyn Momochi",
            videoId: "HKieGUH9pzg"
        )

        let url = try #require(item.deepLinkURL)
        #expect(url.scheme == "vremind")
        #expect(url.host == "open-stream")

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let targetParam = components.queryItems?.first(where: { $0.name == "url" })?.value
        #expect(targetParam == "https://www.youtube.com/watch?v=HKieGUH9pzg")
        #expect(url.absoluteString == "vremind://open-stream?url=https://www.youtube.com/watch?v%3DHKieGUH9pzg")
    }

    @Test func deepLinkFallbackToChannelURLWhenVideoIdIsNil() throws {
        let item = WidgetChannelItem(
            handle: "@bukancaitlyn",
            displayName: "Caitlyn Momochi",
            videoId: nil
        )

        let url = try #require(item.deepLinkURL)
        #expect(url.scheme == "vremind")
        #expect(url.host == "open-stream")

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let targetParam = components.queryItems?.first(where: { $0.name == "url" })?.value
        #expect(targetParam == "https://www.youtube.com/@bukancaitlyn")
        #expect(url.absoluteString == "vremind://open-stream?url=https://www.youtube.com/@bukancaitlyn")
    }

    @Test func deepLinkFallbackWhenVideoIdIsEmptyOrWhitespace() throws {
        let item = WidgetChannelItem(
            handle: "bukancaitlyn",
            displayName: "Caitlyn Momochi",
            videoId: "   "
        )

        let url = try #require(item.deepLinkURL)
        #expect(url.scheme == "vremind")
        #expect(url.host == "open-stream")

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let targetParam = components.queryItems?.first(where: { $0.name == "url" })?.value
        #expect(targetParam == "https://www.youtube.com/@bukancaitlyn")
    }
}
