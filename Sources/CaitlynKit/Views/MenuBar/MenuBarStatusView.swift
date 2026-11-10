import AppKit
import SwiftUI

public struct MenuBarStatusView: View {
    @ObservedObject private var configService: ConfigSyncService
    @ObservedObject private var watchlistService: WatchlistService
    private let onOpenHub: () -> Void
    private let onQuit: () -> Void
    private let onLayoutChanged: (() -> Void)?

    @State private var shakeTrigger: CGFloat = 0
    @State private var easterEggStartDate: Date?
    @State private var keyMonitor: Any?

    public init(
        configService: ConfigSyncService,
        watchlistService: WatchlistService,
        onOpenHub: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        onLayoutChanged: (() -> Void)? = nil
    ) {
        self.configService = configService
        self.watchlistService = watchlistService
        self.onOpenHub = onOpenHub
        self.onQuit = onQuit
        self.onLayoutChanged = onLayoutChanged
    }

    public static func makePopover(
        configService: ConfigSyncService,
        watchlistService: WatchlistService,
        onOpenHub: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        let rootView = MenuBarStatusView(
            configService: configService,
            watchlistService: watchlistService,
            onOpenHub: onOpenHub,
            onQuit: onQuit,
            onLayoutChanged: { [weak popover] in
                DispatchQueue.main.async {
                    if let view = popover?.contentViewController?.view {
                        view.invalidateIntrinsicContentSize()
                        view.layoutSubtreeIfNeeded()
                        popover?.contentSize = view.fittingSize
                    }
                }
            }
        )
        let controller = NSHostingController(rootView: rootView)
        popover.contentViewController = controller
        popover.contentSize = controller.view.fittingSize
        return popover
    }

    public static func statusLine(status: StreamStatus, lastStreamAt: Date?, now: Date) -> String {
        WatchlistChannelCard.statusLine(status: status, lastStreamAt: lastStreamAt, now: now)
    }

    @MainActor
    public static func configureStatusButton(
        _ button: NSStatusBarButton,
        isLive: Bool,
        flashPhase: Bool
    ) {
        if isLive {
            let baseImage = NSImage(
                systemSymbolName: "dot.radiowaves.left.and.right",
                accessibilityDescription: "Caitlyn Momochi (Live)"
            )
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
                .applying(NSImage.SymbolConfiguration(pointSize: 14, weight: .bold))
            let tinted = baseImage?.withSymbolConfiguration(config) ?? baseImage
            tinted?.isTemplate = false
            button.image = tinted
            button.contentTintColor = .systemRed
            button.alphaValue = flashPhase ? 0.25 : 1.0
        } else {
            let image = NSImage(
                systemSymbolName: "sparkles",
                accessibilityDescription: "Caitlyn Momochi"
            )
            image?.isTemplate = true
            button.image = image
            button.contentTintColor = nil
            button.alphaValue = 1.0
        }
    }

    public var body: some View {
        let channels = watchlistService.channels
        let config = configService.config

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.accent)
                Text("VTuber Watchlist")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Text("\(channels.count)/\(WatchlistService.maxSlots) slots")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(channels) { channel in
                    WatchlistChannelCard(
                        channel: channel,
                        status: watchlistService.status(for: channel),
                        lastStreamAt: channel.isPinned ? config.latestReplayDate : nil,
                        onRemove: channel.isPinned ? nil : {
                            _ = watchlistService.removeChannel(id: channel.id)
                            onLayoutChanged?()
                        }
                    )
                }

                if channels.count < WatchlistService.maxSlots {
                    AddChannelCard(
                        currentCount: channels.count,
                        onAdd: { name, handle in
                            let added = watchlistService.addChannel(name: name, handle: handle)
                            if added {
                                Task {
                                    await watchlistService.refreshAll()
                                }
                            }
                            onLayoutChanged?()
                            return added
                        },
                        onExpansionChanged: {
                            onLayoutChanged?()
                        }
                    )
                }
            }

            HStack(spacing: 8) {
                Button {
                    onOpenHub()
                } label: {
                    Text("Open Full App")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    onQuit()
                } label: {
                    Text("Quit")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(ShakeEffect(shakes: shakeTrigger))
        .overlay(
            Group {
                if let easterEggStartDate {
                    EasterEggOverlayView(startDate: easterEggStartDate)
                }
            }
        )
        .clipped()
        .onAppear {
            startKeyMonitor()
        }
        .onDisappear {
            stopKeyMonitor()
        }
    }

    private func startKeyMonitor() {
        guard keyMonitor == nil else { return }
        var tracker = CheatCodeTracker()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if let chars = event.charactersIgnoringModifiers, tracker.feed(chars) {
                triggerEasterEgg(window: event.window)
                return nil
            }
            return event
        }
    }

    private func stopKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func triggerEasterEgg(window: NSWindow?) {
        let now = Date()
        easterEggStartDate = now
        withAnimation(.easeInOut(duration: 0.55)) {
            shakeTrigger += 5
        }
        if let window {
            shakePopoverWindow(window)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            if easterEggStartDate == now {
                easterEggStartDate = nil
            }
        }
    }

    private func shakePopoverWindow(_ window: NSWindow) {
        let origin = window.frame.origin
        let offsets: [CGFloat] = [-10, 10, -8, 8, -6, 6, -3, 3, 0]
        for (idx, dx) in offsets.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(idx) * 0.045) {
                window.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y))
            }
        }
    }
}
