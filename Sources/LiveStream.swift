import Foundation
import AppKit

/// Plays one camera's RTSP stream by running ffmpeg, which decodes the video
/// (using the Mac's hardware decoder) and hands us a steady stream of JPEG frames.
final class LiveStream: @unchecked Sendable {
    let id: UUID
    let isMain: Bool
    let startedAt = Date()
    private let url: String
    let width: Int
    private let fps: Int
    private let onFrame: @MainActor @Sendable (NSImage) -> Void
    private let onExit: @MainActor @Sendable (Bool) -> Void   // true if any frame arrived

    private var process: Process?
    private var buffer = Data()
    private var lastFrameAt: Date?
    private let lock = NSLock()

    private static let registryLock = NSLock()
    private static var running: [UUID: Process] = [:]

    /// Where Homebrew usually puts ffmpeg.
    static var ffmpegPath: String? {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            NSHomeDirectory() + "/.homebrew/bin/ffmpeg",
            NSHomeDirectory() + "/homebrew/bin/ffmpeg"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// ~/Library/Logs/Perch/ffmpeg.log
    static var logURL: URL {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Perch", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("ffmpeg.log")
    }

    init(id: UUID = UUID(), url: String, isMain: Bool, width: Int, fps: Int,
         onFrame: @escaping @MainActor @Sendable (NSImage) -> Void,
         onExit: @escaping @MainActor @Sendable (Bool) -> Void) {
        self.id = id
        self.url = url
        self.isMain = isMain
        self.width = width
        self.fps = fps
        self.onFrame = onFrame
        self.onExit = onExit
    }

    /// When the last frame arrived (nil if none yet).
    var lastFrame: Date? {
        lock.lock(); defer { lock.unlock() }
        return lastFrameAt
    }

    func start() {
        guard let ffmpeg = LiveStream.ffmpegPath else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpeg)
        p.arguments = [
            "-hide_banner", "-loglevel", "warning", "-nostdin",
            "-rtsp_transport", "tcp",
            "-timeout", "10000000",
            // Start showing frames quickly instead of studying the stream first.
            "-fflags", "nobuffer", "-flags", "low_delay",
            "-probesize", "1000000", "-analyzeduration", "1000000",
            "-hwaccel", "videotoolbox",
            "-i", url,
            "-an",
            "-vf", width > 0 ? "fps=\(fps),scale=\(width):-2" : "fps=\(fps)",
            "-pix_fmt", "yuvj420p",
            "-f", "image2pipe", "-vcodec", "mjpeg", "-q:v", "5",
            "-"
        ]
        let pipe = Pipe()
        p.standardOutput = pipe

        // Keep ffmpeg's messages in a log file so problems can be diagnosed.
        let logURL = LiveStream.logURL
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        if let log = try? FileHandle(forWritingTo: logURL) {
            log.seekToEndOfFile()
            let label = (url.components(separatedBy: "/").last ?? "stream")
            let header = "\n--- \(Date()) starting \(label)\n"
            log.write(Data(header.utf8))
            p.standardError = log
        } else {
            p.standardError = FileHandle.nullDevice
        }

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            self?.consume(chunk)
        }
        let exit = onExit
        let myID = id
        p.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            LiveStream.registryLock.lock()
            LiveStream.running[myID] = nil
            LiveStream.registryLock.unlock()
            let gotFrames = self?.lastFrame != nil
            Task { @MainActor in exit(gotFrames) }
        }
        do {
            try p.run()
            process = p
            LiveStream.registryLock.lock()
            LiveStream.running[id] = p
            LiveStream.registryLock.unlock()
        } catch {
            Task { @MainActor in exit(false) }
        }
    }

    func stop() {
        if let p = process, p.isRunning { p.terminate() }
        process = nil
    }

    /// Called when the app quits so no ffmpeg is left running.
    static func terminateAll() {
        registryLock.lock()
        let all = Array(running.values)
        running.removeAll()
        registryLock.unlock()
        for p in all where p.isRunning { p.terminate() }
    }

    /// Splits the byte stream into JPEG frames (each starts FFD8 and ends FFD9).
    private func consume(_ chunk: Data) {
        lock.lock()
        buffer.append(chunk)
        var latest: Data?
        let soi = Data([0xFF, 0xD8])
        let eoi = Data([0xFF, 0xD9])
        while true {
            guard let start = buffer.range(of: soi) else {
                buffer.removeAll()
                break
            }
            guard let end = buffer.range(of: eoi, in: start.upperBound..<buffer.endIndex) else {
                if start.lowerBound > buffer.startIndex {
                    buffer.removeSubrange(buffer.startIndex..<start.lowerBound)
                }
                break
            }
            latest = buffer.subdata(in: start.lowerBound..<end.upperBound)
            buffer.removeSubrange(buffer.startIndex..<end.upperBound)
        }
        if buffer.count > 20_000_000 { buffer.removeAll() }
        if latest != nil { lastFrameAt = Date() }
        lock.unlock()

        // Only show the newest complete frame, so we never fall behind.
        if let frame = latest, let image = NSImage(data: frame) {
            let deliver = onFrame
            Task { @MainActor in deliver(image) }
        }
    }
}
