import Foundation

public struct DialogueSlot: Codable, Equatable {
    public var id: String
    public var source: String
    public var title: String
    public var skin: String
    public var created: Double

    public init(id: String, source: String, title: String, skin: String, created: Double) {
        self.id = id
        self.source = source
        self.title = title
        self.skin = skin
        self.created = created
    }

    public var dictionary: [String: Any] {
        [
            "id": id,
            "source": source,
            "title": title,
            "skin": skin,
            "created": created
        ]
    }
}

public struct DialogueSlotStore: Codable, Equatable {
    public static let skins = [
        "blob-0", "blob-1", "blob-2", "blob-3",
        "blob-4", "blob-5", "blob-6", "blob-7"
    ]
    public static let seedSources = ["cursor", "codex", "grok-bot"]

    public var selected: String
    public var slots: [DialogueSlot]

    public init(selected: String = "", slots: [DialogueSlot] = []) {
        self.selected = selected
        self.slots = slots
    }

    /// FNV-style mix that stays in the same residue class in Swift and the page.
    public static func stableSkin(for id: String) -> String {
        var hash = 0
        for byte in id.utf8 {
            hash = (hash * 33 + Int(byte)) % 997
        }
        let index = (hash % skins.count + skins.count) % skins.count
        return skins[index]
    }

    public static func randomSkin(excluding: Set<String>, rng: inout some RandomNumberGenerator) -> String {
        var pool = skins.filter { !excluding.contains($0) }
        if pool.isEmpty { pool = skins }
        let index = Int.random(in: 0..<pool.count, using: &rng)
        return pool[index]
    }

    public static func seed(now: Double, rng: inout some RandomNumberGenerator) -> DialogueSlotStore {
        var used: Set<String> = []
        var slots: [DialogueSlot] = []
        for source in seedSources {
            let skin = randomSkin(excluding: used, rng: &rng)
            used.insert(skin)
            slots.append(DialogueSlot(
                id: "seed-\(source)",
                source: source,
                title: "New chat",
                skin: skin,
                created: now
            ))
        }
        return DialogueSlotStore(selected: slots[0].id, slots: slots)
    }

    public func normalized() -> DialogueSlotStore {
        var next = self
        next.slots = next.slots.map { slot in
            var copy = slot
            copy.source = AgentLaunch.normalize(copy.source)
            if !Self.skins.contains(copy.skin) {
                copy.skin = Self.stableSkin(for: copy.id)
            }
            if copy.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                copy.title = "New chat"
            }
            return copy
        }
        if !next.slots.contains(where: { $0.id == next.selected }) {
            next.selected = next.slots.first?.id ?? ""
        }
        return next
    }

    /// Adds a slot for each task id that is not stored yet. Existing skins stay put.
    public func merged(with tasks: [CursorTask]) -> DialogueSlotStore {
        var next = normalized()
        var indexByID: [String: Int] = [:]
        for (index, slot) in next.slots.enumerated() {
            indexByID[slot.id] = index
        }
        for task in tasks {
            let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if let index = indexByID[task.id] {
                next.slots[index].source = AgentLaunch.normalize(task.source)
                if !title.isEmpty {
                    next.slots[index].title = title
                }
                continue
            }
            let created = task.updated > 0 ? task.updated : 0
            let slot = DialogueSlot(
                id: task.id,
                source: AgentLaunch.normalize(task.source),
                title: title.isEmpty ? "New chat" : title,
                skin: Self.stableSkin(for: task.id),
                created: created
            )
            indexByID[task.id] = next.slots.count
            next.slots.append(slot)
        }
        if !next.slots.contains(where: { $0.id == next.selected }) {
            next.selected = next.slots.first?.id ?? ""
        }
        return next
    }

    public func created(source: String, now: Double, rng: inout some RandomNumberGenerator) -> (DialogueSlotStore, DialogueSlot) {
        var next = normalized()
        let used = Set(next.slots.map(\.skin))
        let slot = DialogueSlot(
            id: "slot-\(UUID().uuidString.lowercased())",
            source: AgentLaunch.normalize(source),
            title: "New chat",
            skin: Self.randomSkin(excluding: used, rng: &rng),
            created: now
        )
        next.slots.append(slot)
        next.selected = slot.id
        return (next, slot)
    }

    /// Selects the newest wait id that was not already known. The first call only records ids.
    public func selectingNewWaits(in tasks: [CursorTask], known: inout Set<String>, primed: inout Bool) -> DialogueSlotStore {
        var next = merged(with: tasks)
        let waits = tasks.filter { $0.status == "wait" }
        if primed {
            let fresh = waits.filter { !known.contains($0.id) }
            if let newest = fresh.max(by: { $0.updated < $1.updated }) {
                next.selected = newest.id
            }
        }
        known = Set(waits.map(\.id))
        primed = true
        return next
    }
}

public final class DialogueSlotDisk {
    public let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("dialogue-slots.json")
    }

    public static func live() -> DialogueSlotDisk {
        DialogueSlotDisk(directory: AppConfig.supportDirectory)
    }

    public func load(now: Double = Date().timeIntervalSince1970) -> DialogueSlotStore {
        if let existing = read() { return existing }
        var rng = SystemRandomNumberGenerator()
        let seeded = DialogueSlotStore.seed(now: now, rng: &rng)
        save(seeded)
        return seeded
    }

    public func save(_ store: DialogueSlotStore) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(store.normalized()) else { return }
        try? AtomicFile.write(data, to: fileURL)
    }

    private func read() -> DialogueSlotStore? {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(DialogueSlotStore.self, from: data),
              !decoded.slots.isEmpty else {
            return nil
        }
        return decoded.normalized()
    }
}
