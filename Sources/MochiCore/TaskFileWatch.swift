#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Foundation

/// Watches one tasks file. Atomic replace changes the inode, so a delete or rename reopens the path.
/// The change callback runs on a background queue.
public final class TaskFileWatch {
    private let queue = DispatchQueue(label: "mochi.taskwatch")
    private let fileURL: URL
    #if canImport(Darwin)
    private var source: DispatchSourceFileSystemObject?
    #else
    private var source: DispatchSourceRead?
    #endif
    private var descriptor: CInt = -1
    private var mode: Mode = .directory
    private var debounce: DispatchWorkItem?
    private var onChange: (() -> Void)?

    private enum Mode {
        case file
        case directory
    }

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func start(onChange: @escaping () -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            self.onChange = onChange
            self.arm()
        }
    }

    public func stop() {
        queue.sync {
            debounce?.cancel()
            debounce = nil
            onChange = nil
            closeSource()
        }
    }

    public func stamp() -> String {
        var info = stat()
        guard stat(fileURL.path, &info) == 0 else { return "missing" }
        #if canImport(Darwin)
        return "\(info.st_ino)-\(info.st_mtimespec.tv_sec).\(info.st_mtimespec.tv_nsec)-\(info.st_size)"
        #else
        return "\(info.st_ino)-\(info.st_mtim.tv_sec).\(info.st_mtim.tv_nsec)-\(info.st_size)"
        #endif
    }

    #if canImport(Darwin)
    private func arm() {
        closeSource()
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let exists = FileManager.default.fileExists(atPath: fileURL.path)
        let fd = open(exists ? fileURL.path : directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        descriptor = fd
        mode = exists ? .file : .directory
        let watchingFile = exists
        let mask: DispatchSource.FileSystemEvent = watchingFile
            ? [.write, .extend, .delete, .rename, .attrib]
            : [.write]
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: mask,
            queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            if watchingFile {
                let flags = source.data
                if flags.contains(.delete) || flags.contains(.rename) {
                    self.arm()
                }
                self.schedule()
            } else if FileManager.default.fileExists(atPath: self.fileURL.path) {
                self.arm()
                self.schedule()
            }
        }
        source.setCancelHandler {
            if fd >= 0 { close(fd) }
        }
        self.source = source
        source.resume()
    }

    private func closeSource() {
        guard let source else {
            if descriptor >= 0 {
                close(descriptor)
                descriptor = -1
            }
            return
        }
        let fd = descriptor
        descriptor = -1
        self.source = nil
        source.setEventHandler {}
        source.setCancelHandler {
            if fd >= 0 { close(fd) }
        }
        source.cancel()
    }
    #else
    /// Linux Dispatch has no vnode source. inotify reports the same replace-and-reopen cases.
    private func arm() {
        closeSource()
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let exists = FileManager.default.fileExists(atPath: fileURL.path)
        let fd = inotify_init1(Int32(IN_CLOEXEC | IN_NONBLOCK))
        guard fd >= 0 else { return }
        let path = exists ? fileURL.path : directory.path
        let mask = exists
            ? UInt32(IN_MODIFY | IN_ATTRIB | IN_CLOSE_WRITE | IN_DELETE_SELF | IN_MOVE_SELF)
            : UInt32(IN_CREATE | IN_MOVED_TO | IN_CLOSE_WRITE)
        guard inotify_add_watch(fd, path, mask) >= 0 else {
            close(fd)
            return
        }
        descriptor = fd
        mode = exists ? .file : .directory
        let watchingFile = exists
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let replaced = self.drainInotify()
            if watchingFile {
                if replaced || !FileManager.default.fileExists(atPath: self.fileURL.path) {
                    self.arm()
                }
                self.schedule()
            } else if FileManager.default.fileExists(atPath: self.fileURL.path) {
                self.arm()
                self.schedule()
            }
        }
        source.setCancelHandler {
            if fd >= 0 { close(fd) }
        }
        self.source = source
        source.resume()
    }

    private func drainInotify() -> Bool {
        guard descriptor >= 0 else { return false }
        var replaced = false
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count < 16 { break }
            var offset = 0
            while offset + 16 <= count {
                let mask = loadUInt32(buffer, offset + 4)
                let nameLen = loadUInt32(buffer, offset + 12)
                if mask & UInt32(IN_DELETE_SELF | IN_MOVE_SELF | IN_IGNORED) != 0 {
                    replaced = true
                }
                offset += 16 + Int(nameLen)
            }
        }
        return replaced
    }

    private func loadUInt32(_ buffer: [UInt8], _ offset: Int) -> UInt32 {
        var value: UInt32 = 0
        withUnsafeMutableBytes(of: &value) { dest in
            buffer.withUnsafeBytes { src in
                dest.copyMemory(from: UnsafeRawBufferPointer(rebasing: src[offset..<(offset + 4)]))
            }
        }
        return value
    }

    private func closeSource() {
        guard let source else {
            if descriptor >= 0 {
                close(descriptor)
                descriptor = -1
            }
            return
        }
        let fd = descriptor
        descriptor = -1
        self.source = nil
        source.setEventHandler {}
        source.setCancelHandler {
            if fd >= 0 { close(fd) }
        }
        source.cancel()
    }
    #endif

    private func schedule() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.mode == .directory, FileManager.default.fileExists(atPath: self.fileURL.path) {
                self.arm()
            }
            self.onChange?()
        }
        debounce = work
        queue.asyncAfter(deadline: .now() + .milliseconds(40), execute: work)
    }
}
