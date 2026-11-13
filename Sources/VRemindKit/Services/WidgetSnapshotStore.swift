import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Protocol defining snapshot storage and timeline reloading for WidgetKit extensions.
public protocol WidgetSnapshotStoreProtocol: Sendable {
    func writeSnapshot(channels: [WatchedChannel], statuses: [String: StreamStatus]) async throws
    func readSnapshot() -> WidgetSnapshot?
}

/// Stores and resolves widget snapshots between the main unsandboxed application
/// and the sandboxed WidgetKit extension (`com.caitlyn.vremind.widget`).
public final class WidgetSnapshotStore: WidgetSnapshotStoreProtocol, @unchecked Sendable {
    public static let defaultWidgetBundleIdentifier = "com.caitlyn.vremind.widget"

    /// Shared singleton pointing to the resolved container directory.
    public static let shared = WidgetSnapshotStore()

    public let directoryURL: URL
    public let avatarsDirectoryURL: URL
    public let cacheFileURL: URL

    private let fileManager: FileManager
    private let urlSession: URLSession
    private let timelineReloader: (@Sendable () -> Void)?

    public static let defaultTimelineReloader: (@Sendable () -> Void)? = {
        #if canImport(WidgetKit)
        return {
            WidgetCenter.shared.reloadAllTimelines()
        }
        #else
        return nil
        #endif
    }()

    // MARK: - Initializers

