import Foundation

public struct CursorTask: Equatable {
    public var id: String
    public var title: String
    public var status: String
    public var kind: String
    public var prompt: String
    public var detail: String
    public var options: [[String: String]]
    public var allowMultiple: Bool
    public var questionID: String
    public var requestID: String
    public var updated: Double

    public init(
        id: String,
        title: String,
        status: String,
        kind: String = "",
        prompt: String = "",
        detail: String = "",
        options: [[String: String]] = [],
        allowMultiple: Bool = false,
        questionID: String = "",
        requestID: String = "",
        updated: Double = 0
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.kind = kind
        self.prompt = prompt
        self.detail = detail
        self.options = options
        self.allowMultiple = allowMultiple
        self.questionID = questionID
        self.requestID = requestID
        self.updated = updated
    }

    public var dictionary: [String: Any] {
        [
            "id": id,
            "title": title,
            "status": status,
            "kind": kind,
            "prompt": prompt,
            "detail": detail,
            "options": options,
            "allow_multiple": allowMultiple,
            "question_id": questionID,
            "request_id": requestID
        ]
    }
}

public struct TaskTransitionTracker: Equatable {
    public var statusByID: [String: String] = [:]

    public init() {}

    public mutating func newlyCompleted(_ tasks: [CursorTask]) -> [String] {
        var feed: [String] = []
        var next: [String: String] = [:]
        for task in tasks {
            next[task.id] = task.status
            if let previous = statusByID[task.id],
               previous == "running" || previous == "wait",
               task.status == "done" {
                feed.append(task.id)
            }
        }
        statusByID = next
        return feed
    }
}

public enum TaskReader {
    public static func load(tasksURL: URL, now: Double = Date().timeIntervalSince1970, includePrompts: Bool = true) -> [CursorTask] {
        guard let data = try? Data(contentsOf: tasksURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tasks = root["tasks"] as? [String: Any] else {
            return []
        }
        var visible: [CursorTask] = []
        for (key, raw) in tasks {
            guard let item = raw as? [String: Any] else { continue }
            var status = item["status"] as? String ?? "running"
            if !["running", "wait", "done", "fail"].contains(status) {
                status = "running"
            }
            let updated = (item["updated"] as? NSNumber)?.doubleValue ?? (item["updated"] as? Double) ?? 0
            if status == "done" || status == "fail" {
                if updated > 0, now - updated > AppConfig.doneKeep { continue }
            } else if updated > 0, now - updated > AppConfig.liveKeep {
                continue
            }
            let id = item["id"] as? String ?? key
            let options = (item["options"] as? [[String: Any]] ?? []).compactMap { option -> [String: String]? in
                let oid = (option["id"] as? String) ?? ""
                let label = (option["label"] as? String) ?? ""
                guard !label.isEmpty else { return nil }
                return ["id": oid, "label": label]
            }
            visible.append(CursorTask(
                id: id,
                title: item["title"] as? String ?? "Cursor task",
                status: status,
                kind: includePrompts ? (item["kind"] as? String ?? "") : "",
                prompt: includePrompts ? (item["prompt"] as? String ?? "") : "",
                detail: includePrompts ? (item["detail"] as? String ?? "") : "",
                options: options,
                allowMultiple: item["allow_multiple"] as? Bool ?? false,
                questionID: item["question_id"] as? String ?? "",
                requestID: item["request_id"] as? String ?? "",
                updated: updated
            ))
        }
        return visible.sorted { $0.id < $1.id }
    }

    public static func transcriptHints(now: Double = Date().timeIntervalSince1970) -> [CursorTask] {
        let root = AppConfig.cursorDirectory.appendingPathComponent("projects", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var hints: [CursorTask] = []
        for case let url as URL in enumerator {
            if hints.count >= 20 { break }
            guard url.pathExtension == "jsonl", url.path.contains("agent-transcripts") else { continue }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate?.timeIntervalSince1970 ?? 0
            guard modified > 0, now - modified <= AppConfig.liveKeep else { continue }
            let id = url.deletingPathExtension().lastPathComponent
            hints.append(CursorTask(id: id, title: "Cursor task", status: "running", updated: modified))
        }
        return hints
    }
}

public enum ReplyWriter {
    public static func writePermission(id: String, requestID: String, action: String, to url: URL) throws {
        let allowed = action.lowercased()
        guard allowed == "allow" || allowed == "deny" else {
            throw ReplyError.unsupported
        }
        let payload: [String: Any] = [
            "id": id,
            "request_id": requestID,
            "action": allowed,
            "kind": "permission"
        ]
        try AtomicFile.writeJSON(payload, to: url)
    }

    public enum ReplyError: Error {
        case unsupported
    }
}
