import Foundation

public struct IslandPrefs: Codable, Equatable {
    public var dx: Double
    public var dy: Double
    public var bubbleDx: Double
    public var bubbleDy: Double
    public var fill: String
    public var text: String
    public var stroke: String
    public var cardFill: String
    public var cardStroke: String
    public var sound: String
    public var look: String
    public var petScale: Double
    public var bubbleScale: Double
    public var cursorPrivacyAccepted: Bool
    public var scanTranscripts: Bool
    public var dock: String

    public static let soundIDs = ["boop", "chirp", "mew", "pop", "twinkle"]
    public static let docks = ["left", "right"]

    public init(
        dx: Double = 0,
        dy: Double = 0,
        bubbleDx: Double = 0,
        bubbleDy: Double = 0,
        fill: String = "#ffffff",
        text: String = "#241f1c",
        stroke: String = "#2c2926",
        cardFill: String = "#fffdf8",
        cardStroke: String = "#2c2926",
        sound: String = "boop",
        look: String = "mochi",
        petScale: Double = 1,
        bubbleScale: Double = 1,
        cursorPrivacyAccepted: Bool = false,
        scanTranscripts: Bool = false,
        dock: String = "right"
    ) {
        self.dx = dx
        self.dy = dy
        self.bubbleDx = bubbleDx
        self.bubbleDy = bubbleDy
        self.fill = fill
        self.text = text
        self.stroke = stroke
        self.cardFill = cardFill
        self.cardStroke = cardStroke
        self.sound = sound
        self.look = look
        self.petScale = petScale
        self.bubbleScale = bubbleScale
        self.cursorPrivacyAccepted = cursorPrivacyAccepted
        self.scanTranscripts = scanTranscripts
        self.dock = Self.docks.contains(dock) ? dock : "right"
    }

    public var dictionary: [String: Any] {
        [
            "dx": dx,
            "dy": dy,
            "bubble_dx": bubbleDx,
            "bubble_dy": bubbleDy,
            "fill": fill,
            "text": text,
            "stroke": stroke,
            "card_fill": cardFill,
            "card_stroke": cardStroke,
            "sound": sound,
            "look": look,
            "pet_scale": petScale,
            "bubble_scale": bubbleScale,
            "dock": dock
        ]
    }

    public static func parse(_ json: [String: Any], base: IslandPrefs = IslandPrefs()) -> IslandPrefs {
        var next = base
        next.dx = number(json["dx"], fallback: base.dx)
        next.dy = number(json["dy"], fallback: base.dy)
        next.bubbleDx = number(json["bubble_dx"], fallback: base.bubbleDx)
        next.bubbleDy = number(json["bubble_dy"], fallback: base.bubbleDy)
        next.fill = hex(json["fill"]) ?? base.fill
        next.text = hex(json["text"]) ?? base.text
        next.stroke = hex(json["stroke"]) ?? base.stroke
        next.cardFill = hex(json["card_fill"]) ?? base.cardFill
        next.cardStroke = hex(json["card_stroke"]) ?? base.cardStroke
        if let sound = json["sound"] as? String, soundIDs.contains(sound) {
            next.sound = sound
        }
        if let look = json["look"] as? String,
           look.range(of: "^[a-z0-9_-]{1,32}$", options: .regularExpression) != nil {
            next.look = look
        }
        next.petScale = scale(json["pet_scale"], fallback: base.petScale)
        next.bubbleScale = scale(json["bubble_scale"], fallback: base.bubbleScale)
        if let accepted = json["cursor_privacy_accepted"] as? Bool {
            next.cursorPrivacyAccepted = accepted
        }
        if let scan = json["scan_transcripts"] as? Bool {
            next.scanTranscripts = scan
        }
        if let dock = json["dock"] as? String, docks.contains(dock) {
            next.dock = dock
        }
        return next
    }

    private static func number(_ value: Any?, fallback: Double) -> Double {
        if let number = value as? NSNumber { return number.doubleValue }
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        return fallback
    }

    private static func scale(_ value: Any?, fallback: Double) -> Double {
        let number = number(value, fallback: fallback)
        if number == 0 { return 1 }
        return min(2, max(0.5, number))
    }

    private static func hex(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.range(of: "^#[0-9a-f]{6}$", options: .regularExpression) != nil else { return nil }
        return trimmed
    }
}

public final class PrefsStore {
    public let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("prefs.json")
    }

    public static func live() -> PrefsStore {
        PrefsStore(directory: AppConfig.supportDirectory)
    }

    public func load(migrating legacyURLs: [URL] = []) -> IslandPrefs {
        if let prefs = read(fileURL) { return prefs }
        for legacy in legacyURLs {
            if let prefs = read(legacy) {
                save(prefs)
                return prefs
            }
        }
        let fresh = IslandPrefs()
        save(fresh)
        return fresh
    }

    public func save(_ prefs: IslandPrefs) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(prefs) else { return }
        try? AtomicFile.write(data, to: fileURL)
    }

    private func read(_ url: URL) -> IslandPrefs? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let decoded = try? JSONDecoder().decode(IslandPrefs.self, from: data) {
            return decoded
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return IslandPrefs.parse(json)
    }
}
