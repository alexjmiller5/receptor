import Foundation

/// Writes timestamped lines to `debug.log` in the App Group container.
/// Works across processes, survives force-quits. No SwiftData dependency.
enum DebugFileLog {
    private static let fileName = "debug.log"

    private static var fileURL: URL? {
        Configuration.sharedContainerURL?.appendingPathComponent(fileName)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    /// Appends a single timestamped line. Thread-safe via file coordination.
    static func write(_ message: String) {
        guard let url = fileURL else { return }
        let pid = ProcessInfo.processInfo.processIdentifier
        let proc = ProcessInfo.processInfo.processName
        let ts = dateFormatter.string(from: Date())
        let line = "[\(ts)] pid=\(pid) proc=\(proc) \(message)\n"

        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Returns the full contents of the debug log, or nil if empty/missing.
    static func readAll() -> String? {
        guard let url = fileURL else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Clears the debug log file.
    static func clear() {
        guard let url = fileURL else { return }
        try? "".write(to: url, atomically: true, encoding: .utf8)
    }
}
