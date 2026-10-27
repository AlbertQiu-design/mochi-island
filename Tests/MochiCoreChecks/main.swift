import Foundation
import MochiCore

func check(_ condition: @autoclosure () -> Bool, _ name: String = #function, line: Int = #line) {
    if !condition() {
        fputs("FAIL \(name):\(line)\n", stderr)
        exit(1)
    }
}

func PlayReducesEnergy() {
        var state = PetState(hunger: 10, energy: 50, happiness: 40, lastDecayTs: 1_000_000)
        PetEngine.play(&state, now: 1_000_000)
        check(state.energy == 50 + PetRules.playEnergy)
        check(state.lastAction == "play")
    }

func DecayPutsThePetToSleepWithoutDeath() {
        var state = PetState(hunger: 94, energy: 50, happiness: 40, lastDecayTs: 0)
        PetEngine.tick(&state, now: PetRules.decayInterval)
        check(state.asleep)
        check(state.hunger >= PetRules.asleepHunger)
        let frozen = state
        PetEngine.tick(&state, now: PetRules.decayInterval * 4)
        check(state.hunger == frozen.hunger)
        check(state.energy == frozen.energy)
    }

func PlayDoesNothingWhileAsleep() {
        var state = PetState(energy: 40, asleep: true, lastDecayTs: 10)
        PetEngine.play(&state, now: 10)
        check(state.energy == 40)
        check(state.asleep)
        check(state.lastAction != "play")
    }

func FeedFromAIWakesAndDedupes() {
        var state = PetState(hunger: 90, energy: 0, happiness: 20, asleep: true, lastDecayTs: 50)
        check(PetEngine.feedFromAI(&state, taskID: "task-a", now: 50))
        check(!state.asleep)
        check(state.hunger < 90)
        let after = state
        check(!PetEngine.feedFromAI(&state, taskID: "task-a", now: 50))
        check(state == after)
    }

func FedTaskIDsStayBounded() {
        var state = PetState(lastDecayTs: 10)
        for index in 0..<(AppConfig.fedTaskLimit + 5) {
            _ = PetEngine.feedFromAI(&state, taskID: "id-\(index)", now: 10)
        }
        check(state.fedTaskIDs.count == AppConfig.fedTaskLimit)
        check(!state.fedTaskIDs.contains("id-0"))
        check(state.fedTaskIDs.contains("id-\(AppConfig.fedTaskLimit + 4)"))
    }

func LowHappinessDoesNotSleep() {
        var state = PetState(hunger: 10, energy: 80, happiness: 0, lastDecayTs: 5)
        PetEngine.tick(&state, now: 5)
        check(!state.asleep)
        check(PetEngine.mood(state, now: 5) == "angry")
    }

func MoodsMatchTheOldThresholds() {
        let now = 1_000_000.0
        var happy = PetState(lastDecayTs: now)
        check(PetEngine.mood(happy, now: now) == "happy")

        var playful = PetState(hunger: 30, energy: 50, lastDecayTs: now, lastAction: "play", lastActionTs: now)
        check(PetEngine.mood(playful, now: now) == "playful")

        var sleepy = PetState(hunger: 30, energy: 20, lastDecayTs: now)
        check(PetEngine.mood(sleepy, now: now) == "sleepy")

        var hungry = PetState(hunger: 60, energy: 70, lastDecayTs: now)
        check(PetEngine.mood(hungry, now: now) == "hungry")

        var angry = PetState(hunger: 60, energy: 50, lastDecayTs: now, lastAction: "play", lastActionTs: now)
        check(PetEngine.mood(angry, now: now) == "angry")
        _ = happy
    }

func LegacyDeadSaveBecomesAsleep() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = directory.appendingPathComponent("old.json")
        let raw = #"{"name":"Mochi","hunger":99,"energy":10,"happiness":10,"is_alive":false,"last_decay_ts":1,"last_action":"","last_action_ts":0}"#
        try raw.data(using: .utf8)?.write(to: legacy)
        let store = PetStore(directory: directory.appendingPathComponent("live"))
        let loaded = store.load(migrating: [legacy])
        check(loaded.asleep)
        check(loaded.hunger == 99)
        check(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

func SaveClampsHunger() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = PetStore(directory: directory)
        store.save(PetState(name: "TestCat", hunger: 150))
        let loaded = store.load()
        check(loaded.name == "TestCat")
        check(loaded.hunger == 100)
    }

