import Foundation
import AppKit
import ImageIO
import Accelerate

/// Plays one camera's RTSP stream by running ffmpeg, which decodes the video
/// (using the Mac's hardware decoder) and hands us a steady stream of frames.
/// Sub streams come as raw YUV pictures (y4m): they're small, and skipping the JPEG round trip
/// saves ffmpeg encoding and us decoding every frame. Main streams are much bigger, so they stay
/// JPEG to keep the amount of data through the pipe sensible.
final class LiveStream: @unchecked Sendable {
    let id: UUID
    let isMain: Bool
    /// Raw y4m pictures (sub streams) rather than JPEG (main streams).
    private let raw: Bool
    let startedAt = Date()
    private let url: String
    let width: Int
    private let fps: Int
    private let onFrame: @MainActor @Sendable (NSImage) -> Void
    private let onExit: @MainActor @Sendable (Bool) -> Void   // true if any frame arrived

    private var process: Process?
    private var buffer: [UInt8] = []
    /// Where the next search for the end of a frame picks up, so each byte is only looked at once.
    private var scanFrom = 0
    private var rawSize: (w: Int, h: Int)?   // from the y4m header, for raw (sub) streams
    private var lastFrameAt: Date?
    private var lastDeliveredAt = Date.distantPast
    private var _minInterval: TimeInterval = 0
    private let lock = NSLock()

    private static let registryLock = NSLock()
    private static var running: [UUID: Process] = [:]

