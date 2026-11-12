import Foundation
import Combine

public enum UpdateCheckResult: Equatable, Sendable {
    case updateAvailable(GitHubRelease)
    case upToDate(latestVersion: String)
    case localVersionNewer(remoteVersion: String)
    case skippedIgnored(version: String)
    case skippedNotConsented
    case failed(String)
}

@MainActor
public final class UpdateService: ObservableObject {
    @Published public var isChecking: Bool = false
    @Published public var lastResult: UpdateCheckResult? = nil

    public let preferencesStore: PreferencesStore
    public let session: URLSession
    public let currentVersion: String
    private let fetchRelease: (() async throws -> GitHubRelease?)?

    public init(
        preferencesStore: PreferencesStore,
        session: URLSession = .shared,
        currentVersion: String = AppConstants.appVersion,
        fetchRelease: (() async throws -> GitHubRelease?)? = nil
    ) {
        self.preferencesStore = preferencesStore
        self.session = session
        self.currentVersion = currentVersion
        self.fetchRelease = fetchRelease
    }

    @discardableResult
    public func checkForUpdates(manual: Bool = false) async -> UpdateCheckResult {
        if !manual && preferencesStore.settings.updateConsent != .allowed {
            let result = UpdateCheckResult.skippedNotConsented
            self.lastResult = result
            return result
        }

        isChecking = true
        defer { isChecking = false }

        do {
            let release: GitHubRelease
            if let customFetch = fetchRelease {
                guard let fetched = try await customFetch() else {
                    let result = UpdateCheckResult.failed("No release found")
                    self.lastResult = result
                    return result
                }
                release = fetched
            } else {
                release = try await performNetworkFetch()
            }

            preferencesStore.settings.lastUpdateCheckDate = Date()

            let remoteVersion = SemanticVersion(release.tagName)
            let localVersion = SemanticVersion(currentVersion)

            let result: UpdateCheckResult
            if remoteVersion > localVersion {
                if !manual && release.tagName == preferencesStore.settings.ignoredUpdateTag {
                    result = .skippedIgnored(version: release.tagName)
                } else {
                    result = .updateAvailable(release)
                }
            } else if localVersion > remoteVersion {
                result = .localVersionNewer(remoteVersion: release.tagName)
            } else {
                result = .upToDate(latestVersion: release.tagName)
            }

            self.lastResult = result
            return result
        } catch {
            let result = UpdateCheckResult.failed(error.localizedDescription)
            self.lastResult = result
            return result
        }
    }

    private func performNetworkFetch() async throws -> GitHubRelease {
        var request = URLRequest(url: AppConstants.githubReleasesLatestURL)
        request.httpMethod = "GET"
        request.setValue("VRemind-macOS/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw NSError(
                domain: "UpdateService",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "GitHub API request failed with status \(httpResponse.statusCode)"]
            )
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GitHubRelease.self, from: data)
    }
}