func OnlyRunningToDoneFeeds() {
        var tracker = TaskTransitionTracker()
        let first = tracker.newlyCompleted([
            CursorTask(id: "a", title: "A", status: "running"),
            CursorTask(id: "b", title: "B", status: "done")
        ])
        check(first.isEmpty)
        let second = tracker.newlyCompleted([
            CursorTask(id: "a", title: "A", status: "done"),
            CursorTask(id: "b", title: "B", status: "done"),
            CursorTask(id: "c", title: "C", status: "fail")
        ])
        check(second == ["a"])
    }

func HookInstallBacksUpAndMarksEntries() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let binary = directory.appendingPathComponent("MochiHookCLI")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        let hooks = directory.appendingPathComponent("hooks.json")
        let raw = #"{"version":1,"hooks":{"sessionStart":[{"command":"/bin/echo keep"}],"stop":[{"command":"/tmp/vibe-island-bridge --source cursor"}]}}"#
        try raw.data(using: .utf8)?.write(to: hooks)
        let tasks = directory.appendingPathComponent("tasks.json")
        let blocked = HookInstaller.install(hooksURL: hooks, binaryURL: binary, tasksURL: tasks, privacyAccepted: false)
        check(blocked.needsPrivacy)
        let installed = HookInstaller.install(hooksURL: hooks, binaryURL: binary, tasksURL: tasks, privacyAccepted: true)
        check(installed.connected)
        check(FileManager.default.fileExists(atPath: hooks.appendingPathExtension("mochi-island.bak").path))
        let data = try Data(contentsOf: hooks)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let table = json?["hooks"] as? [String: Any]
        let entries = table?["sessionStart"] as? [[String: Any]]
        check(entries?.count == 2)
        check(entries?.first?[AppConfig.hookMarker] as? Int == AppConfig.hookVersion)
        check(entries?.last?["command"] as? String == "/bin/echo keep")
        let stop = table?["stop"] as? [[String: Any]]
        check(stop?.count == 2)
        check(stop?.first?[AppConfig.hookMarker] as? Int == AppConfig.hookVersion)
        check((stop?.last?["command"] as? String)?.contains("vibe-island-bridge") == true)
        for name in ["afterAgentResponse", "afterFileEdit"] {
            let list = table?[name] as? [[String: Any]]
            check(list?.first?[AppConfig.hookMarker] as? Int == AppConfig.hookVersion)
        }
        let shell = table?["beforeShellExecution"] as? [[String: Any]]
        check(shell?.first?["timeout"] as? Int == 300)
        let removed = HookInstaller.remove(hooksURL: hooks, binaryURL: binary, tasksURL: tasks)
        check(!removed.connected)
        let after = try JSONSerialization.jsonObject(with: Data(contentsOf: hooks)) as? [String: Any]
        let left = (after?["hooks"] as? [String: Any])?["sessionStart"] as? [[String: Any]]
        check(left?.count == 1)
        check(left?.first?["command"] as? String == "/bin/echo keep")
        let leftStop = (after?["hooks"] as? [String: Any])?["stop"] as? [[String: Any]]
        check(leftStop?.count == 1)
        check((leftStop?.first?["command"] as? String)?.contains("vibe-island-bridge") == true)
    }

