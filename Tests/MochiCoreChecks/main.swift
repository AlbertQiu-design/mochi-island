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
                "m": ["id": "m", "title": "Cat", "status": "running", "updated": now, "source": "cat"],
                "z": ["id": "z", "title": "Other", "status": "running", "updated": now, "source": "nope"]
            ]
        ]
        try JSONSerialization.data(withJSONObject: payload).write(to: url)
        let tasks = TaskReader.load(tasksURL: url, now: now)
        let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.source) })
        check(byID["c"] == "cursor")
        check(byID["x"] == "codex")
        check(byID["g"] == "grok-bot")
        check(byID["m"] == "mochi")
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
        check(AgentLaunch.normalize("cat") == "mochi")
        check(AgentLaunch.normalize("小猫") == "mochi")
        let cat = AgentLaunch.plan(source: "mochi") { _ in true }
        check(cat.appPath == nil)
        check(cat.url == nil)
        check(cat.note?.contains("小猫") == true)
        let home = AppConfig.homeDirectory
        check(home.isFileURL)
        check(!home.path.isEmpty)
        check(AppConfig.cursorDirectory.path.hasPrefix(home.path))
        check(AppConfig.supportDirectory.path.contains(AppConfig.bundleID))
        let fromHome = AgentLaunch.plan(source: "cursor", home: home) { _ in false }
        check(fromHome.url == "https://cursor.com")
    }

struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

func DockPrefDefaultsToRight() {
    let missing = IslandPrefs.parse([:])
    check(missing.dock == "right")
    let left = IslandPrefs.parse(["dock": "left"])
    check(left.dock == "left")
    check(left.dictionary["dock"] as? String == "left")
    let right = IslandPrefs.parse(["dock": "right"], base: IslandPrefs(dock: "left"))
    check(right.dock == "right")
    let junk = IslandPrefs.parse(["dock": "middle"], base: IslandPrefs(dock: "left"))
    check(junk.dock == "left")
}

func EmptySlotFileSeedsFourFaces() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mochi-slots-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let disk = DialogueSlotDisk(directory: directory)
    let store = disk.load(now: 10)
    check(store.slots.count == 4)
    check(store.slots.map(\.source) == DialogueSlotStore.seedSources)
    check(Set(store.slots.map(\.source)) == Set(["cursor", "grok-bot", "mochi", "codex"]))
    check(store.slots.first { $0.source == "mochi" }?.title == "小猫")
    check(SlotFace.pack(for: "mochi") == "kitten")
    check(SlotFace.resourceName(source: "小猫", status: "") == "kitten-wake")
    check(SlotFace.resourceName(source: "mochi", status: "wait") == "kitten-wait")
    check(SlotFace.displayName(for: "mochi") == "小猫")
    check(SlotFace.label(title: "New chat", source: "mochi") == "小猫")
    check(store.slots.allSatisfy { $0.skin == $0.source })
    check(store.slots.allSatisfy { DialogueSlotStore.skins.contains($0.skin) })
    check(store.selected == store.slots[0].id)
    check(!store.slots[0].skin.contains("happy"))
    check(!store.slots.contains { $0.skin.hasPrefix("blob-") })
    check(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("mochi-island-tasks.json").path))
    let again = disk.load(now: 99)
    check(again == store)
}

func MergeKeepsSkinAndLeavesSlotsWhenTasksLeave() {
    var rng = SplitMix64(seed: 3)
    let seeded = DialogueSlotStore.seed(now: 1, rng: &rng)
    let keptID = seeded.slots[0].id
    let stillThere = seeded.merged(with: [])
    check(stillThere.slots.contains { $0.id == keptID })

    let store = DialogueSlotStore(
        selected: "abc",
        slots: [DialogueSlot(id: "abc", source: "cursor", title: "Keep", skin: "blob-3", created: 1)]
    )
    let task = CursorTask(id: "abc", title: "From bus", status: "running", source: "codex", updated: 5)
    let merged = store.merged(with: [task])
    check(merged.slots.count == 1)
    check(merged.slots[0].skin == "codex")
    check(merged.slots[0].source == "codex")
    check(merged.slots[0].title == "From bus")
    check(merged.merged(with: [task]).slots[0].skin == "codex")

    let added = DialogueSlotStore().merged(with: [task])
    check(added.slots[0].skin == "codex")
    check(added.slots[0].skin == DialogueSlotStore.face(for: "codex"))
}

