import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import VRemindCore

@Suite struct TwitchStreamProviderTests {
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    @Test func testTwitchResponseParserLivePayload() throws {
        let json = """
        {
          "data": {
            "user": {
              "id": "12345",
              "login": "ironmouse",
              "displayName": "Ironmouse",
              "profileImageURL": "https://static-cdn.jtvnw.net/jtv_user_pictures/avatar.png",
              "stream": {
                "id": "stream999",
                "title": "Cooking with Friends",
                "createdAt": "2026-11-12T20:00:00Z",
                "type": "live"
              }
            }
          }
        }
        """.data(using: .utf8)!

        let expectedDate = Self.isoFormatter.date(from: "2026-11-12T20:00:00Z")
        let pageResult = TwitchResponseParser.parse(data: json)
        #expect(pageResult == .live(videoId: "stream999", title: "Cooking with Friends", startedAt: expectedDate))

        let title = TwitchResponseParser.extractChannelTitle(from: json)
        #expect(title == "Ironmouse")

        let avatar = TwitchResponseParser.extractAvatarURL(from: json)
        #expect(avatar == URL(string: "https://static-cdn.jtvnw.net/jtv_user_pictures/avatar.png"))
    }

    @Test func testTwitchResponseParserOfflinePayload() throws {
        let json = """
        {
          "data": {
            "user": {
              "id": "12345",
              "login": "ironmouse",
              "displayName": "Ironmouse",
              "profileImageURL": "https://static-cdn.jtvnw.net/jtv_user_pictures/avatar.png",
              "stream": null
            }
          }
        }
        """.data(using: .utf8)!

        let expectedAvatar = URL(string: "https://static-cdn.jtvnw.net/jtv_user_pictures/avatar.png")
        let pageResult = TwitchResponseParser.parse(data: json)
        #expect(pageResult == .notLive(channelTitle: "Ironmouse", avatarURL: expectedAvatar))

        let title = TwitchResponseParser.extractChannelTitle(from: json)
        #expect(title == "Ironmouse")

        let avatar = TwitchResponseParser.extractAvatarURL(from: json)
        #expect(avatar == expectedAvatar)
    }

    @Test func testTwitchResponseParserMissingUser() throws {
        let json = """
        {
          "data": {
            "user": null
          }
        }
        """.data(using: .utf8)!

        let pageResult = TwitchResponseParser.parse(data: json)
        #expect(pageResult == .unrecognized)

        let title = TwitchResponseParser.extractChannelTitle(from: json)
        #expect(title == nil)

        let avatar = TwitchResponseParser.extractAvatarURL(from: json)
        #expect(avatar == nil)
    }

    @Test func testTwitchResponseParserGraphQLErrors() throws {
        let json = """
        {
          "errors": [
            {
              "message": "persisted query failed"
            }
          ],
          "data": null
        }
        """.data(using: .utf8)!

        let pageResult = TwitchResponseParser.parse(data: json)
        #expect(pageResult == .unrecognized)

        let title = TwitchResponseParser.extractChannelTitle(from: json)
        #expect(title == nil)

        let avatar = TwitchResponseParser.extractAvatarURL(from: json)
        #expect(avatar == nil)
    }

    @Test func testTwitchResponseParserInvalidJSON() {
        let corrupt = "this is not json".data(using: .utf8)!

        let pageResult = TwitchResponseParser.parse(data: corrupt)
        #expect(pageResult == .unrecognized)

        let title = TwitchResponseParser.extractChannelTitle(from: corrupt)
        #expect(title == nil)

        let avatar = TwitchResponseParser.extractAvatarURL(from: corrupt)
        #expect(avatar == nil)
    }

    @Test func testTwitchResponseParserNonLiveStreamTypeOrMissingId() {
        let rerunJSON = """
        {
          "data": {
            "user": {
              "id": "12345",
              "displayName": "Ironmouse",
              "profileImageURL": "https://static-cdn.jtvnw.net/jtv_user_pictures/avatar.png",
              "stream": {
                "id": "stream888",
                "title": "Rerun stream",
                "createdAt": "2026-11-12T20:00:00Z",
                "type": "rerun"
              }
            }
          }
        }
        """.data(using: .utf8)!

        let expectedAvatar = URL(string: "https://static-cdn.jtvnw.net/jtv_user_pictures/avatar.png")
        let rerunResult = TwitchResponseParser.parse(data: rerunJSON)
        // Non-live stream should safely fall back to notLive or unrecognized
        #expect(rerunResult == .notLive(channelTitle: "Ironmouse", avatarURL: expectedAvatar) || rerunResult == .unrecognized)
        #expect(TwitchResponseParser.extractChannelTitle(from: rerunJSON) == "Ironmouse")
        #expect(TwitchResponseParser.extractAvatarURL(from: rerunJSON) == expectedAvatar)

        let missingIdJSON = """
        {
          "data": {
            "user": {
              "id": "12345",
              "displayName": "Ironmouse",
              "profileImageURL": "https://static-cdn.jtvnw.net/jtv_user_pictures/avatar.png",
              "stream": {
                "id": "",
                "title": "Stream without id",
                "createdAt": "2026-11-12T20:00:00Z",
                "type": "live"
              }
            }
          }
        }
        """.data(using: .utf8)!

        let missingIdResult = TwitchResponseParser.parse(data: missingIdJSON)
        #expect(missingIdResult == .notLive(channelTitle: "Ironmouse", avatarURL: expectedAvatar) || missingIdResult == .unrecognized)
    }

