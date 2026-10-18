import AppKit
import Foundation
import MochiCore

@MainActor
final class AppSession {
    private let petStore: PetStore
    private let prefsStore: PrefsStore
    private var pet: PetState
    private var prefs: IslandPrefs
    private var tracker = TaskTransitionTracker()

    init() {
        petStore = PetStore.live()
        prefsStore = PrefsStore.live()
        pet = petStore.load(migrating: Self.legacyFiles("src/pet_state.json"))
        prefs = prefsStore.load(migrating: Self.legacyFiles("island_offset.json"))
    }

    var currentPrefs: IslandPrefs { prefs }

    func replacePrefs(_ json: [String: Any]) {
        prefs = IslandPrefs.parse(json, base: prefs)
        prefsStore.save(prefs)
    }

    func statePayload() -> [String: Any] {
        let now = Date().timeIntervalSince1970
        let before = pet
        PetEngine.tick(&pet, now: now)
        let tasks = visibleTasks(now: now)
        for id in tracker.newlyCompleted(tasks) {
            _ = PetEngine.feedFromAI(&pet, taskID: id, now: now)
        }
        if pet != before {
            petStore.save(pet)
        }
        return PetEngine.snapshot(pet, now: now)
    }

    func play() -> [String: Any] {
        PetEngine.play(&pet, now: Date().timeIntervalSince1970)
        petStore.save(pet)
        return PetEngine.snapshot(pet, now: Date().timeIntervalSince1970)
    }

    func tasksPayload() -> [[String: Any]] {
        visibleTasks(now: Date().timeIntervalSince1970).map(\.dictionary)
    }

    func linkPayload(action: String, acknowledged: Bool) -> [String: Any] {
        let binary = hookBinary()
        let result: HookInstallResult
        if action == "disconnect" {
            result = HookInstaller.remove(hooksURL: hooksURL, binaryURL: binary, tasksURL: tasksURL)
        } else if action == "connect" {
            if !prefs.cursorPrivacyAccepted && !acknowledged {
                var payload = HookInstallResult(connected: false, hook: binary.path, needsPrivacy: true).dictionary
                payload["scanTranscripts"] = prefs.scanTranscripts
                return payload
            }
            prefs.cursorPrivacyAccepted = true
            prefsStore.save(prefs)
            result = HookInstaller.install(
                hooksURL: hooksURL,
                binaryURL: binary,
                tasksURL: tasksURL,
                privacyAccepted: true
            )
        } else {
            result = HookInstaller.status(hooksURL: hooksURL, binaryURL: binary, tasksURL: tasksURL)
        }
        var payload = result.dictionary
        payload["scanTranscripts"] = prefs.scanTranscripts
        return payload
    }

    func choicePayload(_ body: [String: Any]) -> [String: Any] {
        let kind = body["kind"] as? String ?? ""
        let action = ((body["action"] as? String) ?? (body["option_id"] as? String) ?? "").lowercased()
        if kind != "permission" || action == "open" {
            openCursor()
            return ["ok": true, "opened": true]
        }
        let id = body["id"] as? String ?? ""
        let requestID = body["request_id"] as? String ?? ""
        do {
            try ReplyWriter.writePermission(id: id, requestID: requestID, action: action, to: replyURL)
            return ["ok": true]
        } catch {
            return ["ok": false, "error": "Could not save the reply. Choose it in Cursor."]
        }
    }

    func setScanTranscripts(_ enabled: Bool) {
        prefs.scanTranscripts = enabled
        prefsStore.save(prefs)
    }

    private func visibleTasks(now: Double) -> [CursorTask] {
        var tasks = TaskReader.load(tasksURL: tasksURL, now: now, includePrompts: true)
        guard prefs.scanTranscripts else { return tasks }
        let known = Set(tasks.map(\.id))
        for hint in TaskReader.transcriptHints(now: now) where !known.contains(hint.id) {
            tasks.append(hint)
        }
        return tasks.sorted { $0.id < $1.id }
    }

    private func openCursor() {
        let url = URL(fileURLWithPath: "/Applications/Cursor.app")
        NSWorkspace.shared.open(url)
    }

    private func hookBinary() -> URL {
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "MochiHookCLI") {
            return bundled
        }
        return Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/MochiHookCLI")
    }

    private var tasksURL: URL {
        AppConfig.cursorDirectory.appendingPathComponent("mochi-island-tasks.json")
    }

    private var replyURL: URL {
        AppConfig.cursorDirectory.appendingPathComponent("mochi-island-reply.json")
    }

    private var hooksURL: URL {
        AppConfig.cursorDirectory.appendingPathComponent("hooks.json")
    }

    private static func legacyFiles(_ relative: String) -> [URL] {
        var urls: [URL] = []
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        urls.append(cwd.appendingPathComponent(relative))
        let bundleParent = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        urls.append(bundleParent.appendingPathComponent(relative))
        return urls
    }
}
