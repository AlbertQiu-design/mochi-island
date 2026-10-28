#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Foundation

enum AtomicFile {
    static func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temp = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temp, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            #if canImport(Darwin)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
            #else
            // replaceItemAt deletes the destination, then fails, on Linux Swift.
            let rc = temp.path.withCString { from in
                url.path.withCString { to in
                    rename(from, to)
                }
            }
            if rc != 0 {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            #endif
        } else {
            try FileManager.default.moveItem(at: temp, to: url)
        }
    }

    static func writeJSON(_ object: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try write(data, to: url)
    }
}
