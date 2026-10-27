import Foundation

public enum AppConfig {
    public static let bundleID = "com.mochiisland.mac"
    public static let hookMarker = "mochi-island"
    public static let hookVersion = 1
    public static let fedTaskLimit = 500
    public static let doneKeep: Double = 4
    public static let liveKeep: Double = 30 * 60
    public static let settingsTabs = ["Dock", "Looks", "Colors", "Sound", "Links"]
    public static let settingsTabCircle: Double = 36

    public static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(bundleID, isDirectory: true)
    }

    public static var cursorDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor", isDirectory: true)
    }
}
