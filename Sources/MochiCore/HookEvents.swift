import Foundation

/// One agent hook delivery, reduced to the fields Mochi keeps.
/// Prompt, command, tool input, and message text are never stored.
public struct HookOutcome: Equatable {
    public var id: String
    public var source: String
    public var title: String
    public var status: String
    public var kind: String
    public var requestID: String
    public var questionID: String
    public var options: [[String: String]]
    public var waitsForPermission: Bool
    /// `cursor` or `codex` when the hook must answer allow or deny. Empty prints `{}`.
    public var permissionStyle: String
    /// Short category such as Chat or Shell. Never prompt or command text.
    public var detail: String

    public init(
        id: String,
        source: String,
        title: String,
        status: String,
        kind: String = "",
        requestID: String = "",
        questionID: String = "",
        options: [[String: String]] = [],
        waitsForPermission: Bool = false,
        permissionStyle: String = "",
        detail: String = ""
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.status = status
        self.kind = kind
        self.requestID = requestID
        self.questionID = questionID
        self.options = options
        self.waitsForPermission = waitsForPermission
        self.permissionStyle = permissionStyle
        self.detail = detail
    }
}

public enum HookEvents {
    public static func interpret(
        sourceFlag: String?,
        payload: [String: Any],
        environment: [String: String] = [:],
        eventFlag: String? = nil
    ) -> HookOutcome? {
        let event = eventName(in: payload, fallback: eventFlag)
        guard !event.isEmpty else { return nil }
        let source = resolvedSource(flag: sourceFlag, payload: payload, environment: environment)
        let mapped = status(for: event, payload: payload, source: source)
        guard !mapped.isEmpty else { return nil }
        let permission = isPermission(event, source: source)
        let waits = permission && (source == "cursor" || source == "codex")
        let choice = choiceOptions(payload: payload, event: event)
        let options = waits ? allowDeny : choice.options
        let kind = waits ? "permission" : choice.kind
        return HookOutcome(
            id: sessionID(in: payload, source: source),
            source: source,
            title: SlotFace.displayName(for: source),
            status: mapped,
            kind: mapped == "wait" && waits ? kind : (mapped == "wait" ? "" : ""),
            requestID: waits ? requestID(in: payload) : "",
            questionID: waits ? choice.questionID : "",
            options: waits ? options : [],
            waitsForPermission: waits,
            permissionStyle: waits ? (source == "codex" ? "codex" : "cursor") : "",
            detail: safeDetail(for: event, source: source)
        )
    }

    /// Merges one delivery into the task dictionary. The stored record is id, agent, status, and time,
    /// plus the permission fields the bubble needs to answer. It does not keep prompt or command text.
    public static func merge(_ outcome: HookOutcome, into tasks: inout [String: Any], now: Double) {
        let (oldKey, previous) = find(tasks, id: outcome.id)
        var status = outcome.status
        var requestID = outcome.requestID
        var kind = outcome.kind
        var options = outcome.options
        var questionID = outcome.questionID
        if status == "closed" {
            tasks.removeValue(forKey: outcome.id)
            if oldKey != outcome.id { tasks.removeValue(forKey: oldKey) }
            return
        }
        if status == "heartbeat" {
            status = previous["status"] as? String ?? "running"
            if !["running", "wait", "done", "fail"].contains(status) { status = "running" }
            requestID = previous["request_id"] as? String ?? ""
            kind = previous["kind"] as? String ?? ""
            questionID = previous["question_id"] as? String ?? ""
            options = stringOptions(previous["options"])
        }
        var detail = outcome.detail
        if detail.isEmpty {
            detail = string(previous["detail"])
        }
        if oldKey != outcome.id { tasks.removeValue(forKey: oldKey) }
        var record: [String: Any] = [
            "id": outcome.id,
            "title": outcome.title,
            "status": status,
            "source": outcome.source,
            "updated": now
        ]
        if !detail.isEmpty {
            record["detail"] = detail
        }
        if status == "wait" {
            record["kind"] = kind
            record["options"] = options
            record["request_id"] = requestID
            if !questionID.isEmpty { record["question_id"] = questionID }
        }
        tasks[outcome.id] = record
    }

