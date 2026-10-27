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
    public static let skins = ["cursor", "grok-bot", "mochi", "codex"]
    public static let seedSources = ["cursor", "grok-bot", "mochi", "codex"]

    public var selected: String
    public var slots: [DialogueSlot]

    public init(selected: String = "", slots: [DialogueSlot] = []) {
        self.selected = selected
        self.slots = slots
    }

    public static func face(for source: String) -> String {
        switch AgentLaunch.normalize(source) {
        case "grok-bot": return "grok-bot"
        case "mochi": return "mochi"
        case "codex": return "codex"
        default: return "cursor"
        }
    }

    /// Kept for older callers; face now follows the source, not a hash of the id.
    public static func stableSkin(for id: String) -> String {
        face(for: id.hasPrefix("seed-") ? String(id.dropFirst(5)) : "cursor")
    }

    public static func seed(now: Double, rng: inout some RandomNumberGenerator) -> DialogueSlotStore {
        _ = rng.next()
        let slots = seedSources.map { source in
            DialogueSlot(
                id: "seed-\(source)",
                source: source,
                title: source == "mochi" ? SlotFace.displayName(for: source) : "New chat",
                skin: face(for: source),
                created: now
            )
        }
        return DialogueSlotStore(selected: slots[0].id, slots: slots)
    }

    public func normalized() -> DialogueSlotStore {
        var next = self
        next.slots = next.slots.map { slot in
            var copy = slot
            copy.source = AgentLaunch.normalize(copy.source)
            copy.skin = Self.face(for: copy.source)
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

    public func ensuringSeedSources() -> DialogueSlotStore {
        var next = normalized()
        for (index, source) in Self.seedSources.enumerated() {
            guard !next.slots.contains(where: { AgentLaunch.normalize($0.source) == source }) else { continue }
            next.slots.insert(
                DialogueSlot(
                    id: "seed-\(source)",
                    source: source,
                    title: source == "mochi" ? SlotFace.displayName(for: source) : "New chat",
                    skin: Self.face(for: source),
                    created: next.slots.first?.created ?? 0
                ),
                at: min(index, next.slots.count)
            )
        }
        if !next.slots.contains(where: { $0.id == next.selected }) {
            next.selected = next.slots.first?.id ?? ""
        }
        return next
    }

    /// Adds a slot for each task id that is not stored yet. Face follows the source.
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
                next.slots[index].skin = Self.face(for: next.slots[index].source)
                if !title.isEmpty {
                    next.slots[index].title = title
                }
                continue
            }
            let created = task.updated > 0 ? task.updated : 0
            let source = AgentLaunch.normalize(task.source)
            let slot = DialogueSlot(
                id: task.id,
                source: source,
                title: title.isEmpty ? "New chat" : title,
                skin: Self.face(for: source),
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
        _ = rng.next()
        let source = AgentLaunch.normalize(source)
        let slot = DialogueSlot(
            id: "slot-\(UUID().uuidString.lowercased())",
            source: source,
            title: "New chat",
            skin: Self.face(for: source),
            created: now
        )
        next.slots.append(slot)
        next.selected = slot.id
        return (next, slot)
    }

    public func selecting(_ id: String) -> DialogueSlotStore {
        var next = normalized()
        if next.slots.contains(where: { $0.id == id }) {
            next.selected = id
        }
        return next
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
        if let existing = read() {
            let filled = existing.ensuringSeedSources()
            if filled != existing { save(filled) }
            return filled
        }
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
