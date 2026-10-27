import Darwin
import Foundation

let stateURL = AppPaths.cursor.appendingPathComponent("mochi-island-tasks.json")
let replyURL = AppPaths.cursor.appendingPathComponent("mochi-island-reply.json")
let permissionTimeout: TimeInterval = 280

enum AppPaths {
    static var homeDirectory: URL {
        #if os(macOS)
        FileManager.default.homeDirectoryForCurrentUser
        #else
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        #endif
    }

    static var cursor: URL {
        homeDirectory.appendingPathComponent(".cursor", isDirectory: true)
    }
}

let startEvents: Set<String> = ["beforeSubmitPrompt", "sessionStart", "subagentStart"]
let toolEvents: Set<String> = [
    "preToolUse", "postToolUse", "postToolUseFailure",
    "beforeShellExecution", "afterShellExecution",
    "beforeMCPExecution", "afterMCPExecution", "afterAgentThought"
]
let doneEvents: Set<String> = ["sessionEnd", "subagentStop"]
let waitTools = ["AskQuestion": "choice", "CreatePlan": "plan", "SwitchMode": "mode"]
let permissionEvents: Set<String> = ["beforeShellExecution", "beforeMCPExecution"]
let heartbeatEvents: Set<String> = ["afterAgentThought", "afterAgentResponse", "afterFileEdit", "stop"]
let finishedTools: Set<String> = ["postToolUse", "postToolUseFailure", "afterShellExecution", "afterMCPExecution"]

func emit(_ object: Any) {
    let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

func readStdin() -> [String: Any] {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard !data.isEmpty,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return [:]
    }
    return json
}

func walk(_ value: Any, depth: Int = 0, visit: (String, Any) -> Void) {
    if depth > 6 { return }
    if let dict = value as? [String: Any] {
        for (key, item) in dict {
            visit(key, item)
            walk(item, depth: depth + 1, visit: visit)
        }
    } else if let list = value as? [Any] {
        for item in list.prefix(12) {
            walk(item, depth: depth + 1, visit: visit)
        }
    }
}

func firstText(_ payload: [String: Any], names: Set<String>) -> String {
    var found = ""
    walk(payload) { key, item in
        if found.isEmpty, names.contains(key), let text = item as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            found = text
        }
    }
    return found
}