    public static func commit(_ outcome: HookOutcome, tasksURL: URL, now: Double = Date().timeIntervalSince1970) {
        var root = readRoot(tasksURL)
        var tasks = root["tasks"] as? [String: Any] ?? [:]
        merge(outcome, into: &tasks, now: now)
        root["tasks"] = tasks
        try? AtomicFile.writeJSON(root, to: tasksURL)
    }

    public static func permissionStdout(style: String, action: String) -> [String: Any] {
        let decision = action == "deny" ? "deny" : "allow"
        if style == "codex" {
            return [
                "hookSpecificOutput": [
                    "hookEventName": "PermissionRequest",
                    "decision": ["behavior": decision]
                ]
            ]
        }
        return ["permission": decision]
    }

    private static let allowDeny: [[String: String]] = [
        ["id": "allow", "label": "Allow"],
        ["id": "deny", "label": "Deny"]
    ]

    private static func resolvedSource(flag: String?, payload: [String: Any], environment: [String: String]) -> String {
        if grokRuntime(environment) { return "grok-bot" }
        if let version = payload["cursor_version"] as? String,
           !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "cursor"
        }
        let flagged = AgentLaunch.normalize(flag)
        switch flagged {
        case "codex", "claude", "grok-bot", "copilot", "opencode":
            return flagged
        default:
            return "cursor"
        }
    }

    /// Grok Build sets one of these for every hook it runs, including a Cursor hook imported into Grok.
    private static func grokRuntime(_ environment: [String: String]) -> Bool {
        for key in ["GROK_SESSION_ID", "GROK_HOOK_EVENT"] {
            let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !value.isEmpty { return true }
        }
        return false
    }

    /// Copilot's camelCase payload does not include the event name, so the installed command passes it.
    /// A name already on the payload wins. Grok's PascalCase `hook_event_name` wins over its snake_case alias.
    private static func eventName(in payload: [String: Any], fallback: String?) -> String {
        let names = ["hook_event_name", "event", "hookEventName", "hook_event"]
        for name in names {
            if let value = payload[name] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return fallback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func status(for event: String, payload: [String: Any], source: String) -> String {
        switch source {
        case "copilot": return copilotStatus(event, payload: payload)
        case "opencode": return opencodeStatus(event, payload: payload)
        case "grok-bot":
            if let native = grokNative(event, payload: payload) {
                return native
            }
            return cursorFamilyStatus(event, payload: payload, source: "cursor")
        default: return cursorFamilyStatus(event, payload: payload, source: source)
        }
    }

    /// GitHub Copilot CLI events. Unknown names are ignored. Session end closes the slot.
    private static func copilotStatus(_ event: String, payload: [String: Any]) -> String {
        switch event {
        case "sessionStart", "SessionStart",
             "userPromptSubmitted", "UserPromptSubmit",
             "preToolUse", "PreToolUse",
             "postToolUse", "PostToolUse",
             "subagentStart", "SubagentStart",
             "postToolUseFailure", "PostToolUseFailure":
            return "running"
        case "permissionRequest", "PermissionRequest":
            return "wait"
        case "notification", "Notification":
            let kind = token(payload, keys: ["notification_type", "notificationType", "type"])
            return kind == "permission_prompt" || kind == "elicitation_dialog" ? "wait" : ""
        case "errorOccurred", "ErrorOccurred":
            let context = token(payload, keys: ["errorContext", "error_context"])
            if context == "model_call" { return "fail" }
            if context == "tool_execution" { return "running" }
            return ""
        case "agentStop", "Stop":
            return "done"
        case "sessionEnd", "SessionEnd":
            return "closed"
        default:
            return ""
        }
    }

    /// OpenCode plugin events. Status type is read; retry text and question text are not.
    private static func opencodeStatus(_ event: String, payload: [String: Any]) -> String {
        switch event {
        case "session.status":
            switch token(payload, keys: ["status_type", "type"]) {
            case "busy", "retry": return "running"
            case "idle": return "done"
            default:
                if let status = payload["status"] as? [String: Any] {
                    switch string(status["type"]) {
                    case "busy", "retry": return "running"
                    case "idle": return "done"
                    default: return ""
                    }
                }
                return ""
            }
        case "tool.execute.before", "permission.replied", "question.replied", "question.rejected":
            return "running"
        case "permission.asked", "question.asked":
            return "wait"
        case "session.idle":
            return "done"
        case "session.error":
            return "fail"
        default:
            return ""
        }
    }

    /// xAI grok events. Nil means this is not one of those names, so a Cursor hook Grok imported can
    /// still update the same session. An empty string ignores the event. `idle_prompt` stays empty
    /// so it cannot cover a finished or failed turn. PascalCase `Stop` is the turn end, not Cursor's heartbeat.
    private static func grokNative(_ event: String, payload: [String: Any]) -> String? {
        switch event {
        case "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "SubagentStart",
             "PermissionDenied", "PostToolUseFailure":
            return "running"
        case "Notification":
            let kind = token(payload, keys: ["notification_type", "notificationType", "type"])
            return kind == "permission_prompt" ? "wait" : ""
        case "Stop":
            return "done"
        case "StopFailure", "StopCancelled":
            return "fail"
        case "SessionEnd":
            return "closed"
        default:
            return nil
        }
    }

    private static func cursorFamilyStatus(_ event: String, payload: [String: Any], source: String) -> String {
        let name = event.lowercased().replacingOccurrences(of: "_", with: "")
        if name == "stopfailure" { return "fail" }
        if isPermission(event, source: source) {
            return source == "claude" ? "running" : "wait"
        }
        if isChoice(payload: payload), !isFinishedTool(event) { return "wait" }
        switch name {
        case "afteragentthought", "afteragentresponse", "afterfileedit", "stop":
            return "heartbeat"
        case "beforesubmitprompt", "sessionstart", "subagentstart",
             "userpromptsubmit", "pretooluse", "posttooluse", "posttoolusefailure",
             "notification", "beforeshellexecution", "aftershellexecution",
             "beforemcpexecution", "aftermcpexecution":
            return "running"
        case "sessionend", "subagentstop":
            return failed(payload) ? "fail" : "done"
        default:
            return ""
        }
    }

    /// A category for the bubble. The payload's prompt and command are never copied.
    private static func safeDetail(for event: String, source: String) -> String {
        switch event {
        case "beforeSubmitPrompt", "UserPromptSubmit", "userPromptSubmitted":
            return "Chat"
        case "beforeShellExecution":
            return "Shell"
        case "beforeMCPExecution":
            return "MCP"
        case "PermissionRequest", "permission_request", "permissionRequest", "permission.asked":
            return source == "cursor" || source == "codex" || source == "claude" ? "Permission" : ""
        default:
            return ""
        }
    }

    private static func isPermission(_ event: String, source: String) -> Bool {
        guard source == "cursor" || source == "codex" || source == "claude" else { return false }
        switch event {
        case "beforeShellExecution", "beforeMCPExecution", "PermissionRequest", "permission_request":
            return true
        default:
            return false
        }
    }

    private static func token(_ payload: [String: Any], keys: [String]) -> String {
        for key in keys {
            let value = string(payload[key])
            if !value.isEmpty { return value }
        }
        return ""
    }

    private static func isFinishedTool(_ event: String) -> Bool {
        let name = event.lowercased().replacingOccurrences(of: "_", with: "")
        return ["posttooluse", "posttoolusefailure", "aftershellexecution", "aftermcpexecution"].contains(name)
    }

    private static func isChoice(payload: [String: Any]) -> Bool {
        let tool = toolName(payload)
        return tool == "AskQuestion" || tool == "CreatePlan" || tool == "SwitchMode"
    }

    private static func failed(_ payload: [String: Any]) -> Bool {
        if payload["error"] != nil { return true }
        let status = (payload["status"] as? String ?? payload["result"] as? String ?? "").lowercased()
        return ["error", "failed", "fail", "aborted", "cancelled", "canceled"].contains(status)
    }

    private static func toolName(_ payload: [String: Any]) -> String {
        for key in ["tool_name", "toolName", "tool"] {
            if let value = payload[key] as? String, !value.isEmpty { return value }
        }
        return ""
    }

    private static func choiceOptions(payload: [String: Any], event: String) -> (kind: String, questionID: String, options: [[String: String]]) {
        guard !isFinishedTool(event) else { return ("", "", []) }
        switch toolName(payload) {
        case "CreatePlan":
            return ("plan", "", [["id": "approve", "label": "Approve"], ["id": "keep", "label": "Keep planning"]])
        case "SwitchMode":
            return ("mode", "", [["id": "allow", "label": "Allow switch"], ["id": "stay", "label": "Stay"]])
        case "AskQuestion":
            let input = dictionary(payload, keys: ["tool_input", "input", "arguments", "args"])
            let questions = input["questions"] as? [Any] ?? []
            let first = questions.first as? [String: Any] ?? [:]
            let questionID = string(first["id"])
            return ("choice", questionID, optionList(first["options"] ?? input["options"]))
        default:
            return ("", "", [])
        }
    }

    private static func optionList(_ raw: Any?) -> [[String: String]] {
        guard let list = raw as? [Any] else { return [] }
        var options: [[String: String]] = []
        for item in list {
            guard let dict = item as? [String: Any] else { continue }
            var id = string(dict["id"]).isEmpty ? string(dict["value"]) : string(dict["id"])
            let label = string(dict["label"]).isEmpty ? string(dict["title"]) : string(dict["label"])
            if id.isEmpty { id = String(label.prefix(40)) }
            if id.isEmpty || label.isEmpty { continue }
            options.append(["id": String(id.prefix(80)), "label": String(label.prefix(160))])
        }
        return options
    }

    private static func requestID(in payload: [String: Any]) -> String {
        for key in ["generation_id", "tool_use_id", "request_id"] {
            let value = string(payload[key])
            if !value.isEmpty && value != "nil" { return value }
        }
        return String(DispatchTime.now().uptimeNanoseconds)
    }

    /// Uses id fields already in the JSON. A transcript path contributes only its file stem.
    /// The file itself is never opened.
    private static func sessionID(in payload: [String: Any], source: String) -> String {
        for key in ["conversation_id", "session_id", "sessionId", "sessionID", "subagent_id", "composer_id", "thread_id"] {
            let value = string(payload[key])
            if !value.isEmpty { return bareID(value) }
        }
        if let nested = payload["session"] as? [String: Any] {
            let value = string(nested["id"])
            if !value.isEmpty { return bareID(value) }
        }
        if let path = payload["transcript_path"] as? String, !path.isEmpty {
            let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            if !stem.isEmpty { return bareID(stem) }
        }
        return "\(source)-session"
    }

    private static func bareID(_ value: String) -> String {
        let pattern = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
        if let range = value.range(of: pattern, options: .regularExpression) {
            return String(value[range]).lowercased()
        }
        return String(value.prefix(80))
    }

    private static func find(_ tasks: [String: Any], id: String) -> (String, [String: Any]) {
        if let item = tasks[id] as? [String: Any] { return (id, item) }
        for (key, raw) in tasks {
            guard let item = raw as? [String: Any] else { continue }
            if item["id"] as? String == id { return (key, item) }
            let aliases = item["aliases"] as? [String] ?? []
            if aliases.contains(id) { return (key, item) }
        }
        return (id, [:])
    }

    private static func readRoot(_ url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return root
    }

    private static func stringOptions(_ value: Any?) -> [[String: String]] {
        if let typed = value as? [[String: String]] { return typed }
        guard let rows = value as? [[String: Any]] else { return [] }
        return rows.compactMap { item in
            let label = string(item["label"])
            guard !label.isEmpty else { return nil }
            return ["id": string(item["id"]), "label": label]
        }
    }

    private static func dictionary(_ payload: [String: Any], keys: [String]) -> [String: Any] {
        for key in keys {
            if let value = payload[key] as? [String: Any] { return value }
        }
        return [:]
    }

    private static func string(_ value: Any?) -> String {
        guard let text = value as? String else { return "" }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "nil" ? "" : trimmed
    }
}
