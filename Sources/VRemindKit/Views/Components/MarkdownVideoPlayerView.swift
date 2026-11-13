import AVFoundation
import AVKit
import AppKit
import SwiftUI

@MainActor
public final class MarkdownVideoPlayerController: ObservableObject {
    public let url: URL
    public let player: AVPlayer

    @Published public private(set) var isMuted: Bool = true
    @Published public private(set) var isPaused: Bool = false
    @Published public private(set) var isLoading: Bool = true
    @Published public private(set) var hasFailed: Bool = false

    nonisolated(unsafe) private var statusObservation: NSKeyValueObservation?
    nonisolated(unsafe) private var endObserver: NSObjectProtocol?
    nonisolated(unsafe) private var failedEndObserver: NSObjectProtocol?
    private var isStarted: Bool = false

    public init(url: URL, player: AVPlayer = AVPlayer()) {
        self.url = url
        self.player = player
        self.player.isMuted = true
    }

    deinit {
        statusObservation?.invalidate()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        if let failedEndObserver {
            NotificationCenter.default.removeObserver(failedEndObserver)
        }
    }

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        hasFailed = false
        isLoading = true

        let item = AVPlayerItem(url: url)
        player.isMuted = isMuted
        player.actionAtItemEnd = .none
        player.replaceCurrentItem(with: item)

        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, _ in
            let status = observedItem.status
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch status {
                case .readyToPlay:
                    self.isLoading = false
                    if !self.isPaused {
                        self.player.play()
                    }
                case .failed:
                    self.markFailed()
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.player.seek(to: .zero)
                if !self.isPaused {
                    self.player.play()
                }
            }
        }

        failedEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.markFailed()
            }
        }

        if !isPaused {
            player.play()
        }
    }

    public func stop() {
        player.pause()
        statusObservation?.invalidate()
        statusObservation = nil

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let failedEndObserver {
            NotificationCenter.default.removeObserver(failedEndObserver)
            self.failedEndObserver = nil
        }

        player.replaceCurrentItem(with: nil)
        isStarted = false
    }

    public func toggleMute() {
        isMuted.toggle()
        player.isMuted = isMuted
    }

    public func togglePlayPause() {
        isPaused.toggle()
        if isPaused {
            player.pause()
        } else {
            player.play()
        }
    }

    public func markFailed() {
        hasFailed = true
        isLoading = false
    }
}

private struct AVPlayerContainerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.showsFullScreenToggleButton = false
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

public struct MarkdownVideoPlayerView: View {
    public let url: URL
    public let alt: String?
    public let onOpenInBrowser: (URL) -> Void

    @StateObject private var controller: MarkdownVideoPlayerController

    public init(
        url: URL,
        alt: String? = nil,
        onOpenInBrowser: @escaping (URL) -> Void = LinkOpener.open
    ) {
        self.url = url
        self.alt = alt
        self.onOpenInBrowser = onOpenInBrowser
        _controller = StateObject(wrappedValue: MarkdownVideoPlayerController(url: url))
    }

    public var body: some View {
        Group {
            if controller.hasFailed {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.title3)
                        .foregroundColor(.secondary)

                    Text(alt ?? url.lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Button("Open Video in Browser") {
                        onOpenInBrowser(url)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .padding(.horizontal, 12)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(8)
            } else {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        AVPlayerContainerView(player: controller.player)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                controller.togglePlayPause()
                            }

                        if controller.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else if controller.isPaused {
                            Image(systemName: "play.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.55))
                                .clipShape(Circle())
                                .allowsHitTesting(false)
                        }
                    }

                    Button {
                        controller.toggleMute()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: controller.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            Text(controller.isMuted ? "Muted" : "Sound")
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .background(Color.black.opacity(0.85))
                .cornerRadius(8)
            }
        }
        .onAppear {
            controller.start()
        }
        .onDisappear {
            controller.stop()
        }
    }
}