func clean(_ raw: String) -> String {
    var text = raw
    if let range = text.range(of: "<user_query>\\s*(.*?)\\s*</user_query>", options: .regularExpression) {
        let matched = String(text[range])
        text = matched
            .replacingOccurrences(of: "<user_query>", with: "")
            .replacingOccurrences(of: "</user_query>", with: "")
    }
    text = text.replacingOccurrences(of: "\\n", with: " ")
    text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    return text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

func bareID(_ value: String) -> String {
    let pattern = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
    if let range = value.range(of: pattern, options: .regularExpression) {
        return String(value[range]).lowercased()
    }
    return String(value.prefix(80))
}

func taskID(_ payload: [String: Any]) -> String {
    if let path = payload["transcript_path"] as? String, !path.isEmpty {
        let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        if !stem.isEmpty { return bareID(stem) }
    }
    for name in ["conversation_id", "subagent_id", "session_id", "composer_id"] {
        if let value = payload[name] as? String, !value.isEmpty { return bareID(value) }
    }
    let nested = firstText(payload, names: ["conversation_id", "subagent_id", "session_id"])
    if !nested.isEmpty { return bareID(nested) }
    return "cursor-task"
}

func aliases(_ payload: [String: Any], itemID: String) -> [String] {
    var names: Set<String> = [itemID]
    for key in ["conversation_id", "session_id", "subagent_id", "composer_id"] {
        if let value = payload[key] as? String, !value.isEmpty {
            names.insert(bareID(value))
            names.insert(String(value.prefix(80)))
        }
    }
    if let path = payload["transcript_path"] as? String, !path.isEmpty {
        names.insert(bareID(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent))
    }
    return names.filter { !$0.isEmpty }.sorted()
}

func toolName(_ payload: [String: Any]) -> String {
    for name in ["tool_name", "toolName", "tool", "name"] {
        if let value = payload[name] as? String, !value.isEmpty { return value }
    }
    return firstText(payload, names: ["tool_name", "toolName"])
}

func dictAt(_ payload: [String: Any], names: Set<String>) -> [String: Any] {
    for name in names {
        if let value = payload[name] as? [String: Any] { return value }
    }
    var found: [String: Any] = [:]
    walk(payload) { key, item in
        if found.isEmpty, names.contains(key), let dict = item as? [String: Any] {
            found = dict
        }
    }
    return found
}

func isFail(_ payload: [String: Any]) -> Bool {
    if payload["error"] != nil || payload["aborted"] != nil || payload["cancelled"] != nil || payload["canceled"] != nil {
        return true
    }
    let status = firstText(payload, names: ["status", "result", "outcome"]).lowercased()
    return ["error", "failed", "fail", "aborted", "cancelled", "canceled"].contains(status)
}

func optionList(_ raw: Any?) -> [[String: String]] {
    guard let list = raw as? [Any] else { return [] }
    var options: [[String: String]] = []
    for item in list {
        guard let dict = item as? [String: Any] else { continue }
        var id = String(describing: dict["id"] ?? dict["value"] ?? "").trimmingCharacters(in: .whitespaces)
        let label = String(describing: dict["label"] ?? dict["title"] ?? dict["text"] ?? id).trimmingCharacters(in: .whitespaces)
        if id.isEmpty || id == "nil" { id = String(label.prefix(40)) }
        if id.isEmpty { id = "opt-\(options.count)" }
        if !label.isEmpty && label != "nil" {
            options.append(["id": String(id.prefix(80)), "label": String(label.prefix(160))])
        }
    }
    return options
}

func extraFromTool(_ name: String, payload: [String: Any]) -> [String: Any] {
    let data = dictAt(payload, names: ["tool_input", "input", "arguments", "args", "params"])
    var extra: [String: Any] = [
        "kind": waitTools[name] ?? "",
        "prompt": "",
        "detail": "",
        "options": [] as [[String: String]],
        "allow_multiple": false
    ]
    if name == "AskQuestion" {
        let questions = data["questions"] as? [Any] ?? []
        let first = questions.first as? [String: Any] ?? [:]
        extra["options"] = optionList(first["options"] ?? data["options"])
        extra["allow_multiple"] = first["allow_multiple"] as? Bool ?? false
        extra["question_id"] = String(describing: first["id"] ?? "")
    } else if name == "CreatePlan" {
        extra["options"] = [["id": "approve", "label": "Approve"], ["id": "keep", "label": "Keep planning"]]
    } else if name == "SwitchMode" {
        extra["options"] = [["id": "allow", "label": "Allow switch"], ["id": "stay", "label": "Stay"]]
    }
    return extra
}

func extraFromPermission(_ event: String) -> [String: Any] {
    let shell = event.contains("Shell") || event == "beforeShellExecution"
    return [
        "kind": "permission",
        "prompt": "",
        "detail": "",
        "options": [
            ["id": "allow", "label": "Allow"],
            ["id": "deny", "label": "Deny"]
        ],
        "allow_multiple": false,
        "permission_prompt": shell ? "Allow this command?" : "Allow this MCP call?"
    ]
}

func loadTasks() -> [String: Any] {
    guard let data = try? Data(contentsOf: stateURL),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let tasks = root["tasks"] as? [String: Any] else {
        return [:]
    }
    return tasks
}

func saveTasks(_ tasks: [String: Any]) {
    let payload: [String: Any] = ["tasks": tasks]
    guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
    try? AtomicJSON.write(data, to: stateURL)
}

enum AtomicJSON {
    static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temp = url.appendingPathExtension("tmp")
        try data.write(to: temp)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: url)
        }
    }
}

func withLock(_ body: () -> Void) {
    try? FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let lockURL = stateURL.appendingPathExtension("lock")
    let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
    if fd >= 0 {
        flock(fd, LOCK_EX)
        body()
        flock(fd, LOCK_UN)
        close(fd)
    } else {
        body()
    }
}

func findExisting(_ tasks: [String: Any], itemID: String, aliases: [String]) -> (String, [String: Any]) {
    let names = Set(aliases + [itemID])
    for (key, raw) in tasks {
        guard let item = raw as? [String: Any] else { continue }
        var itemNames: Set<String> = [key, item["id"] as? String ?? ""]
        for alias in item["aliases"] as? [String] ?? [] { itemNames.insert(alias) }
        if !names.intersection(itemNames).isEmpty {
            return (key, item)
        }
    }
    return (itemID, [:])
}

