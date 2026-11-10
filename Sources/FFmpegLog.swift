import Foundation

/// ~/Library/Logs/Perch/ffmpeg.log, written only by Perch.
///
/// ffmpeg used to write straight into the file, each process with its own file position, so they
/// wrote over each other and the file could balloon (it once reported 124 GB). Now every ffmpeg's
/// messages come back through a pipe and are written here, in order, with these limits:
/// - the file rotates at 5 MB to ffmpeg.old.log (replacing the previous one), so it never
///   holds more than about 10 MB in all;
/// - a message repeated within a minute is written at most 3 times, then counted, and a
///   one-line summary is written instead;
/// - passwords in camera addresses (rtsp://user:password@...) are hidden.
final class FFmpegLog: @unchecked Sendable {
    static let shared = FFmpegLog()

    static let maxBytes = 5_000_000
    private static let repeatsPerMinute = 3

    let directory: URL
    var url: URL { directory.appendingPathComponent("ffmpeg.log") }
    private var oldURL: URL { directory.appendingPathComponent("ffmpeg.old.log") }

    private let queue = DispatchQueue(label: "perch.ffmpeg-log")
    private var handle: FileHandle?
    private var size = 0

    init(directory: URL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Perch", isDirectory: true)) {
        self.directory = directory
        queue.async { self.prepare() }
    }

    /// Waits until everything handed over so far is on disk (for tests).
    func flush() { queue.sync {} }

    /// Writes one line, e.g. a "starting camera" header.
    func note(_ text: String) {
        queue.async { self.write(text + "\n") }
    }

    /// A per-stream reader: feed it ffmpeg's stderr chunks; it splits lines and drops repeats.
    final class Stream: @unchecked Sendable {
        private let label: String
        private let log: FFmpegLog
        private var partial = Data()
        private var windowStart = Date()
        private var counts: [String: Int] = [:]
        private let lock = NSLock()

        init(label: String, log: FFmpegLog = .shared) { self.label = label; self.log = log }

        func consume(_ chunk: Data) {
            lock.lock()
            partial.append(chunk)
            var lines: [String] = []
            while let nl = partial.firstIndex(of: 0x0A) {
                let line = String(decoding: partial[partial.startIndex..<nl], as: UTF8.self)
                partial.removeSubrange(partial.startIndex...nl)
                lines.append(line)
            }
            if partial.count > 64_000 { partial.removeAll() }   // a "line" that never ends
            var out = ""
            for raw in lines {
                let line = FFmpegLog.redact(raw.trimmingCharacters(in: .whitespacesAndNewlines))
                guard !line.isEmpty else { continue }
                out += rollWindowIfNeeded()
                let key = FFmpegLog.normalise(line)
                let n = (counts[key] ?? 0) + 1
                counts[key] = n
                if n <= FFmpegLog.repeatsPerMinute { out += line + "\n" }
            }
            lock.unlock()
            if !out.isEmpty { let log = log; log.queue.async { log.write(out) } }
        }

        /// Call when ffmpeg exits, to write the count of anything that was held back.
        func finish() {
            lock.lock()
            let summary = suppressedSummary()
            counts.removeAll()
            lock.unlock()
            if !summary.isEmpty { let log = log; log.queue.async { log.write(summary) } }
        }

        private func rollWindowIfNeeded() -> String {
            guard Date().timeIntervalSince(windowStart) >= 60 else { return "" }
            let summary = suppressedSummary()
            counts.removeAll()
            windowStart = Date()
            return summary
        }

        private func suppressedSummary() -> String {
            let hidden = counts.values.reduce(0) { $0 + max(0, $1 - FFmpegLog.repeatsPerMinute) }
            return hidden > 0 ? "(\(label): \(hidden) repeated messages not shown)\n" : ""
        }
    }

    // MARK: - Writing (on `queue` only)

    private func prepare() {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        // Clear out stray logs from older versions (anything but the current and previous one).
        if let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for f in files where f.lastPathComponent.hasPrefix("ffmpeg") && f.pathExtension == "log"
                && f.lastPathComponent != "ffmpeg.log" && f.lastPathComponent != "ffmpeg.old.log" {
                try? fm.removeItem(at: f)
            }
        }
        // Older versions could leave a huge or damaged log: anything over the limit is deleted.
        for f in [url, oldURL] {
            if let s = (try? fm.attributesOfItem(atPath: f.path))?[.size] as? Int, s > Self.maxBytes {
                try? fm.removeItem(at: f)
            }
        }
        open()
    }

    private func open() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        handle = try? FileHandle(forWritingTo: url)
        size = Int((try? handle?.seekToEnd()) ?? 0)
    }

    private func rotate() {
        try? handle?.close()
        handle = nil
        let fm = FileManager.default
        try? fm.removeItem(at: oldURL)
        try? fm.moveItem(at: url, to: oldURL)
    }

    private func write(_ text: String) {
        if handle == nil { open() }
        let data = Data(text.utf8)
        if size + data.count > Self.maxBytes {
            rotate()
            open()
        }
        try? handle?.write(contentsOf: data)
        size += data.count
    }

    // MARK: - Helpers

    /// rtsp://user:secret@host → rtsp://user:•••@host
    static func redact(_ line: String) -> String {
        line.replacingOccurrences(of: #"(rtsp://[^:/@\s]*):[^@\s]*@"#, with: "$1:•••@",
                                  options: .regularExpression)
    }

    /// Treats messages that differ only in memory addresses or numbers as the same message.
    static func normalise(_ line: String) -> String {
        line.replacingOccurrences(of: #"0x[0-9a-fA-F]+|-?\d+"#, with: "#", options: .regularExpression)
    }
}