    /// Perch's own bundled ffmpeg first, then Homebrew's.
    static var ffmpegPath: String? {
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "ffmpeg")?.path,
           FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            NSHomeDirectory() + "/.homebrew/bin/ffmpeg",
            NSHomeDirectory() + "/homebrew/bin/ffmpeg"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Whether this ffmpeg can write raw y4m pictures (older bundled builds could only do JPEG).
    static let supportsRaw: Bool = {
        guard let ffmpeg = ffmpegPath else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpeg)
        p.arguments = ["-hide_banner", "-muxers"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).contains("yuv4mpegpipe")
    }()

    init(id: UUID = UUID(), url: String, isMain: Bool, width: Int, fps: Int,
         onFrame: @escaping @MainActor @Sendable (NSImage) -> Void,
         onExit: @escaping @MainActor @Sendable (Bool) -> Void) {
        self.id = id
        self.url = url
        self.isMain = isMain
        self.raw = !isMain && LiveStream.supportsRaw
        self.width = width
        self.fps = fps
        self.onFrame = onFrame
        self.onExit = onExit
    }

    /// Frames arriving sooner than this after the last one shown are skipped without being decoded.
    /// Cameras that aren't on screen only need the odd picture, so this saves a lot of work.
    var minInterval: TimeInterval {
        get { lock.lock(); defer { lock.unlock() }; return _minInterval }
        set { lock.lock(); _minInterval = newValue; lock.unlock() }
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
            "-flags", "low_delay",
            "-probesize", "1000000", "-analyzeduration", "1000000",
            "-hwaccel", "videotoolbox",
        ] + (isMain ? [] : [
            // "nobuffer" makes the hardware decoder give up on HEVC main streams (it gets fed
            // pictures before the ones they depend on), so it's only used for sub streams.
            "-fflags", "nobuffer",
        ]) + [
            "-i", url,
            "-an",
            "-vf", width > 0 ? "fps=\(fps),scale=\(width):-2" : "fps=\(fps)"
        ] + (raw
            ? ["-pix_fmt", "yuv420p", "-f", "yuv4mpegpipe", "-"]
            : ["-pix_fmt", "yuvj420p", "-f", "image2pipe", "-vcodec", "mjpeg", "-q:v", "5", "-"])
        let pipe = Pipe()
        p.standardOutput = pipe

        // ffmpeg's messages come back to us and go into Perch's log (see FFmpegLog), rather than
        // ffmpeg writing to the file itself.
        let label = (url.components(separatedBy: "/").last ?? "stream")
        FFmpegLog.shared.note("\n--- \(Date()) starting \(label)")
        let errors = Pipe()
        let errorLog = FFmpegLog.Stream(label: label)
        p.standardError = errors
        errors.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                errorLog.finish()
            } else {
                errorLog.consume(chunk)
            }
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

    /// Asks ffmpeg to quit, and forces it if it hasn't gone within 2 seconds
    /// (after the Mac sleeps, a stuck network read can ignore the polite request).
    func stop() {
        guard let p = process, p.isRunning else { return }
        p.terminate()
        let pid = p.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [p] in
            if p.isRunning { Darwin.kill(pid, SIGKILL) }
        }
    }

    /// Called when the app quits so no ffmpeg is left running.
    static func terminateAll() {
        registryLock.lock()
        let all = Array(running.values)
        running.removeAll()
        registryLock.unlock()
        for p in all where p.isRunning { p.terminate() }
    }

    private func consume(_ chunk: Data) {
        if raw { consumeRaw(chunk) } else { consumeJPEG(chunk) }
    }

    /// Splits a y4m stream: one header line ("YUV4MPEG2 W640 H360 ..."), then for each picture
    /// a "FRAME" line followed by its Y, U and V planes.
    private func consumeRaw(_ chunk: Data) {
        lock.lock()
        buffer.append(contentsOf: chunk)
        var cut = 0
        if rawSize == nil {
            guard let nl = buffer.firstIndex(of: 0x0A) else { lock.unlock(); return }
            let header = String(decoding: buffer[0..<nl], as: UTF8.self).split(separator: " ")
            let w = header.first { $0.hasPrefix("W") }.flatMap { Int($0.dropFirst()) } ?? 0
            let h = header.first { $0.hasPrefix("H") }.flatMap { Int($0.dropFirst()) } ?? 0
            guard w > 1, h > 1 else { buffer.removeAll(); lock.unlock(); return }
            rawSize = (w, h)
            cut = nl + 1
        }
        let (w, h) = rawSize!
        let frameBytes = w * h + 2 * ((w + 1) / 2) * ((h + 1) / 2)
        var latest: Int?   // where the newest complete picture's planes start
        while let nl = buffer[cut...].firstIndex(of: 0x0A), nl - cut < 256 {
            let start = nl + 1
            guard buffer.count - start >= frameBytes else { break }
            latest = start
            cut = start + frameBytes
        }
        let now = Date()
        var deliver: [UInt8]?
        if let start = latest {
            lastFrameAt = now
            if now.timeIntervalSince(lastDeliveredAt) >= _minInterval {
                lastDeliveredAt = now
                deliver = Array(buffer[start..<(start + frameBytes)])
            }
        }
        if cut > 0 { buffer.removeFirst(cut) }
        if buffer.count > 20_000_000 { buffer.removeAll(); rawSize = nil }
        lock.unlock()

        if let planes = deliver, let image = LiveStream.convertI420(planes, width: w, height: h) {
            let onFrame = onFrame
            Task { @MainActor in onFrame(image) }
        }
    }

    /// Splits the byte stream into JPEG frames (each starts FFD8 and ends FFD9).
    private func consumeJPEG(_ chunk: Data) {
        lock.lock()
        buffer.append(contentsOf: chunk)
        var latest: ArraySlice<UInt8>?
        var cut = 0   // bytes at the front that are finished with
        while true {
            guard let start = LiveStream.find(0xD8, in: buffer, from: cut) else {
                // No frame start at all: keep only a trailing 0xFF, which may begin one.
                cut = buffer.last == 0xFF ? buffer.count - 1 : buffer.count
                scanFrom = 0
                break
            }
            let searchStart = max(start + 2, scanFrom)
            guard let end = LiveStream.find(0xD9, in: buffer, from: searchStart) else {
                cut = start
                scanFrom = max(start + 2, buffer.count - 1)
                break
            }
            latest = buffer[start..<(end + 2)]
            cut = end + 2
            scanFrom = 0
        }
        let now = Date()
        var deliver: [UInt8]?
        if let frame = latest {
            lastFrameAt = now
            if now.timeIntervalSince(lastDeliveredAt) >= _minInterval {
                lastDeliveredAt = now
                deliver = Array(frame)
            }
        }
        if cut > 0 {
            buffer.removeFirst(cut)
            scanFrom = max(0, scanFrom - cut)
        }
        if buffer.count > 20_000_000 { buffer.removeAll(); scanFrom = 0 }
        lock.unlock()

        // Only show the newest complete frame, so we never fall behind. It's decoded here, off the
        // main thread, so drawing it later costs nothing.
        if let bytes = deliver, let image = LiveStream.decode(bytes) {
            let onFrame = onFrame
            Task { @MainActor in onFrame(image) }
        }
    }

    /// Index of the first 0xFF followed by `marker`, at or after `from`.
    private static func find(_ marker: UInt8, in bytes: [UInt8], from: Int) -> Int? {
        let count = bytes.count
        guard from < count - 1 else { return nil }
        return bytes.withUnsafeBufferPointer { buf -> Int? in
            guard let base = buf.baseAddress else { return nil }
            var i = from
            while i < count - 1 {
                guard let hit = memchr(base + i, 0xFF, count - 1 - i) else { return nil }
                let at = base.distance(to: hit.assumingMemoryBound(to: UInt8.self))
                if base[at + 1] == marker { return at }
                i = at + 1
            }
            return nil
        }
    }

    /// YUV -> RGB conversion settings: BT.601 for standard-definition pictures, BT.709 for HD
    /// (the same rule ffmpeg uses), both "video range" since that's what ffmpeg's yuv420p gives us.
    private static let yuvInfo: (sd: vImage_YpCbCrToARGB, hd: vImage_YpCbCrToARGB) = {
        var range = vImage_YpCbCrPixelRange(Yp_bias: 16, CbCr_bias: 128, YpRangeMax: 235,
                                            CbCrRangeMax: 240, YpMax: 235, YpMin: 16,
                                            CbCrMax: 240, CbCrMin: 16)
        var sd = vImage_YpCbCrToARGB(), hd = vImage_YpCbCrToARGB()
        vImageConvert_YpCbCrToARGB_GenerateConversion(kvImage_YpCbCrToARGBMatrix_ITU_R_601_4,
            &range, &sd, kvImage420Yp8_Cb8_Cr8, kvImageARGB8888, vImage_Flags(kvImageNoFlags))
        vImageConvert_YpCbCrToARGB_GenerateConversion(kvImage_YpCbCrToARGBMatrix_ITU_R_709_2,
            &range, &hd, kvImage420Yp8_Cb8_Cr8, kvImageARGB8888, vImage_Flags(kvImageNoFlags))
        return (sd, hd)
    }()

    private static func convertI420(_ planes: [UInt8], width: Int, height: Int) -> NSImage? {
        let cw = (width + 1) / 2, ch = (height + 1) / 2
        let w = width & ~1, h = height & ~1   // the converter works on whole 2x2 blocks
        guard w > 0, h > 0 else { return nil }
        let rowBytes = w * 4
        var out = Data(count: rowBytes * h)
        var info = height >= 720 ? yuvInfo.hd : yuvInfo.sd
        let ok: Bool = planes.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBytes { dst in
                guard let base = src.baseAddress, let dstBase = dst.baseAddress else { return false }
                let yp = UnsafeMutableRawPointer(mutating: base)
                var yBuf = vImage_Buffer(data: yp, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: width)
                var cbBuf = vImage_Buffer(data: yp + width * height, height: vImagePixelCount(h / 2),
                                          width: vImagePixelCount(w / 2), rowBytes: cw)
                var crBuf = vImage_Buffer(data: yp + width * height + cw * ch, height: vImagePixelCount(h / 2),
                                          width: vImagePixelCount(w / 2), rowBytes: cw)
                var dest = vImage_Buffer(data: dstBase, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: rowBytes)
                let order: [UInt8] = [3, 2, 1, 0]   // ARGB -> BGRA, the layout the GPU prefers
                return vImageConvert_420Yp8_Cb8_Cr8ToARGB8888(&yBuf, &cbBuf, &crBuf, &dest, &info,
                                                              order, 255, vImage_Flags(kvImageNoFlags)) == kvImageNoError
            }
        }
        guard ok, let provider = CGDataProvider(data: out as CFData),
              let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue
                                                        | CGImageAlphaInfo.noneSkipFirst.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: true,
                               intent: .defaultIntent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: w, height: h))
    }

    private static func decode(_ bytes: [UInt8]) -> NSImage? {
        let data = Data(bytes) as CFData
        guard let source = CGImageSourceCreateWithData(data, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0,
                  [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
