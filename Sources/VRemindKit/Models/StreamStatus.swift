import Foundation

public enum StreamStatus: Codable, Equatable, Sendable {
    case live(videoId: String, title: String, startedAt: Date?)
    case upcoming(videoId: String, title: String, scheduledStartTime: Date?)
    case offline(lastStreamedAt: Date?)
    case unknown
}
