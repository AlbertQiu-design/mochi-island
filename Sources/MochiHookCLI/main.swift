import Darwin
import Foundation
import MochiCore

let stateURL = AppConfig.cursorDirectory.appendingPathComponent("mochi-island-tasks.json")
let replyURL = AppConfig.cursorDirectory.appendingPathComponent("mochi-island-reply.json")
let permissionTimeout: TimeInterval = 280

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

func argumentValue(_ name: String) -> String? {
    let args = Array(CommandLine.arguments.dropFirst())
    var index = 0
    while index < args.count {
        if args[index] == name, index + 1 < args.count {
            return args[index + 1]
        }
        index += 1
    }
    return nil
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

func readReply() -> [String: Any] {
    guard let data = try? Data(contentsOf: replyURL),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return [:]
    }
    return json
}

func waitPermission(itemID: String, requestID: String) -> String {
    let deadline = Date().timeIntervalSince1970 + permissionTimeout
    while Date().timeIntervalSince1970 < deadline {
        let data = readReply()
        let action = (data["action"] as? String ?? "").lowercased()
        let rid = data["request_id"] as? String ?? ""
        let tid = data["id"] as? String ?? ""
        if !requestID.isEmpty, rid == requestID, action == "allow" || action == "deny" {
            return action
        }
        if requestID.isEmpty, tid == itemID, action == "allow" || action == "deny" {
            return action
        }
        Thread.sleep(forTimeInterval: 0.2)
    }
    return "allow"
}

func run() {
    let payload = readStdin()
    let outcome = HookEvents.interpret(
        sourceFlag: argumentValue("--source"),
        payload: payload,
        environment: ProcessInfo.processInfo.environment,
        eventFlag: argumentValue("--event")
    )
    if let outcome {
        withLock {
            HookEvents.commit(outcome, tasksURL: stateURL)
        }
        if outcome.waitsForPermission {
            let action = waitPermission(itemID: outcome.id, requestID: outcome.requestID)
            emit(HookEvents.permissionStdout(style: outcome.permissionStyle, action: action))
            return
        }
    }
    emit([:] as [String: Any])
}

run()
exit(0)
