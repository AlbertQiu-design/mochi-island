import AppKit
import Foundation
import MochiCore

@MainActor
final class AppSession {
    private let petStore: PetStore
    private let prefsStore: PrefsStore
    private let slotDisk: DialogueSlotDisk
    private var pet: PetState
    private var prefs: IslandPrefs
    private var slots: DialogueSlotStore
    private var tracker = TaskTransitionTracker()
    private var knownWaitIDs: Set<String> = []
    private var waitsPrimed = false

    init() {
        petStore = PetStore.live()
        prefsStore = PrefsStore.live()
        slotDisk = DialogueSlotDisk.live()
        pet = petStore.load(migrating: Self.legacyFiles("src/pet_state.json"))
        prefs = prefsStore.load(migrating: Self.legacyFiles("island_offset.json"))
        slots = slotDisk.load()
    }

    var currentPrefs: IslandPrefs { prefs }

    func replacePrefs(_ json: [String: Any]) {
        prefs = IslandPrefs.parse(json, base: prefs)
        prefsStore.save(prefs)
        if let selected = json["selected"] as? String, slots.slots.contains(where: { $0.id == selected }) {
            slots.selected = selected
            slotDisk.save(slots)
        }
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
        absorbTasks(tasks)
        var payload = PetEngine.snapshot(pet, now: now)
        payload["slots"] = slots.slots.map(\.dictionary)
        payload["selected"] = slots.selected
        payload["dock"] = prefs.dock
        return payload
    }

    func play() -> [String: Any] {
        PetEngine.play(&pet, now: Date().timeIntervalSince1970)
        petStore.save(pet)
        return PetEngine.snapshot(pet, now: Date().timeIntervalSince1970)
    }

    func tasksPayload() -> [[String: Any]] {
        let tasks = visibleTasks(now: Date().timeIntervalSince1970)
        absorbTasks(tasks)
        return tasks.map(\.dictionary)
    }

    func createSlot(source: String) -> [String: Any] {
        var rng = SystemRandomNumberGenerator()
        let (next, slot) = slots.created(source: source, now: Date().timeIntervalSince1970, rng: &rng)
        slots = next
        slotDisk.save(slots)
        return [
            "ok": true,
            "slot": slot.dictionary,
            "slots": slots.slots.map(\.dictionary),
            "selected": slots.selected
        ]
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
        let action = (body["option_id"] as? String) ?? ""
        let id = body["id"] as? String ?? ""
        let requestID = body["request_id"] as? String ?? ""
        do {
            try ReplyWriter.writeChoice(id: id, requestID: requestID, action: action, kind: kind, to: replyURL)
            return ["ok": true]
        } catch {
            return ["ok": false, "error": "Could not save the reply. Choose it in Cursor."]
        }
    }

    func openAgent(source: String, taskID: String) -> [String: Any] {
        let plan = AgentLaunch.plan(source: source)
        let normalized = AgentLaunch.normalize(source)
        if normalized == "mochi" {
            return ["ok": true, "opened": false, "source": normalized, "id": taskID]
        }
        if let path = plan.appPath {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            return ["ok": true, "opened": true, "source": normalized, "app": path, "id": taskID]
        }
        if let raw = plan.url, let url = URL(string: raw) {
            NSWorkspace.shared.open(url)
            var payload: [String: Any] = [
                "ok": true,
                "opened": true,
                "source": normalized,
                "url": raw,
                "id": taskID
            ]
            if let note = plan.note {
                payload["note"] = note
            }
            return payload
        }
        return ["ok": false, "source": normalized, "id": taskID, "error": plan.note ?? "Could not open that agent."]
    }

    func setScanTranscripts(_ enabled: Bool) {
        prefs.scanTranscripts = enabled
        prefsStore.save(prefs)
    }

    private func absorbTasks(_ tasks: [CursorTask]) {
        let next = slots.selectingNewWaits(in: tasks, known: &knownWaitIDs, primed: &waitsPrimed)
        guard next != slots else { return }
        slots = next
        slotDisk.save(slots)
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
