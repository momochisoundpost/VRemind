import Foundation
import ServiceManagement
import Testing
@testable import VRemindKit

struct LaunchAtLoginHelperTests {

    @Test func testLaunchAtLoginToggleState() {
        // Tests interface contract
        LaunchAtLoginHelper.resetBackend()
        let initial = LaunchAtLoginHelper.isEnabled
        let result = LaunchAtLoginHelper.setEnabled(initial)
        #expect(result == true)
        #expect(LaunchAtLoginHelper.isEnabled == initial)
    }

    @Test func testMakeMontereyAppleScript() {
        let addScript = LaunchAtLoginHelper.makeMontereyAppleScript(
            enabled: true,
            appPath: "/Applications/Caitlyn.app",
            appName: "Caitlyn"
        )
        #expect(addScript == "tell application \"System Events\" to make login item at end with properties {path:\"/Applications/Caitlyn.app\", hidden:false}")

        let deleteScript = LaunchAtLoginHelper.makeMontereyAppleScript(
            enabled: false,
            appPath: "/Applications/Caitlyn.app",
            appName: "Caitlyn"
        )
        #expect(deleteScript == "tell application \"System Events\" to delete login item \"Caitlyn\"")
    }

    @Test func testMakeMontereyQueryAppleScript() {
        let queryScript = LaunchAtLoginHelper.makeMontereyQueryAppleScript()
        #expect(queryScript == "tell application \"System Events\" to get the name of every login item")
    }

    @Test func testMontereyBackendIsEnabledReflectsItems() {
        let backendWithApp = MontereyAppleScriptBackend(
            appPath: "/Applications/Caitlyn.app",
            appName: "Caitlyn",
            executor: { _ in (true, ["Finder", "Caitlyn", "Notes"]) }
        )
        #expect(backendWithApp.isEnabled == true)

        let backendWithoutApp = MontereyAppleScriptBackend(
            appPath: "/Applications/Caitlyn.app",
            appName: "Caitlyn",
            executor: { _ in (true, ["Finder", "Notes"]) }
        )
        #expect(backendWithoutApp.isEnabled == false)

        let backendFailure = MontereyAppleScriptBackend(
            appPath: "/Applications/Caitlyn.app",
            appName: "Caitlyn",
            executor: { _ in (false, nil) }
        )
        #expect(backendFailure.isEnabled == false)
    }

    @Test func testMontereyBackendSetEnabledLifecycleAndShortCircuit() {
        var currentItems: [String] = []
        var executedScripts: [String] = []

        let backend = MontereyAppleScriptBackend(
            appPath: "/Applications/Caitlyn.app",
            appName: "Caitlyn",
            executor: { script in
                executedScripts.append(script)
                if script.contains("get the name of every login item") {
                    return (true, currentItems)
                } else if script.contains("make login item at end with properties") {
                    currentItems.append("Caitlyn")
                    return (true, nil)
                } else if script.contains("delete login item") {
                    currentItems.removeAll { $0 == "Caitlyn" }
                    return (true, nil)
                }
                return (false, nil)
            }
        )

        // Initially disabled
        #expect(backend.isEnabled == false)

        // Enable
        let enableResult = backend.setEnabled(true)
        #expect(enableResult == true)
        #expect(backend.isEnabled == true)
        #expect(executedScripts.contains { $0.contains("make login item at end with properties") })

        // Enable again when already enabled -> should short-circuit and not call make login item again
        let scriptCountBefore = executedScripts.count
        let redundantEnableResult = backend.setEnabled(true)
        #expect(redundantEnableResult == true)
        // Only the isEnabled check query script may be executed, but NO make script
        let newScripts = executedScripts.suffix(from: scriptCountBefore)
        #expect(!newScripts.contains { $0.contains("make login item") })

        // Disable
        let disableResult = backend.setEnabled(false)
        #expect(disableResult == true)
        #expect(backend.isEnabled == false)
        #expect(executedScripts.contains { $0.contains("delete login item") })

        // Disable again when already disabled -> should short-circuit and not call delete script
        let scriptCountBeforeRedundantDisable = executedScripts.count
        let redundantDisableResult = backend.setEnabled(false)
        #expect(redundantDisableResult == true)
        let newDisableScripts = executedScripts.suffix(from: scriptCountBeforeRedundantDisable)
        #expect(!newDisableScripts.contains { $0.contains("delete login item") })
    }