func CreateSlotAppendsAFaceWithoutATaskFile() {
    var rng = SplitMix64(seed: 9)
    let store = DialogueSlotStore.seed(now: 2, rng: &rng)
    var createRNG = SplitMix64(seed: 11)
    let (next, slot) = store.created(source: "Grok Bot", now: 20, rng: &createRNG)
    check(next.slots.count == store.slots.count + 1)
    check(next.selected == slot.id)
    check(slot.source == "grok-bot")
    check(slot.skin == "grok-bot")
    check(slot.title == "New chat")
    check(DialogueSlotStore.skins.contains(slot.skin))
    check(!slot.skin.contains("happy"))
    var catRNG = SplitMix64(seed: 12)
    let cat = store.created(source: "小猫", now: 21, rng: &catRNG).1
    check(cat.source == "mochi")
    check(cat.skin == "mochi")
}

func KittenV1FaceFilesFollowSource() {
    check(SlotFace.pack(for: "cursor") == "cursor")
    check(SlotFace.pack(for: "grok-bot") == "grok")
    check(SlotFace.pack(for: "小猫") == "kitten")
    check(SlotFace.resourceName(source: "mochi", status: "running") == "kitten-work")
    check(SlotFace.resourceName(source: "mochi", status: "done") == "kitten-done")
    check(SlotFace.label(title: "Fix tabs", source: "cursor") == "Fix tabs")
    check(SlotFace.displayName(for: "grok-bot") == "Grok Bot")
}

func EnsuringSeedAddsMissingKitten() {
    let store = DialogueSlotStore(
        selected: "seed-cursor",
        slots: [
            DialogueSlot(id: "seed-cursor", source: "cursor", title: "Cursor", skin: "cursor", created: 1),
            DialogueSlot(id: "seed-grok-bot", source: "grok-bot", title: "Grok", skin: "grok-bot", created: 1)
        ]
    )
    check(!store.slots.contains { $0.source == "mochi" })
    let filled = store.ensuringSeedSources()
    check(filled.slots.contains { $0.source == "mochi" && $0.id == "seed-mochi" })
    check(filled.slots.contains { $0.source == "cursor" })
    check(filled.slots.contains { $0.source == "grok-bot" })
    check(filled.slots.contains { $0.source == "codex" && $0.id == "seed-codex" })
    check(filled.slots.first { $0.source == "mochi" }?.title == "小猫")
}

func SelectingKeepsOnlyKnownIds() {
    var rng = SplitMix64(seed: 5)
    let store = DialogueSlotStore.seed(now: 1, rng: &rng)
    let picked = store.slots[1].id
    let next = store.selecting(picked)
    check(next.selected == picked)
    check(next.slots == store.slots)
    let junk = store.selecting("missing")
    check(junk.selected == store.selected)
}

func NewWaitSelectsOnlyAfterTheFirstSnapshot() {
    var rng = SplitMix64(seed: 4)
    let store = DialogueSlotStore.seed(now: 1, rng: &rng)
    var known: Set<String> = []
    var primed = false
    let first = store.selectingNewWaits(
        in: [CursorTask(id: "w", title: "Waiting", status: "wait", updated: 9)],
        known: &known,
        primed: &primed
    )
    check(primed)
    check(first.selected == store.selected)
    check(first.slots.contains { $0.id == "w" })
    let second = first.selectingNewWaits(
        in: [
            CursorTask(id: "w", title: "Waiting", status: "wait", updated: 9),
            CursorTask(id: "w2", title: "Newer", status: "wait", source: "codex", updated: 12)
        ],
        known: &known,
        primed: &primed
    )
    check(second.selected == "w2")
    check(second.slots.contains { $0.id == "w" })
    check(second.slots.first { $0.id == "w2" }?.source == "codex")
}

func LiveHooksFixWhenAsked() {
        guard let binary = ProcessInfo.processInfo.environment["MOCHI_FIX_LIVE_HOOKS"], !binary.isEmpty else { return }
        let cursor = AppConfig.cursorDirectory
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
DockPrefDefaultsToRight()
try EmptySlotFileSeedsFourFaces()
MergeKeepsSkinAndLeavesSlotsWhenTasksLeave()
CreateSlotAppendsAFaceWithoutATaskFile()
KittenV1FaceFilesFollowSource()
EnsuringSeedAddsMissingKitten()
SelectingKeepsOnlyKnownIds()
NewWaitSelectsOnlyAfterTheFirstSnapshot()
LiveHooksFixWhenAsked()
print("MochiCore checks passed")
