import Combine
import Foundation

@MainActor
public final class ConfigSyncService: ObservableObject {
    @Published public private(set) var config: HubConfig

    private let cacheDirectory: URL
    private let remoteURL: URL
    private let session: URLSession

    private var cacheFileURL: URL {
        cacheDirectory.appendingPathComponent("caitlyn_hub.json")
    }

    public init(
        cacheDirectory: URL,
        remoteURL: URL = AppConstants.remoteConfigURL,
        session: URLSession = .shared
    ) {
        self.cacheDirectory = cacheDirectory
        self.remoteURL = remoteURL
        self.session = session

        let cachedURL = cacheDirectory.appendingPathComponent("caitlyn_hub.json")
        if let data = try? Data(contentsOf: cachedURL),
           let decoded = try? HubConfig.decode(from: data) {
            self.config = decoded
        } else {
            self.config = HubConfig.loadBundledSeed()
        }
    }

    public func sync() async {
        do {
            let (data, response) = try await session.data(from: remoteURL)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return
            }
            let decoded = try HubConfig.decode(from: data)
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try data.write(to: cacheFileURL, options: .atomic)
            self.config = decoded
        } catch {
            // Leave current config and cache untouched on any network or decode failure.
        }
    }

    public static func defaultCacheDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport.appendingPathComponent("CaitlynSwift", isDirectory: true)
    }
}
