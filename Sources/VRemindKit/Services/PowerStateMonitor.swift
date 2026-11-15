import Combine
import Foundation
import IOKit.ps

public enum PowerSource: Equatable, Sendable {
    case ac
    case battery
}

public enum PowerTier: Equatable, Sendable {
    case normal
    case battery
    case lowPowerMode
}

public struct PowerPolicy: Equatable, Sendable {
    public let tier: PowerTier
    public let pollInterval: TimeInterval
    public let timerLeeway: TimeInterval
    public let batchSize: Int
    public let animationsPaused: Bool
    public let deferBackgroundUpdateChecks: Bool

    public init(
        tier: PowerTier,
        pollInterval: TimeInterval,
        timerLeeway: TimeInterval,
        batchSize: Int,
        animationsPaused: Bool,
        deferBackgroundUpdateChecks: Bool
    ) {
        self.tier = tier
        self.pollInterval = pollInterval
        self.timerLeeway = timerLeeway
        self.batchSize = batchSize
        self.animationsPaused = animationsPaused
        self.deferBackgroundUpdateChecks = deferBackgroundUpdateChecks
    }

    public static func resolve(source: PowerSource, isLowPowerModeEnabled: Bool) -> PowerPolicy {
        if isLowPowerModeEnabled {
            return PowerPolicy(
                tier: .lowPowerMode,
                pollInterval: 900,
                timerLeeway: 180,
                batchSize: 1,
                animationsPaused: true,
                deferBackgroundUpdateChecks: true
            )
        }
        switch source {
        case .battery:
            return PowerPolicy(
                tier: .battery,
                pollInterval: 360,
                timerLeeway: 60,
                batchSize: 2,
                animationsPaused: false,
                deferBackgroundUpdateChecks: false
            )
        case .ac:
            return PowerPolicy(
                tier: .normal,
                pollInterval: 180,
                timerLeeway: 30,
                batchSize: 3,
                animationsPaused: false,
                deferBackgroundUpdateChecks: false
            )
        }
    }
}

@MainActor
public final class PowerStateMonitor: ObservableObject {
    @Published public private(set) var currentPolicy: PowerPolicy

    private let powerSourceProvider: @Sendable () -> PowerSource
    private let lowPowerModeProvider: @Sendable () -> Bool
    private let notificationCenter: NotificationCenter

    private nonisolated(unsafe) var powerStateObserver: (any NSObjectProtocol)?
    private nonisolated(unsafe) var runLoopSource: CFRunLoopSource?
    private nonisolated(unsafe) var contextPointer: UnsafeMutableRawPointer?

    nonisolated public static func mapPowerSourceType(_ rawType: String?) -> PowerSource {
        guard let rawType else { return .ac }
        if rawType == kIOPSBatteryPowerValue {
            return .battery
        }
        return .ac
    }

    nonisolated public static func systemPowerSource() -> PowerSource {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return .ac
        }
        let rawType = IOPSGetProvidingPowerSourceType(blob)?.takeRetainedValue() as String?
        return mapPowerSourceType(rawType)
    }

    public init(
        powerSourceProvider: @escaping @Sendable () -> PowerSource = { PowerStateMonitor.systemPowerSource() },
        lowPowerModeProvider: @escaping @Sendable () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled },
        notificationCenter: NotificationCenter = .default,
        observeSystemPowerSource: Bool = false
    ) {
        self.powerSourceProvider = powerSourceProvider
        self.lowPowerModeProvider = lowPowerModeProvider
        self.notificationCenter = notificationCenter

        let initialSource = powerSourceProvider()
        let initialLPM = lowPowerModeProvider()
        self.currentPolicy = PowerPolicy.resolve(source: initialSource, isLowPowerModeEnabled: initialLPM)

        self.powerStateObserver = notificationCenter.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.refresh()
                }
            } else {
                Task { @MainActor [weak self] in
                    self?.refresh()
                }
            }
        }

        if observeSystemPowerSource {
            let box = PowerObserverContext(monitor: self)
            let pointer = Unmanaged.passRetained(box).toOpaque()
            self.contextPointer = pointer

            let callback: IOPowerSourceCallbackType = { context in
                guard let context else { return }
                let box = Unmanaged<PowerObserverContext>.fromOpaque(context).takeUnretainedValue()
                if Thread.isMainThread {
                    MainActor.assumeIsolated {
                        box.monitor?.refresh()
                    }
                } else {
                    Task { @MainActor [weak box] in
                        box?.monitor?.refresh()
                    }
                }
            }

            if let source = IOPSNotificationCreateRunLoopSource(callback, pointer)?.takeRetainedValue() {
                self.runLoopSource = source
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            } else {
                Unmanaged<PowerObserverContext>.fromOpaque(pointer).release()
                self.contextPointer = nil
            }
        }
    }

    public func refresh() {
        let source = powerSourceProvider()
        let isLPM = lowPowerModeProvider()
        let resolved = PowerPolicy.resolve(source: source, isLowPowerModeEnabled: isLPM)
        if resolved != currentPolicy {
            currentPolicy = resolved
        }
    }

    deinit {
        if let powerStateObserver {
            notificationCenter.removeObserver(powerStateObserver)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CFRunLoopSourceInvalidate(runLoopSource)
        }
        if let contextPointer {
            Unmanaged<PowerObserverContext>.fromOpaque(contextPointer).release()
        }
    }
}

private final class PowerObserverContext: @unchecked Sendable {
    weak var monitor: PowerStateMonitor?
    init(monitor: PowerStateMonitor) {
        self.monitor = monitor
    }
}
