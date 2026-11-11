import AppKit
import Foundation
import ServiceManagement

/// Protocol defining a launch-at-login backend provider.
public protocol LaunchAtLoginBackend: Sendable {
    var isEnabled: Bool { get }
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool
}

/// Helper for managing macOS launch-at-login registration.
/// Uses `SMAppService.mainApp` on macOS 13+ (Ventura and later)
/// and falls back to `NSAppleScript` against "System Events" on macOS 12 (Monterey).
public enum LaunchAtLoginHelper {
    private static let lock = NSLock()
    private static var _backend: (any LaunchAtLoginBackend)?

    /// Optional backend override for testing or custom environments.
    public static var backend: (any LaunchAtLoginBackend)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _backend
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _backend = newValue
        }
    }

    /// Resets the backend override to `nil`, restoring system-default resolution.
    public static func resetBackend() {
        lock.lock()
        defer { lock.unlock() }
        _backend = nil
    }

    /// Whether launch-at-login is currently enabled for the application.
    public static var isEnabled: Bool {
        if let customBackend = backend {
            return customBackend.isEnabled
        }
        if #available(macOS 13.0, *) {
            return SMAppServiceBackend.shared.isEnabled
        } else {
            return MontereyAppleScriptBackend.shared.isEnabled
        }
    }

    /// Enables or disables launch-at-login for the application.
    /// Short-circuits if the target state already matches `isEnabled`.
    @discardableResult
    public static func setEnabled(_ enabled: Bool) -> Bool {
        if let customBackend = backend {
            return customBackend.setEnabled(enabled)
        }
        if #available(macOS 13.0, *) {
            return SMAppServiceBackend.shared.setEnabled(enabled)
        } else {
            return MontereyAppleScriptBackend.shared.setEnabled(enabled)
        }
    }

    /// Builds the AppleScript command used to add or remove login items on macOS 12 Monterey.
    public static func makeMontereyAppleScript(enabled: Bool, appPath: String, appName: String) -> String {
        if enabled {
            return "tell application \"System Events\" to make login item at end with properties {path:\"\(appPath)\", hidden:false}"
        } else {
            return "tell application \"System Events\" to delete login item \"\(appName)\""
        }
    }

    /// Builds the AppleScript command used to query existing login item names on macOS 12 Monterey.
    public static func makeMontereyQueryAppleScript() -> String {
        "tell application \"System Events\" to get the name of every login item"
    }
}

/// macOS 13+ (Ventura and later) backend using modern `SMAppService.mainApp`.
@available(macOS 13.0, *)
public final class SMAppServiceBackend: LaunchAtLoginBackend, @unchecked Sendable {
    public static let shared = SMAppServiceBackend()

    public typealias StatusProvider = () -> SMAppService.Status
    public typealias ActionHandler = () throws -> Void

    private let statusProvider: StatusProvider
    private let registerAction: ActionHandler
    private let unregisterAction: ActionHandler

    public init(
        statusProvider: @escaping StatusProvider = { SMAppService.mainApp.status },
        registerAction: @escaping ActionHandler = { try SMAppService.mainApp.register() },
        unregisterAction: @escaping ActionHandler = { try SMAppService.mainApp.unregister() }
    ) {
        self.statusProvider = statusProvider
        self.registerAction = registerAction
        self.unregisterAction = unregisterAction
    }

    public var isEnabled: Bool {
        statusProvider() == .enabled
    }

    @discardableResult
    public func setEnabled(_ enabled: Bool) -> Bool {
        if enabled == isEnabled {
            return true
        }
        do {
            if enabled {
                try registerAction()
            } else {
                try unregisterAction()
            }
            return true
        } catch {
            return false
        }
    }
}

/// macOS 12 (Monterey) fallback backend using `NSAppleScript` against "System Events".
public final class MontereyAppleScriptBackend: LaunchAtLoginBackend, @unchecked Sendable {
    public static let shared = MontereyAppleScriptBackend()

    public typealias Executor = (String) -> (success: Bool, output: [String]?)

    private let lock = NSLock()
    private var _executor: Executor
    private var _appPath: String
    private var _appName: String

    public var appPath: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _appPath
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _appPath = newValue
        }
    }

    public var appName: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _appName
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _appName = newValue
        }
    }

    public var executor: Executor {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _executor
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _executor = newValue
        }
    }

    public static let defaultExecutor: Executor = { scriptSource in
        guard let script = NSAppleScript(source: scriptSource) else {
            return (false, nil)
        }
        var errorDict: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorDict)
        if errorDict != nil {
            return (false, nil)
        }

        var items: [String] = []
        if descriptor.descriptorType == typeAEList {
            for i in 1...descriptor.numberOfItems {
                if let item = descriptor.atIndex(i)?.stringValue {
                    items.append(item)
                }
            }
        } else if let single = descriptor.stringValue {
            items.append(single)
        }
        return (true, items)
    }

    public init(
        appPath: String = Bundle.main.bundlePath,
        appName: String = Bundle.main.infoDictionary?["CFBundleName"] as? String
            ?? Bundle.main.bundleURL.deletingPathExtension().lastPathComponent,
        executor: @escaping Executor = MontereyAppleScriptBackend.defaultExecutor
    ) {
        self._appPath = appPath
        self._appName = appName.isEmpty ? "Caitlyn" : appName
        self._executor = executor
    }

    public var isEnabled: Bool {
        let queryScript = LaunchAtLoginHelper.makeMontereyQueryAppleScript()
        let result = executor(queryScript)
        guard result.success, let list = result.output else {
            return false
        }
        return list.contains(appName)
    }

    @discardableResult
    public func setEnabled(_ enabled: Bool) -> Bool {
        if enabled == isEnabled {
            return true
        }
        let script = LaunchAtLoginHelper.makeMontereyAppleScript(
            enabled: enabled,
            appPath: appPath,
            appName: appName
        )
        let result = executor(script)
        return result.success
    }
}