    @Test func testTwitchStreamProviderFetchChannelStateLive() async throws {
        let channel = WatchedChannel(
            id: "twitch:ironmouse",
            platform: .twitch,
            name: "ironmouse",
            handle: "ironmouse"
        )

        let expectedDate = Self.isoFormatter.date(from: "2026-11-12T20:00:00Z")
        let livePayload = """
        {
          "data": {
            "user": {
              "id": "12345",
              "login": "ironmouse",
              "displayName": "Ironmouse",
              "profileImageURL": "https://static-cdn.jtvnw.net/jtv_user_pictures/avatar.png",
              "stream": {
                "id": "stream999",
                "title": "Cooking with Friends",
                "createdAt": "2026-11-12T20:00:00Z",
                "type": "live"
              }
            }
          }
        }
        """.data(using: .utf8)!

        final class RequestBox: @unchecked Sendable {
            var request: URLRequest?
        }
        let box = RequestBox()

        let fetcher: HTTPFetcher = { request in
            box.request = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (livePayload, response)
        }

        let provider = TwitchStreamProvider()
        let result = try await provider.fetchChannelState(for: channel, fetcher: fetcher)

        let capturedRequest = box.request
        #expect(capturedRequest?.url == TwitchStreamProvider.graphQLEndpoint)
        #expect(capturedRequest?.httpMethod == "POST")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Client-ID") == TwitchStreamProvider.publicWebClientID)
        #expect(capturedRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")

        if let bodyData = capturedRequest?.httpBody,
           let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            let variables = body["variables"] as? [String: Any]
            #expect(variables?["login"] as? String == "ironmouse")
        } else {
            #expect(Bool(false), "Missing or malformed HTTP body in Twitch request")
        }

        #expect(result.pageResult == .live(videoId: "stream999", title: "Cooking with Friends", startedAt: expectedDate))
        #expect(result.channelTitle == "Ironmouse")
        #expect(result.avatarURL == URL(string: "https://static-cdn.jtvnw.net/jtv_user_pictures/avatar.png"))
    }

    @Test func testTwitchStreamProviderFetchChannelStateHTTP500() async throws {
        let channel = WatchedChannel(
            id: "twitch:ironmouse",
            platform: .twitch,
            name: "ironmouse",
            handle: "ironmouse"
        )

        let fetcher: HTTPFetcher = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }

        let provider = TwitchStreamProvider()
        let result = try await provider.fetchChannelState(for: channel, fetcher: fetcher)

        #expect(result.pageResult == .unrecognized)
        #expect(result.channelTitle == nil)
        #expect(result.avatarURL == nil)
    }

    @Test func testTwitchStreamProviderPropertiesAndURLs() {
        let provider = TwitchStreamProvider()
        #expect(provider.platform == .twitch)
        #expect(provider.normalizeHandle("@IronMouse") == "ironmouse")
        #expect(provider.normalizeHandle("https://twitch.tv/IronMouse") == "ironmouse")
        #expect(provider.channelURL(for: "ironmouse") == URL(string: "https://www.twitch.tv/ironmouse"))

        let channel = WatchedChannel(
            id: "twitch:ironmouse",
            platform: .twitch,
            name: "Ironmouse",
            handle: "ironmouse"
        )

        let liveStatus = StreamStatus.live(videoId: "stream999", title: "Live", startedAt: nil)
        let offlineStatus = StreamStatus.offline(lastStreamedAt: nil)

        #expect(provider.watchURL(for: channel, status: liveStatus) == URL(string: "https://www.twitch.tv/ironmouse"))
        #expect(provider.watchURL(for: channel, status: offlineStatus) == URL(string: "https://www.twitch.tv/ironmouse"))
    }
}
