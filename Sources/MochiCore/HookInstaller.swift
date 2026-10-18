import Foundation

public struct HookInstallResult: Equatable {
    public var connected: Bool
    public var hook: String
    public var tasks: Int
    public var error: String?
    public var needsPrivacy: Bool

    public init(connected: Bool, hook: String, tasks: Int = 0, error: String? = nil, needsPrivacy: Bool = false) {
        self.connected = connected
        self.hook = hook
        self.tasks = tasks
        self.error = error
        self.needsPrivacy = needsPrivacy
    }

    public var dictionary: [String: Any] {
        var payload: [String: Any] = [
            "connected": connected,
            "hook": hook,
            "tasks": tasks,
            "needsPrivacy": needsPrivacy
        ]
        if let error { payload["error"] = error }
        return payload
    }
}

public enum HookInstaller {
    public static let events = [
        "beforeSubmitPrompt",
        "sessionStart",
        "subagentStart",
        "preToolUse",
        "postToolUse",
        "postToolUseFailure",
        "beforeShellExecution",
        "afterShellExecution",
        "beforeMCPExecution",
        "afterMCPExecution",
        "afterAgentThought",
        "sessionEnd",
        "subagentStop"
    ]
    public static let permissionEvents: Set<String> = ["beforeShellExecution", "beforeMCPExecution"]

    public static func status(hooksURL: URL, binaryURL: URL, tasksURL: URL) -> HookInstallResult {
        let connected = isInstalled(hooksURL: hooksURL, binaryURL: binaryURL)
        let count = connected ? TaskReader.load(tasksURL: tasksURL, includePrompts: false).count : 0
        return HookInstallResult(connected: connected, hook: binaryURL.path, tasks: count)
    }

    public static func install(hooksURL: URL, binaryURL: URL, tasksURL: URL, privacyAccepted: Bool) -> HookInstallResult {
        guard privacyAccepted else {
            return HookInstallResult(connected: false, hook: binaryURL.path, needsPrivacy: true)
        }
        guard FileManager.default.isExecutableFile(atPath: binaryURL.path) else {
            return HookInstallResult(connected: false, hook: binaryURL.path, error: "hook program missing")
        }
        backup(hooksURL)
        var root = read(hooksURL)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let command = binaryURL.path
        for event in events {
            var entries = hooks[event] as? [[String: Any]] ?? []
            entries.removeAll { isOurs($0) }
            var entry: [String: Any] = [
                "command": command,
                AppConfig.hookMarker: AppConfig.hookVersion
            ]
            if permissionEvents.contains(event) {
                entry["timeout"] = 300
            }
            entries.append(entry)
            hooks[event] = entries
        }
        root["version"] = 1
        root["hooks"] = hooks
        do {
            try AtomicFile.writeJSON(root, to: hooksURL)
        } catch {
            return HookInstallResult(connected: false, hook: binaryURL.path, error: "could not write hooks")
        }
        return status(hooksURL: hooksURL, binaryURL: binaryURL, tasksURL: tasksURL)
    }

    public static func remove(hooksURL: URL, binaryURL: URL, tasksURL: URL) -> HookInstallResult {
        backup(hooksURL)
        var root = read(hooksURL)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var cleaned: [String: Any] = [:]
        for (event, raw) in hooks {
            let entries = (raw as? [[String: Any]] ?? []).filter { !isOurs($0) }
            if !entries.isEmpty {
                cleaned[event] = entries
            }
        }
        hooks = cleaned
        root["hooks"] = hooks
        try? AtomicFile.writeJSON(root, to: hooksURL)
        return status(hooksURL: hooksURL, binaryURL: binaryURL, tasksURL: tasksURL)
    }

    private static func isInstalled(hooksURL: URL, binaryURL: URL) -> Bool {
        let hooks = read(hooksURL)["hooks"] as? [String: Any] ?? [:]
        for raw in hooks.values {
            for entry in raw as? [[String: Any]] ?? [] where isOurs(entry) {
                let command = entry["command"] as? String ?? ""
                if command == binaryURL.path || command.contains("MochiHookCLI") {
                    return FileManager.default.isExecutableFile(atPath: binaryURL.path) || FileManager.default.isExecutableFile(atPath: command)
                }
            }
        }
        return false
    }

    private static func isOurs(_ entry: [String: Any]) -> Bool {
        if entry[AppConfig.hookMarker] != nil { return true }
        let command = entry["command"] as? String ?? ""
        return command.contains("MochiHookCLI") || command.contains("mochi-island-status.py")
    }

    private static func read(_ url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    private static func backup(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let backup = url.appendingPathExtension("mochi-island.bak")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.copyItem(at: url, to: backup)
    }
}