    public init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default,
        urlSession: URLSession = .shared,
        timelineReloader: (@Sendable () -> Void)? = defaultTimelineReloader
    ) {
        let base = directoryURL ?? Self.resolveDefaultDirectoryURL(fileManager: fileManager)
        self.directoryURL = base
        self.avatarsDirectoryURL = base.appendingPathComponent("Avatars", isDirectory: true)
        self.cacheFileURL = base.appendingPathComponent("widget-cache.json", isDirectory: false)
        self.fileManager = fileManager
        self.urlSession = urlSession
        self.timelineReloader = timelineReloader
    }

    public convenience init(baseURL: URL) {
        self.init(directoryURL: baseURL)
    }

    // MARK: - Container Path Resolution

    /// Resolves the Application Support container path for VRemind.
    ///
    /// - In the host application (unsandboxed): Resolves
    ///   `~/Library/Containers/<widgetBundleIdentifier>/Data/Library/Application Support/VRemind/`.
    /// - In the widget extension (sandboxed): Resolves
    ///   `<containerApplicationSupportDirectory>/VRemind/`.
    public static func resolveDefaultDirectoryURL(
        fileManager: FileManager = .default,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        bundleURL: URL = Bundle.main.bundleURL,
        widgetBundleIdentifier: String = defaultWidgetBundleIdentifier
    ) -> URL {
        let isWidgetExtension = bundleIdentifier == widgetBundleIdentifier || bundleURL.pathExtension == "appex"

        if isWidgetExtension,
           let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return appSupport.appendingPathComponent("VRemind", isDirectory: true)
        }

        let homeURL = fileManager.homeDirectoryForCurrentUser
        return homeURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Containers", isDirectory: true)
            .appendingPathComponent(widgetBundleIdentifier, isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("VRemind", isDirectory: true)
    }

    // MARK: - WidgetSnapshotStoreProtocol

    public func writeSnapshot(
        channels: [WatchedChannel],
        statuses: [String: StreamStatus]
    ) async throws {
        // Ensure destination directories exist
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        try fileManager.createDirectory(at: avatarsDirectoryURL, withIntermediateDirectories: true, attributes: nil)

        // Map domain channels and statuses into widget items
        var items: [WidgetChannelItem] = []
        items.reserveCapacity(channels.count)

        for channel in channels {
            let status = statuses[channel.id]
                ?? statuses[channel.id.lowercased()]
                ?? statuses[channel.handle]
                ?? statuses[channel.handle.lowercased()]
                ?? .unknown

            let candidateFilename = Self.avatarFilename(for: channel.handle, platform: channel.platform)
            let avatarDestinationURL = avatarsDirectoryURL.appendingPathComponent(candidateFilename, isDirectory: false)

            var avatarFilename: String? = nil
            if let avatarURL = channel.avatarURL {
                avatarFilename = candidateFilename
                await cacheAvatarIfNeeded(from: avatarURL, to: avatarDestinationURL)
            } else if fileManager.fileExists(atPath: avatarDestinationURL.path) {
                avatarFilename = candidateFilename
            }

            let item = Self.makeChannelItem(channel: channel, status: status, avatarFilename: avatarFilename)
            items.append(item)
        }

        // Sort items so primary channel is spotlighted first
        let sorted = Self.sortChannels(items)
        let snapshot = WidgetSnapshot(generatedAt: Date(), channels: sorted)

        // Write atomically
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(snapshot)
        try data.write(to: cacheFileURL, options: .atomic)

        // Notify WidgetKit
        timelineReloader?()
    }

    public func readSnapshot() -> WidgetSnapshot? {
        guard fileManager.fileExists(atPath: cacheFileURL.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: cacheFileURL)
            let decoder = JSONDecoder()
            return try decoder.decode(WidgetSnapshot.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - Avatar Caching Helper

    private func cacheAvatarIfNeeded(from sourceURL: URL, to destinationURL: URL) async {
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            return
        }

        do {
            let data: Data
            if sourceURL.isFileURL {
                data = try Data(contentsOf: sourceURL)
            } else {
                let (downloadedData, response) = try await urlSession.data(from: sourceURL)
                if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                    return
                }
                data = downloadedData
            }

            guard !data.isEmpty else { return }
            try data.write(to: destinationURL, options: .atomic)
        } catch {
            // Caching is best-effort and must not fail snapshot writing
        }
    }

    // MARK: - Domain Mapping & Sorting

    public static func avatarFilename(for handle: String, platform: StreamPlatform = .youtube) -> String {
        var cleaned = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("@") {
            cleaned.removeFirst()
        }
        let safe = cleaned
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let baseName = safe.isEmpty ? "avatar" : safe
        return "\(platform.rawValue)_\(baseName).jpg"
    }

    public static func makeChannelItem(
        channel: WatchedChannel,
        status: StreamStatus,
        avatarFilename: String?
    ) -> WidgetChannelItem {
        let statusKind: StatusKind
        let streamTitle: String?
        let videoId: String?
        let liveStartedAt: Date?
        let upcomingStartTime: Date?
        let lastStreamedAt: Date?

        switch status {
        case .live(let vId, let title, let startedAt):
            statusKind = .live
            videoId = vId.isEmpty ? nil : vId
            streamTitle = title.isEmpty ? nil : title
            liveStartedAt = startedAt
            upcomingStartTime = nil
            lastStreamedAt = startedAt ?? channel.lastStreamedAt

        case .upcoming(let vId, let title, let scheduledStartTime):
            statusKind = .upcoming
            videoId = vId.isEmpty ? nil : vId
            streamTitle = title.isEmpty ? nil : title
            liveStartedAt = nil
            upcomingStartTime = scheduledStartTime
            lastStreamedAt = channel.lastStreamedAt

        case .offline(let streamedAt):
            statusKind = .offline
            videoId = nil
            streamTitle = nil
            liveStartedAt = nil
            upcomingStartTime = nil
            lastStreamedAt = streamedAt ?? channel.lastStreamedAt

        case .unknown:
            statusKind = .unknown
            videoId = nil
            streamTitle = nil
            liveStartedAt = nil
            upcomingStartTime = nil
            lastStreamedAt = channel.lastStreamedAt
        }

        return WidgetChannelItem(
            platform: channel.platform,
            handle: channel.handle,
            displayName: channel.name,
            avatarFilename: avatarFilename,
            avatarURL: channel.avatarURL,
            statusKind: statusKind,
            streamTitle: streamTitle,
            videoId: videoId,
            liveStartedAt: liveStartedAt,
            upcomingStartTime: upcomingStartTime,
            lastStreamedAt: lastStreamedAt
        )
    }

    /// Sorts channels so the primary channel (featured hero) is first:
    /// 1. `.live` channels: most recently live first (`liveStartedAt` descending).
    /// 2. `.upcoming` channels: starting soonest first (`upcomingStartTime` ascending).
    /// 3. `.offline` channels: most recently streamed first (`lastStreamedAt` descending).
    /// 4. `.unknown` channels.
    /// Preserves original list position as a deterministic tie-breaker.
    public static func sortChannels(_ items: [WidgetChannelItem]) -> [WidgetChannelItem] {
        let indexed = items.enumerated().map { ($0.offset, $0.element) }
        let sorted = indexed.sorted { lhs, rhs in
            let (indexA, itemA) = lhs
            let (indexB, itemB) = rhs

            let rankA = statusRank(itemA.statusKind)
            let rankB = statusRank(itemB.statusKind)
            if rankA != rankB {
                return rankA < rankB
            }

            switch itemA.statusKind {
            case .live:
                if let dateA = itemA.liveStartedAt, let dateB = itemB.liveStartedAt {
                    if dateA != dateB {
                        return dateA > dateB
                    }
                } else if itemA.liveStartedAt != nil {
                    return true
                } else if itemB.liveStartedAt != nil {
                    return false
                }

            case .upcoming:
                if let dateA = itemA.upcomingStartTime, let dateB = itemB.upcomingStartTime {
                    if dateA != dateB {
                        return dateA < dateB
                    }
                } else if itemA.upcomingStartTime != nil {
                    return true
                } else if itemB.upcomingStartTime != nil {
                    return false
                }

            case .offline:
                if let dateA = itemA.lastStreamedAt, let dateB = itemB.lastStreamedAt {
                    if dateA != dateB {
                        return dateA > dateB
                    }
                } else if itemA.lastStreamedAt != nil {
                    return true
                } else if itemB.lastStreamedAt != nil {
                    return false
                }

            case .unknown:
                break
            }

            return indexA < indexB
        }

        return sorted.map(\.1)
    }

    private static func statusRank(_ kind: StatusKind) -> Int {
        switch kind {
        case .live: return 0
        case .upcoming: return 1
        case .offline: return 2
        case .unknown: return 3
        }
    }
}