func upsert(_ tasks: inout [String: Any], itemID: String, title: String, status: String, aliases: [String], extra: [String: Any], requestID: String) {
    let (oldKey, previous) = findExisting(tasks, itemID: itemID, aliases: aliases)
    var merged = Set(aliases)
    for alias in previous["aliases"] as? [String] ?? [] { merged.insert(alias) }
    merged.insert(itemID)
    merged.insert(oldKey)
    if oldKey != itemID { tasks.removeValue(forKey: oldKey) }
    var nextStatus = status
    var nextTitle = title
    var nextExtra = extra
    var nextRequest = requestID
    if status == "heartbeat" {
        nextStatus = previous["status"] as? String ?? "running"
        nextTitle = title.isEmpty ? (previous["title"] as? String ?? "") : title
        nextExtra = [
            "kind": previous["kind"] as? String ?? "",
            "options": previous["options"] as? [[String: String]] ?? [],
            "allow_multiple": previous["allow_multiple"] as? Bool ?? false,
            "question_id": previous["question_id"] as? String ?? ""
        ]
        nextRequest = previous["request_id"] as? String ?? ""
    } else if status != "wait" {
        nextRequest = ""
    }
    let permissionPrompt = nextExtra["permission_prompt"] as? String ?? ""
    tasks[itemID] = [
        "id": itemID,
        "title": nextTitle.isEmpty ? (previous["title"] as? String ?? "Cursor task") : nextTitle,
        "status": nextStatus,
        "updated": Date().timeIntervalSince1970,
        "aliases": merged.filter { !$0.isEmpty }.sorted(),
        "source": "cursor",
        "kind": nextExtra["kind"] as? String ?? "",
        "prompt": permissionPrompt,
        "detail": "",
        "options": nextExtra["options"] as? [[String: String]] ?? [],
        "allow_multiple": nextExtra["allow_multiple"] as? Bool ?? false,
        "question_id": nextExtra["question_id"] as? String ?? "",
        "request_id": nextRequest
    ]
}

func nextStatus(_ event: String, payload: [String: Any], name: String) -> String {
    if permissionEvents.contains(event) { return "wait" }
    if waitTools[name] != nil && !finishedTools.contains(event) { return "wait" }
    if heartbeatEvents.contains(event) { return "heartbeat" }
    if startEvents.contains(event) || toolEvents.contains(event) { return "running" }
    if doneEvents.contains(event) { return isFail(payload) ? "fail" : "done" }
    return ""
}

func readReply() -> [String: Any] {
    guard let data = try? Data(contentsOf: replyURL),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return [:]
    }
    return json
}

func waitPermission(itemID: String, requestID: String, aliases: [String]) -> String {
    let deadline = Date().timeIntervalSince1970 + permissionTimeout
    let names = Set(aliases + [itemID])
    while Date().timeIntervalSince1970 < deadline {
        let data = readReply()
        let action = (data["action"] as? String ?? "").lowercased()
        let rid = data["request_id"] as? String ?? ""
        let tid = data["id"] as? String ?? ""
        if !requestID.isEmpty, rid == requestID, action == "allow" || action == "deny" {
            return action
        }
        if requestID.isEmpty, names.contains(tid), action == "allow" || action == "deny" {
            return action
        }
        Thread.sleep(forTimeInterval: 0.2)
    }
    return "allow"
}

func run() {
    let payload = readStdin()
    var event = payload["hook_event_name"] as? String ?? payload["event"] as? String ?? ""
    if event.isEmpty { event = ProcessInfo.processInfo.environment["CURSOR_HOOK_EVENT"] ?? "" }
    let itemID = taskID(payload)
    let names = aliases(payload, itemID: itemID)
    let name = toolName(payload)
    var extra: [String: Any] = [:]
    var requestID = ""
    var title = ""
    if event == "beforeSubmitPrompt" || event == "sessionStart" {
        title = clean(firstText(payload, names: ["prompt", "text", "user_prompt", "prompt_text", "message", "description", "content"]))
    }
    if waitTools[name] != nil {
        extra = extraFromTool(name, payload: payload)
    } else if permissionEvents.contains(event) {
        extra = extraFromPermission(event)
        requestID = String(describing: payload["generation_id"] ?? payload["tool_use_id"] ?? "")
        if requestID.isEmpty || requestID == "nil" {
            requestID = String(DispatchTime.now().uptimeNanoseconds)
        }
    }
    var status = nextStatus(event, payload: payload, name: name)
    if event.isEmpty && !title.isEmpty { status = "running" }
    withLock {
        guard !status.isEmpty else { return }
        var tasks = loadTasks()
        upsert(&tasks, itemID: itemID, title: title, status: status, aliases: names, extra: extra, requestID: requestID)
        saveTasks(tasks)
    }
    if permissionEvents.contains(event) {
        emit(["permission": waitPermission(itemID: itemID, requestID: requestID, aliases: names)])
        return
    }
    if event == "preToolUse" || event == "subagentStart" {
        emit(["permission": "allow"])
        return
    }
    emit([:] as [String: Any])
}

run()
exit(0)