    @Test func testMontereyBackendExecutorFailureReturnsFalse() {
        var isEnabledCall = true
        let backend = MontereyAppleScriptBackend(
            appPath: "/Applications/Caitlyn.app",
            appName: "Caitlyn",
            executor: { script in
                if isEnabledCall {
                    isEnabledCall = false
                    return (true, []) // initially disabled
                }
                return (false, nil) // script execution failure
            }
        )

        let result = backend.setEnabled(true)
        #expect(result == false)
    }

    @available(macOS 13.0, *)
    @Test func testSMAppServiceBackendTogglingAndShortCircuit() {
        var currentStatus: SMAppService.Status = .notRegistered
        var registerCallCount = 0
        var unregisterCallCount = 0

        let backend = SMAppServiceBackend(
            statusProvider: { currentStatus },
            registerAction: {
                registerCallCount += 1
                currentStatus = .enabled
            },
            unregisterAction: {
                unregisterCallCount += 1
                currentStatus = .notRegistered
            }
        )

        #expect(backend.isEnabled == false)

        // Enable
        let enableSuccess = backend.setEnabled(true)
        #expect(enableSuccess == true)
        #expect(backend.isEnabled == true)
        #expect(registerCallCount == 1)

        // Redundant enable -> short-circuits
        let redundantEnableSuccess = backend.setEnabled(true)
        #expect(redundantEnableSuccess == true)
        #expect(registerCallCount == 1)

        // Disable
        let disableSuccess = backend.setEnabled(false)
        #expect(disableSuccess == true)
        #expect(backend.isEnabled == false)
        #expect(unregisterCallCount == 1)

        // Redundant disable -> short-circuits
        let redundantDisableSuccess = backend.setEnabled(false)
        #expect(redundantDisableSuccess == true)
        #expect(unregisterCallCount == 1)
    }

    @available(macOS 13.0, *)
    @Test func testSMAppServiceBackendThrowsErrorReturnsFalse() {
        struct MockError: Error {}

        let failingRegisterBackend = SMAppServiceBackend(
            statusProvider: { .notRegistered },
            registerAction: { throw MockError() },
            unregisterAction: {}
        )
        #expect(failingRegisterBackend.setEnabled(true) == false)

        let failingUnregisterBackend = SMAppServiceBackend(
            statusProvider: { .enabled },
            registerAction: {},
            unregisterAction: { throw MockError() }
        )
        #expect(failingUnregisterBackend.setEnabled(false) == false)
    }

    @Test func testLaunchAtLoginHelperWithInjectedBackend() {
        defer { LaunchAtLoginHelper.resetBackend() }

        var state = false
        final class MockBackend: LaunchAtLoginBackend, @unchecked Sendable {
            var stateRef: () -> Bool
            var setState: (Bool) -> Void

            init(stateRef: @escaping () -> Bool, setState: @escaping (Bool) -> Void) {
                self.stateRef = stateRef
                self.setState = setState
            }

            var isEnabled: Bool {
                stateRef()
            }

            func setEnabled(_ enabled: Bool) -> Bool {
                setState(enabled)
                return true
            }
        }

        LaunchAtLoginHelper.backend = MockBackend(
            stateRef: { state },
            setState: { state = $0 }
        )

        #expect(LaunchAtLoginHelper.isEnabled == false)
        let success = LaunchAtLoginHelper.setEnabled(true)
        #expect(success == true)
        #expect(LaunchAtLoginHelper.isEnabled == true)

        let disableSuccess = LaunchAtLoginHelper.setEnabled(false)
        #expect(disableSuccess == true)
        #expect(LaunchAtLoginHelper.isEnabled == false)
    }
}
