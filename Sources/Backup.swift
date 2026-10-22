import Foundation

/// Sends a full-resolution snapshot of an event somewhere safe: a folder (which can be a
/// network drive mounted in Finder) and/or a web address that accepts an upload.
enum Backup {
    struct Item: Sendable {
        let jpeg: Data
        let event: String        // "doorbell", "person", "vehicle", "animal", "motion" or "test"
        let eventLabel: String   // "Doorbell", "Person", …
        let camera: String
        let channel: Int         // 1-based, as shown in Perch
        let date: Date
    }

    struct Destinations: Sendable {
        var folder: String?
        var webhook: String?
        var token: String
    }

    /// Where snapshots wait if the folder can't be reached (a network drive that's disconnected).
    static var pendingFolder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = support.appendingPathComponent("Perch/pending-backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Sends one snapshot everywhere it should go. Returns a short status line for Settings.
    static func send(_ item: Item, to dest: Destinations) async -> String {
        var results: [String] = []
        if let folder = dest.folder, !folder.isEmpty {
            results.append(saveToFolder(item, folder: folder))
        }
        if let hook = dest.webhook?.trimmingCharacters(in: .whitespaces), !hook.isEmpty {
            results.append(await post(item, to: hook, token: dest.token))
        }
        let time = item.date.formatted(date: .omitted, time: .standard)
        return results.isEmpty ? "No destination is switched on." : "\(time): " + results.joined(separator: " · ")
    }

    // MARK: Folder

    /// <folder>/2026-10-22/14.37.05 Front Door (Doorbell).jpg
    static func relativePath(for item: Item) -> String {
        let day = DateFormatter(); day.dateFormat = "yyyy-MM-dd"
        let time = DateFormatter(); time.dateFormat = "HH.mm.ss"
        let unsafe = CharacterSet(charactersIn: "/:\\")
        let camera = item.camera.components(separatedBy: unsafe).joined(separator: "-")
        return "\(day.string(from: item.date))/\(time.string(from: item.date)) \(camera) (\(item.eventLabel)).jpg"
    }

    private static func saveToFolder(_ item: Item, folder: String) -> String {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath, isDirectory: true)
        let relative = relativePath(for: item)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            // Keep it and try again next time, so nothing is lost while a network drive is disconnected.
            let name = relative.replacingOccurrences(of: "/", with: "__")
            try? item.jpeg.write(to: pendingFolder.appendingPathComponent(name))
            return "folder not available, kept to send later"
        }
        do {
            let target = root.appendingPathComponent(relative)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try item.jpeg.write(to: target, options: .atomic)
            let caught = flushPending(to: root)
            return caught > 0 ? "saved to folder (+\(caught) that were waiting)" : "saved to folder"
        } catch {
            return "couldn't save to folder: \(error.localizedDescription)"
        }
    }

    /// Moves snapshots that were kept while the folder was unavailable. Returns how many.
    @discardableResult
    static func flushPending(to root: URL) -> Int {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: pendingFolder, includingPropertiesForKeys: nil) else { return 0 }
        var moved = 0
        for file in files where file.pathExtension.lowercased() == "jpg" {
            let relative = file.lastPathComponent.replacingOccurrences(of: "__", with: "/")
            let target = root.appendingPathComponent(relative)
            do {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                try fm.copyItem(at: file, to: target)
                try fm.removeItem(at: file)
                moved += 1
            } catch { continue }
        }
        return moved
    }

    // MARK: Web address

    /// POSTs multipart/form-data: fields event, camera, channel, time (ISO 8601) and the file "snapshot".
    private static func post(_ item: Item, to address: String, token: String) async -> String {
        guard let url = URL(string: address), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return "web address doesn't look right"
        }
        let boundary = "perch-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        field("event", item.event)
        field("camera", item.camera)
        field("channel", String(item.channel))
        field("time", iso.string(from: item.date))
        let filename = (relativePath(for: item) as NSString).lastPathComponent
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"snapshot\"; filename=\"\(filename)\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
        body.append(item.jpeg)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("Perch", forHTTPHeaderField: "User-Agent")
        let t = token.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }

        var lastProblem = ""
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: UInt64(attempt) * 3_000_000_000) }
            do {
                let (_, response) = try await URLSession.shared.upload(for: req, from: body)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(code) { return "sent to web address" }
                lastProblem = "web address answered \(code)"
                if (400..<500).contains(code) { break }   // retrying won't help
            } catch {
                lastProblem = "couldn't reach web address"
            }
        }
        return lastProblem
    }
}
