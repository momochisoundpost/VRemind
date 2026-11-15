import Darwin
import Foundation

public enum UISurface: Hashable, Sendable {
    case popover
    case preferences
    case onboarding
    case updateAvailable
}

public struct PriorityBackend: Sendable {
    public let applyNice: @Sendable (Int32) -> Void
    public let setBackgroundState: @Sendable (Bool) -> Void

    public init(
        applyNice: @escaping @Sendable (Int32) -> Void,
        setBackgroundState: @escaping @Sendable (Bool) -> Void
    ) {
        self.applyNice = applyNice
        self.setBackgroundState = setBackgroundState
    }

    public static let noop = PriorityBackend(
        applyNice: { _ in },
        setBackgroundState: { _ in }
    )

    public static let darwin = PriorityBackend(
        applyNice: { nice in
            _ = Darwin.setpriority(PRIO_PROCESS, 0, nice)
        },
        setBackgroundState: { enabled in
            _ = Darwin.setpriority(PRIO_DARWIN_PROCESS, 0, enabled ? PRIO_DARWIN_BG : 0)
        }
    )
}

@MainActor
public final class ProcessPriorityManager {
    public private(set) var activeSurfaces: Set<UISurface> = []
    public private(set) var isBackgroundThrottled: Bool = false

    private let backend: PriorityBackend

    public init(backend: PriorityBackend = .noop) {
        self.backend = backend
    }

    public func applyLaunchBaseline() {
        backend.applyNice(Int32(PRIO_MAX))
        if activeSurfaces.isEmpty && !isBackgroundThrottled {
            isBackgroundThrottled = true
            backend.setBackgroundState(true)
        }
    }

    public func beginUIActivity(_ surface: UISurface) {
        activeSurfaces.insert(surface)
        if isBackgroundThrottled {
            isBackgroundThrottled = false
            backend.setBackgroundState(false)
        }
    }

    public func endUIActivity(_ surface: UISurface) {
        activeSurfaces.remove(surface)
        if activeSurfaces.isEmpty && !isBackgroundThrottled {
            isBackgroundThrottled = true
            backend.setBackgroundState(true)
        }
    }
}