func TaskWatchFiresWhenTheFileIsReplaced() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mochi-watch-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("tasks.json")
    let watch = TaskFileWatch(fileURL: file)
    let lock = NSLock()
    var hits = 0
    watch.start {
        lock.lock()
        hits += 1
        lock.unlock()
    }
    func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return hits
    }
    func replace(_ id: String) throws {
        let payload: [String: Any] = [
            "tasks": [id: ["id": id, "status": "running", "updated": Date().timeIntervalSince1970]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let temp = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        try data.write(to: temp)
        if FileManager.default.fileExists(atPath: file.path) {
            _ = try FileManager.default.replaceItemAt(file, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: file)
        }
    }
    func waitForIncrease(from seen: Int) -> Bool {
        var attempts = 0
        let deadline = Date().addingTimeInterval(1.5)
        while count() == seen && Date() < deadline {
            if attempts < 2 {
                try? replace("n-\(seen)-\(attempts)")
                attempts += 1
                Thread.sleep(forTimeInterval: 0.08)
            } else {
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
        return count() > seen
    }
    Thread.sleep(forTimeInterval: 0.15)
    check(waitForIncrease(from: 0))
    check(waitForIncrease(from: count()))
    watch.stop()
}

func ReplyWriterOnlyAllowsPermissionActions() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try ReplyWriter.writePermission(id: "t", requestID: "r", action: "allow", to: url)
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        check(saved?["action"] as? String == "allow")
        check(saved?["kind"] as? String == "permission")
        var threw = false
        do {
            try ReplyWriter.writePermission(id: "t", requestID: "r", action: "approve", to: url)
        } catch {
            threw = true
        }
        check(threw)
        let choiceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try ReplyWriter.writeChoice(id: "t2", requestID: "r2", action: "approve", kind: "plan", to: choiceURL)
        let choice = try JSONSerialization.jsonObject(with: Data(contentsOf: choiceURL)) as? [String: Any]
        check(choice?["action"] as? String == "approve")
        check(choice?["kind"] as? String == "plan")
        check(choice?["option_id"] as? String == "approve")
    }

func TaskReaderKeepsSource() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mochi-src-\(UUID().uuidString).json")
        let now = Date().timeIntervalSince1970
        let payload: [String: Any] = [
            "tasks": [
                "c": ["id": "c", "title": "Cursor", "status": "running", "updated": now, "source": "cursor"],
                "x": ["id": "x", "title": "Codex", "status": "running", "updated": now, "source": "codex"],
                "g": ["id": "g", "title": "Grok", "status": "running", "updated": now, "source": "grok-bot"],
                "z": ["id": "z", "title": "Other", "status": "running", "updated": now, "source": "nope"]
            ]
        ]
        try JSONSerialization.data(withJSONObject: payload).write(to: url)
        let tasks = TaskReader.load(tasksURL: url, now: now)
        let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.source) })
        check(byID["c"] == "cursor")
        check(byID["x"] == "codex")
        check(byID["g"] == "grok-bot")
        check(byID["z"] == "cursor")
        check(tasks.first { $0.id == "x" }?.dictionary["source"] as? String == "codex")
    }

func AgentLaunchFindsInstalledAppsAndCodexFallback() {
        let cursor = AgentLaunch.plan(source: "Cursor") { path in
            path.hasSuffix("/Cursor.app")
        }
        check(cursor.appPath?.hasSuffix("/Cursor.app") == true)
        check(cursor.url == nil)
        let missing = AgentLaunch.plan(source: "codex") { _ in false }
        check(missing.appPath == nil)
        check(missing.url == "https://chatgpt.com/codex")
        check(missing.note?.contains("Codex.app") == true)
        let grok = AgentLaunch.plan(source: "grok bot") { path in
            path.hasSuffix("/Grok Bot.app")
        }
        check(grok.appPath?.hasSuffix("/Grok Bot.app") == true)
    }

func LiveHooksFixWhenAsked() {
        guard let binary = ProcessInfo.processInfo.environment["MOCHI_FIX_LIVE_HOOKS"], !binary.isEmpty else { return }
        let cursor = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cursor", isDirectory: true)
        let result = HookInstaller.install(
            hooksURL: cursor.appendingPathComponent("hooks.json"),
            binaryURL: URL(fileURLWithPath: binary),
            tasksURL: cursor.appendingPathComponent("mochi-island-tasks.json"),
            privacyAccepted: true
        )
        if !result.connected {
            fputs("FAIL live hooks \(result.error ?? "")\n", stderr)
            exit(1)
        }
        print("live hooks updated")
    }

PlayReducesEnergy()
DecayPutsThePetToSleepWithoutDeath()
PlayDoesNothingWhileAsleep()
FeedFromAIWakesAndDedupes()
FedTaskIDsStayBounded()
LowHappinessDoesNotSleep()
MoodsMatchTheOldThresholds()
try LegacyDeadSaveBecomesAsleep()
try SaveClampsHunger()
OnlyRunningToDoneFeeds()
try HookInstallBacksUpAndMarksEntries()
try TaskWatchFiresWhenTheFileIsReplaced()
try ReplyWriterOnlyAllowsPermissionActions()
try TaskReaderKeepsSource()
AgentLaunchFindsInstalledAppsAndCodexFallback()
LiveHooksFixWhenAsked()
print("MochiCore checks passed")
