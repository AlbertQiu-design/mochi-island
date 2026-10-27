import Foundation

/// Capsule face files and Dock-label copy. Kitten art is the locked kitten-v1 SVGs.
public enum SlotFace {
    public static func pack(for source: String) -> String {
        switch AgentLaunch.normalize(source) {
        case "grok-bot": return "grok"
        case "mochi": return "kitten"
        case "codex": return "codex"
        default: return "cursor"
        }
    }

    public static func state(for status: String) -> String {
        switch status {
        case "running": return "work"
        case "wait", "fail": return "wait"
        case "done": return "done"
        default: return "wake"
        }
    }

    public static func resourceName(source: String, status: String) -> String {
        "\(pack(for: source))-\(state(for: status))"
    }

    public static func displayName(for source: String) -> String {
        switch AgentLaunch.normalize(source) {
        case "grok-bot": return "Grok Bot"
        case "mochi": return "小猫"
        case "codex": return "Codex"
        default: return "Cursor"
        }
    }

    public static func label(title: String, source: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "New chat" {
            return displayName(for: source)
        }
        return trimmed
    }
}
