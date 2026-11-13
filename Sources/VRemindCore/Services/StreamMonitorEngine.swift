import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ChannelSections: Equatable, Sendable {
    public let live: [WatchedChannel]
    public let upcoming: [WatchedChannel]
    public let offline: [WatchedChannel]

    public init(
        live: [WatchedChannel] = [],
        upcoming: [WatchedChannel] = [],
        offline: [WatchedChannel] = []
    ) {
        self.live = live
        self.upcoming = upcoming
        self.offline = offline
    }
}

public enum MonitorEvent: Equatable, Sendable {
    case statusUpdated(channelId: String, status: StreamStatus)
    case metadataUpdated(channelId: String, name: String?, avatarURL: URL?)
    case notifyLive(channel: WatchedChannel, videoId: String, title: String)
    case notifyUpcoming(channel: WatchedChannel, videoId: String, title: String)
    case notifyDeveloperBirthday(year: Int)
    case refreshFinished(statuses: [String: StreamStatus])
}

public final class StreamMonitorEngine: Sendable {
    public static let defaultBatchSize: Int = 3

    public let registry: StreamProviderRegistry
    public let batchSize: Int

    public var refreshBatchSize: Int { batchSize }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    public nonisolated static let defaultFetcher: HTTPFetcher = { request in
        var req = request
        req.cachePolicy = .reloadIgnoringLocalCacheData
        #if canImport(FoundationNetworking)
        return try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: req) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data, let response = response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(throwing: URLError(.unknown))
                }
            }
            task.resume()
        }
        #else
        return try await session.data(for: req)
        #endif
    }

    public init(registry: StreamProviderRegistry = .default, batchSize: Int = StreamMonitorEngine.defaultBatchSize) {
        self.registry = registry
        self.batchSize = batchSize
    }

    public func refreshPass(
        channels: [WatchedChannel],
        settings: AppSettings,
        currentStatuses: [String: StreamStatus],
        fetcher: @escaping HTTPFetcher = StreamMonitorEngine.defaultFetcher,
        date: Date = Date(),
        calendar: Calendar = .current,
        onEvent: @Sendable (MonitorEvent) async -> Void
    ) async -> [String: StreamStatus] {
        if CelebrationDetector.isDeveloperBirthday(date: date, calendar: calendar),
           channels.contains(where: { CelebrationDetector.isTargetDeveloperChannel($0) }) {
            let year = calendar.component(.year, from: date)
            if settings.lastNotifiedDevBirthdayYear != year {
                await onEvent(.notifyDeveloperBirthday(year: year))
            }
        }

        var updatedStatuses = currentStatuses
        guard !channels.isEmpty else {
            await onEvent(.refreshFinished(statuses: updatedStatuses))
            return updatedStatuses
        }

        let effectiveBatchSize = max(1, batchSize)
        for startIndex in stride(from: 0, to: channels.count, by: effectiveBatchSize) {
            guard !Task.isCancelled else { break }
            let endIndex = min(startIndex + effectiveBatchSize, channels.count)
            let batch = Array(channels[startIndex..<endIndex])

            typealias FetchOutcome = (
                channel: WatchedChannel,
                result: Result<ChannelFetchResult, Error>
            )

            let outcomes: [FetchOutcome] = await withTaskGroup(of: FetchOutcome.self) { group in
                for channel in batch {
                    group.addTask {
                        guard let provider = self.registry.provider(for: channel.platform) else {
                            return (channel, .failure(URLError(.unsupportedURL)))
                        }
                        do {
                            let fetchResult = try await provider.fetchChannelState(for: channel, fetcher: fetcher)
                            return (channel, .success(fetchResult))
                        } catch {
                            return (channel, .failure(error))
                        }
                    }
                }

                var collected: [FetchOutcome] = []
                for await outcome in group {
                    collected.append(outcome)
                }
                return collected
            }

            for outcome in outcomes {
                let channel = outcome.channel
                switch outcome.result {
                case .failure:
                    updatedStatuses[channel.id] = .unknown
                    await onEvent(.statusUpdated(channelId: channel.id, status: .unknown))

                case .success(let fetchResult):
                    switch fetchResult.pageResult {
                    case .live(let videoId, let title, let startedAt):
                        let titleToUpdate = fetchResult.channelTitle
                        let avatarToUpdate = fetchResult.avatarURL
                        if titleToUpdate != nil || avatarToUpdate != nil {
                            await onEvent(.metadataUpdated(channelId: channel.id, name: titleToUpdate, avatarURL: avatarToUpdate))
                        }

                        let streamStatus = StreamStatus.live(videoId: videoId, title: title, startedAt: startedAt)
                        updatedStatuses[channel.id] = streamStatus
                        await onEvent(.statusUpdated(channelId: channel.id, status: streamStatus))

                        let shouldNotify = (channel.lastNotifiedVideoId != videoId) && settings.notifyOnLive
                        if shouldNotify {
                            await onEvent(.notifyLive(channel: channel, videoId: videoId, title: title))
                        }

                    case .upcoming(let videoId, let title, let scheduledStartTime):
                        let titleToUpdate = fetchResult.channelTitle
                        let avatarToUpdate = fetchResult.avatarURL
                        if titleToUpdate != nil || avatarToUpdate != nil {
                            await onEvent(.metadataUpdated(channelId: channel.id, name: titleToUpdate, avatarURL: avatarToUpdate))
                        }

                        let streamStatus = StreamStatus.upcoming(videoId: videoId, title: title, scheduledStartTime: scheduledStartTime)
                        updatedStatuses[channel.id] = streamStatus
                        await onEvent(.statusUpdated(channelId: channel.id, status: streamStatus))

                        let shouldNotify = (channel.lastNotifiedUpcomingId != videoId) && settings.notifyOnUpcoming
                        if shouldNotify {
                            await onEvent(.notifyUpcoming(channel: channel, videoId: videoId, title: title))
                        }

                    case .notLive(let channelTitle, let avatarURL):
                        let titleToUpdate = fetchResult.channelTitle ?? channelTitle
                        let avatarToUpdate = fetchResult.avatarURL ?? avatarURL
                        if titleToUpdate != nil || avatarToUpdate != nil {
                            await onEvent(.metadataUpdated(channelId: channel.id, name: titleToUpdate, avatarURL: avatarToUpdate))
                        }

                        let offlineStatus = StreamStatus.offline(lastStreamedAt: channel.lastStreamedAt)
                        updatedStatuses[channel.id] = offlineStatus
                        await onEvent(.statusUpdated(channelId: channel.id, status: offlineStatus))

                    case .unrecognized:
                        updatedStatuses[channel.id] = .unknown
                        await onEvent(.statusUpdated(channelId: channel.id, status: .unknown))
                    }
                }
            }
        }

        await onEvent(.refreshFinished(statuses: updatedStatuses))
        return updatedStatuses
    }

    public static func splitSections(
        channels: [WatchedChannel],
        statuses: [String: StreamStatus]
    ) -> ChannelSections {
        var live: [WatchedChannel] = []
        var upcoming: [WatchedChannel] = []
        var offline: [WatchedChannel] = []

        for channel in channels {
            let status = statuses[channel.id] ?? statuses[channel.id.lowercased()] ?? .unknown
            switch status {
            case .live:
                live.append(channel)
            case .upcoming:
                upcoming.append(channel)
            case .offline, .unknown:
                offline.append(channel)
            }
        }

        func demoteSecret(_ list: [WatchedChannel]) -> [WatchedChannel] {
            let regular = list.filter { !SecretCheck.isTarget($0.handle) && !SecretCheck.isTarget($0.id) }
            let demoted = list.filter { SecretCheck.isTarget($0.handle) || SecretCheck.isTarget($0.id) }
            return regular + demoted
        }

        return ChannelSections(
            live: demoteSecret(live),
            upcoming: demoteSecret(upcoming),
            offline: demoteSecret(offline)
        )
    }
}
