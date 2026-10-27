import Foundation

public enum AppConfig {
    public static let bundleID = "com.mochiisland.mac"
    public static let hookMarker = "mochi-island"
    public static let hookVersion = 1
    public static let fedTaskLimit = 500
    public static let doneKeep: Double = 4
    public static let liveKeep: Double = 30 * 60

    public static var homeDirectory: URL {
        #if os(macOS)
        FileManager.default.homeDirectoryForCurrentUser
        #else
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        #endif
    }

    public static var supportDirectory: URL {
        homeDirectory
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(bundleID, isDirectory: true)
    }

    public static var cursorDirectory: URL {
        homeDirectory
            .appendingPathComponent(".cursor", isDirectory: true)
    }
}
