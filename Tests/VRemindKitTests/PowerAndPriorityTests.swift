import Combine
import Darwin
import Foundation
import Testing
@testable import VRemindKit

struct PowerAndPriorityTests {
    @Test func testPowerPolicyTierResolutionAndSourceMapping() {
        #expect(PowerStateMonitor.mapPowerSourceType("Battery Power") == .battery)
        #expect(PowerStateMonitor.mapPowerSourceType("AC Power") == .ac)
        #expect(PowerStateMonitor.mapPowerSourceType("UPS Power") == .ac)
        #expect(PowerStateMonitor.mapPowerSourceType(nil) == .ac)

        let normal = PowerPolicy.resolve(source: .ac, isLowPowerModeEnabled: false)
        #expect(normal.tier == .normal)
        #expect(normal.pollInterval == 180)
        #expect(normal.timerLeeway == 30)
        #expect(normal.batchSize == 3)
        #expect(normal.animationsPaused == false)
        #expect(normal.deferBackgroundUpdateChecks == false)

        let battery = PowerPolicy.resolve(source: .battery, isLowPowerModeEnabled: false)
        #expect(battery.tier == .battery)
        #expect(battery.pollInterval == 360)
        #expect(battery.timerLeeway == 60)
        #expect(battery.batchSize == 2)
        #expect(battery.animationsPaused == false)
        #expect(battery.deferBackgroundUpdateChecks == false)

        let lpmOnAC = PowerPolicy.resolve(source: .ac, isLowPowerModeEnabled: true)
        let lpmOnBattery = PowerPolicy.resolve(source: .battery, isLowPowerModeEnabled: true)
        #expect(lpmOnAC == lpmOnBattery)
        #expect(lpmOnAC.tier == .lowPowerMode)
        #expect(lpmOnAC.pollInterval == 900)
        #expect(lpmOnAC.timerLeeway == 180)
        #expect(lpmOnAC.batchSize == 1)
        #expect(lpmOnAC.animationsPaused == true)
        #expect(lpmOnAC.deferBackgroundUpdateChecks == true)
    }

    @Test @MainActor func testPowerStateMonitorObservesTransitionsWithoutDuplicatePublishes() async {
        let sourceBox = ValueBox<PowerSource>(.ac)
        let lpmBox = ValueBox<Bool>(false)
        let center = NotificationCenter()

        let monitor = PowerStateMonitor(
            powerSourceProvider: { sourceBox.get() },
            lowPowerModeProvider: { lpmBox.get() },
            notificationCenter: center,
            observeSystemPowerSource: false
        )

        #expect(monitor.currentPolicy.tier == .normal)

        var publishedPolicies: [PowerPolicy] = []
        var cancellables = Set<AnyCancellable>()
        monitor.$currentPolicy
            .dropFirst()
            .sink { publishedPolicies.append($0) }
            .store(in: &cancellables)

        // Unchanged refresh should not re-publish
        monitor.refresh()
        #expect(publishedPolicies.isEmpty)

        // Switch to battery
        sourceBox.set(.battery)
        monitor.refresh()
        #expect(publishedPolicies.map(\.tier) == [.battery])

        // Post NSProcessInfoPowerStateDidChange with Low Power Mode enabled
        lpmBox.set(true)
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        for _ in 0..<20 {
            if monitor.currentPolicy.tier == .lowPowerMode { break }
            await Task.yield()
        }
        #expect(monitor.currentPolicy.tier == .lowPowerMode)
        #expect(publishedPolicies.map(\.tier) == [.battery, .lowPowerMode])
    }

    @Test @MainActor func testProcessPriorityManagerTracksOverlappingUISurfaces() {
        let niceCalls = ValueBox<[Int32]>([])
        let bgCalls = ValueBox<[Bool]>([])

        let spyBackend = PriorityBackend(
            applyNice: { nice in niceCalls.set(niceCalls.get() + [nice]) },
            setBackgroundState: { enabled in bgCalls.set(bgCalls.get() + [enabled]) }
        )

        let manager = ProcessPriorityManager(backend: spyBackend)
        manager.applyLaunchBaseline()

        #expect(niceCalls.get() == [Int32(PRIO_MAX)])
        #expect(bgCalls.get() == [true])
        #expect(manager.isBackgroundThrottled == true)

        // Popover opens -> lifts background throttle
        manager.beginUIActivity(.popover)
        #expect(bgCalls.get() == [true, false])
        #expect(manager.isBackgroundThrottled == false)

        // Preferences opens while popover is still open -> no duplicate syscall
        manager.beginUIActivity(.preferences)
        #expect(bgCalls.get() == [true, false])
        #expect(manager.activeSurfaces == [.popover, .preferences])

        // Popover closes while Preferences remains open -> stays unthrottled
        manager.endUIActivity(.popover)
        #expect(bgCalls.get() == [true, false])
        #expect(manager.isBackgroundThrottled == false)

        // Preferences closes -> all surfaces closed -> re-engages background throttle
        manager.endUIActivity(.preferences)
        #expect(bgCalls.get() == [true, false, true])
        #expect(manager.isBackgroundThrottled == true)
        #expect(manager.activeSurfaces.isEmpty)
    }

    @Test @MainActor func testPowerStateMonitorWithSystemPowerSourceObserver() {
        let monitor = PowerStateMonitor(
            powerSourceProvider: { .ac },
            lowPowerModeProvider: { false },
            notificationCenter: NotificationCenter(),
            observeSystemPowerSource: true
        )
        #expect(monitor.currentPolicy.tier == .normal)
    }

    @Test func testPriorityBackendNoop() {
        PriorityBackend.noop.applyNice(0)
        PriorityBackend.noop.setBackgroundState(false)
        #expect(Bool(true))
    }

    @Test func testSystemPowerSourceCall() {
        let source = PowerStateMonitor.systemPowerSource()
        #expect(source == .ac || source == .battery)
    }
}
