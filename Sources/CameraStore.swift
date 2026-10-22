import SwiftUI
import AppKit

struct Camera: Identifiable, Hashable {
    let channel: Int      // NVR channel, starting at 0
    var name: String
    var id: Int { channel }
    var key: String { String(channel + 1) }
}

/// One RTSP stream: a channel's full-quality main stream or its light sub stream.
struct StreamKey: Hashable {
    let channel: Int
    let main: Bool
}

enum StreamQuality: String, CaseIterable, Identifiable {
    case best, high, low

    var id: String { rawValue }

    var label: String {
        switch self {
        case .best: return "Maximum (full resolution, uses more power)"
        case .high: return "High (HD)"
        case .low: return "Low (saves data and power)"
        }
    }

    var short: String {
        switch self {
        case .best: return "MAX"
        case .high: return "HD"
        case .low: return "SD"
        }
    }
}

enum GridLayout: String, CaseIterable, Identifiable {
    case auto, grid, focus, row, column

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Automatic"
        case .grid: return "Grid"
        case .focus: return "One large, others small"
        case .row: return "Side by side"
        case .column: return "Stacked"
        }
    }
}

/// Talks to the Reolink NVR on the local network: live video, snapshots and detections.
@MainActor
final class CameraStore: ObservableObject {
    // MARK: Settings
    @Published var host: String
    @Published var username: String
    @Published var password: String
    @Published var names: [String]
    @Published var panelInterval: Double
    @Published var alertsEnabled: Bool
    @Published var alertPeople: Bool
    @Published var alertVehicles: Bool
    @Published var alertAnimals: Bool
    @Published var alertMotion: Bool
    @Published var alertSound: Bool
    @Published var snoozedUntil: Date?

    // MARK: View state
    @Published var images: [Int: NSImage] = [:]
    @Published var motion: [Int: Bool] = [:]          // something detected right now
    @Published var lastUpdate: Date?
    @Published var lastError: String?
    @Published var selected: Int = 0 { didSet { updateStreams() } }
    @Published var showGrid = false { didSet { updateStreams() } }
    @Published var previewEvent: DetectionEvent? = nil { didSet { updateStreams() } }
    @Published var miniChannel: Int = 0 { didSet { updateStreams() } }
    @Published var events: [DetectionEvent] = []
    @Published var unseen = 0
    @Published var pinned = UserDefaults.standard.bool(forKey: "pinned") {
        didSet { UserDefaults.standard.set(pinned, forKey: "pinned") }
    }
    @Published var fillTiles = UserDefaults.standard.object(forKey: "fillTiles") as? Bool ?? false {
        didSet { UserDefaults.standard.set(fillTiles, forKey: "fillTiles") }
    }
    @Published var gridLayout = GridLayout(rawValue: UserDefaults.standard.string(forKey: "gridLayout") ?? "") ?? .auto {
        didSet { UserDefaults.standard.set(gridLayout.rawValue, forKey: "gridLayout") }
    }
    /// Rotation in degrees (0, 90, 180, 270) for each channel.
    @Published var rotations: [Int: Int] = [:]

    // MARK: All-cameras view settings
    @Published var gridOrder: [Int] = (UserDefaults.standard.array(forKey: "gridOrder") as? [Int]) ?? [] {
        didSet { UserDefaults.standard.set(gridOrder, forKey: "gridOrder") }
    }
    @Published var gridHidden: [Int] = (UserDefaults.standard.array(forKey: "gridHidden") as? [Int]) ?? [] {
        didSet { UserDefaults.standard.set(gridHidden, forKey: "gridHidden") }
    }
    @Published var gridSpacing: Double = UserDefaults.standard.object(forKey: "gridSpacing") as? Double ?? 2 {
        didSet { UserDefaults.standard.set(gridSpacing, forKey: "gridSpacing") }
    }
    @Published var gridShowNames: Bool = UserDefaults.standard.object(forKey: "gridShowNames") as? Bool ?? true {
        didSet { UserDefaults.standard.set(gridShowNames, forKey: "gridShowNames") }
    }
    @Published var gridShowBadges: Bool = UserDefaults.standard.object(forKey: "gridShowBadges") as? Bool ?? true {
        didSet { UserDefaults.standard.set(gridShowBadges, forKey: "gridShowBadges") }
    }
    @Published var focusChannel: Int = UserDefaults.standard.object(forKey: "focusChannel") as? Int ?? 0 {
        didSet { UserDefaults.standard.set(focusChannel, forKey: "focusChannel") }
    }
    /// Open the camera window when Perch is opened from the Dock, Finder or Launchpad.
    @Published var openViewerOnLaunch: Bool = UserDefaults.standard.object(forKey: "openViewerOnLaunch") as? Bool ?? true {
        didSet { UserDefaults.standard.set(openViewerOnLaunch, forKey: "openViewerOnLaunch") }
    }

    /// Video quality for one camera on its own, and for the all-cameras view.
    @Published var singleQuality = StreamQuality(rawValue: UserDefaults.standard.string(forKey: "singleQuality") ?? "") ?? .high {
        didSet {
            UserDefaults.standard.set(singleQuality.rawValue, forKey: "singleQuality")
            updateStreams()
        }
    }
    @Published var gridQuality = StreamQuality(rawValue: UserDefaults.standard.string(forKey: "gridQuality") ?? "") ?? .low {
        didSet {
            UserDefaults.standard.set(gridQuality.rawValue, forKey: "gridQuality")
            updateStreams()
        }
    }

    /// Per-camera choice of fill (true) or fit (false); cameras not listed use `fillTiles`.
    @Published var fitOverrides: [Int: Bool] = CameraStore.loadFitOverrides() {
        didSet {
            var raw: [String: Bool] = [:]
            for (ch, value) in fitOverrides { raw[String(ch)] = value }
            UserDefaults.standard.set(raw, forKey: "fitOverrides")
        }
    }

    nonisolated static func loadFitOverrides() -> [Int: Bool] {
        let raw = UserDefaults.standard.dictionary(forKey: "fitOverrides") as? [String: Bool] ?? [:]
        var result: [Int: Bool] = [:]
        for (key, value) in raw {
            if let ch = Int(key) { result[ch] = value }
        }
        return result
    }

    /// Whether this camera's picture is cropped to fill its space.
    func fills(_ channel: Int) -> Bool { fitOverrides[channel] ?? fillTiles }

    /// nil = follow the default.
    func setFill(_ channel: Int, _ value: Bool?) {
        if let value {
            fitOverrides[channel] = value
        } else {
            fitOverrides.removeValue(forKey: channel)
        }
    }

    /// Channels that have a camera (empty = all of `names`). Filled in by camera detection.
    @Published var activeChannels: [Int] = (UserDefaults.standard.array(forKey: "activeChannels") as? [Int]) ?? [] {
        didSet { UserDefaults.standard.set(activeChannels, forKey: "activeChannels") }
    }
    @Published var detecting = false
    private var camerasDetected = UserDefaults.standard.bool(forKey: "camerasDetected")

    /// What we last asked the cameras to show burned into the picture.
    @Published var osdTime: Bool = UserDefaults.standard.object(forKey: "osdTime") as? Bool ?? true {
        didSet { UserDefaults.standard.set(osdTime, forKey: "osdTime") }
    }
    @Published var osdName: Bool = UserDefaults.standard.object(forKey: "osdName") as? Bool ?? true {
        didSet { UserDefaults.standard.set(osdName, forKey: "osdName") }
    }

    // MARK: Private
    private var panelTask: Task<Void, Never>?
    private var liveTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var panelOpen = false
    private var viewerOpen = false
    private var miniOpen = false

    private var streams: [StreamKey: LiveStream] = [:]
    private var frameAt: [StreamKey: Date] = [:]
    private var pathVariant: [Int: Int] = [:]

    private var activeKinds: [Int: Set<DetectionEvent.Kind>] = [:]
    private var lastEventAt: [String: Date] = [:]
    private var lastActiveAt: [String: Date] = [:]
    private var aiSupported: [Int: Bool] = [:]
    private var eventImageCache: [UUID: NSImage] = [:]

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    init() {
        let d = UserDefaults.standard
        CameraStore.migrateFromOldName(into: d)
        host = d.string(forKey: "host") ?? ""
        username = d.string(forKey: "username") ?? "viewer"
        names = d.stringArray(forKey: "names") ?? ["Driveway", "Garden", "Front Door", "Side gate"]
        let interval = d.double(forKey: "panelInterval")
        panelInterval = interval > 0 ? interval : 1
        alertsEnabled = d.object(forKey: "alertsEnabled") as? Bool ?? true
        alertPeople = d.object(forKey: "alertPeople") as? Bool ?? true
        alertVehicles = d.object(forKey: "alertVehicles") as? Bool ?? true
        alertAnimals = d.object(forKey: "alertAnimals") as? Bool ?? false
        alertMotion = d.object(forKey: "alertMotion") as? Bool ?? false
        alertSound = d.object(forKey: "alertSound") as? Bool ?? true
        snoozedUntil = nil
        password = Keychain.load(account: "nvr")
            ?? Keychain.load(account: "nvr", service: "ReolinkViewer")
            ?? ""
        for ch in 0..<names.count {
            rotations[ch] = d.integer(forKey: "rotation\(ch)")
        }
        events = EventLog.load()

        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: nil) { _ in
            LiveStream.terminateAll()
        }
        restartMonitor()
        if !camerasDetected && isConfigured {
            Task { _ = await self.detectCameras() }
        }
    }

    /// Brings settings across from the app's earlier name, once.
    private static func migrateFromOldName(into d: UserDefaults) {
        guard d.string(forKey: "host") == nil,
              let old = UserDefaults(suiteName: "local.reolink-viewer"),
              old.string(forKey: "host") != nil else { return }
        var keys = ["host", "username", "names", "panelInterval", "alertsEnabled", "alertPeople",
                    "alertVehicles", "alertAnimals", "alertMotion", "alertSound", "pinned",
                    "fillTiles", "gridLayout"]
        for ch in 0..<32 { keys.append("rotation\(ch)") }
        for key in keys {
            if let value = old.object(forKey: key) { d.set(value, forKey: key) }
        }
    }

    // MARK: - Basics

    var cameras: [Camera] {
        let channels = activeChannels.isEmpty
            ? Array(names.indices)
            : activeChannels.filter { names.indices.contains($0) }.sorted()
        return channels.map { Camera(channel: $0, name: names[$0]) }
    }

    func setCameraActive(_ channel: Int, _ on: Bool) {
        var list = activeChannels.isEmpty ? Array(names.indices) : activeChannels
        if on {
            if !list.contains(channel) { list.append(channel) }
        } else {
            list.removeAll { $0 == channel }
        }
        activeChannels = list.sorted()
        restartEverything()
    }

    var isConfigured: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty && !username.isEmpty && !password.isEmpty
    }

    var liveVideoAvailable: Bool { LiveStream.ffmpegPath != nil }

    var isSnoozed: Bool {
        if let s = snoozedUntil { return s > Date() }
        return false
    }

    func snooze(hours: Double) { snoozedUntil = Date().addingTimeInterval(hours * 3600) }
    func unsnooze() { snoozedUntil = nil }

    func rotation(for channel: Int) -> Int { rotations[channel] ?? 0 }

    /// Turns a camera's picture 90° anticlockwise each time.
    func rotate(_ channel: Int) {
        let next = (rotation(for: channel) + 270) % 360
        rotations[channel] = next
        UserDefaults.standard.set(next, forKey: "rotation\(channel)")
    }

    /// All channels in the user's chosen order.
    var orderedChannels: [Int] {
        let all = cameras.map(\.channel)
        var order = gridOrder.filter { all.contains($0) }
        for ch in all where !order.contains(ch) { order.append(ch) }
        return order
    }

    /// The cameras shown in the all-cameras view, in order.
    var gridCameras: [Camera] {
        orderedChannels.filter { !gridHidden.contains($0) }.map { Camera(channel: $0, name: name(for: $0)) }
    }

    func moveInGrid(_ channel: Int, by offset: Int) {
        var order = orderedChannels
        guard let i = order.firstIndex(of: channel) else { return }
        let j = i + offset
        guard order.indices.contains(j) else { return }
        order.swapAt(i, j)
        gridOrder = order
    }

    func setShownInGrid(_ channel: Int, _ shown: Bool) {
        if shown {
            gridHidden.removeAll { $0 == channel }
        } else if !gridHidden.contains(channel) {
            gridHidden.append(channel)
        }
    }

    func name(for channel: Int) -> String {
        names.indices.contains(channel) ? names[channel] : "Camera \(channel + 1)"
    }

    func save() {
        let d = UserDefaults.standard
        host = host.trimmingCharacters(in: .whitespaces)
        d.set(host, forKey: "host")
        d.set(username, forKey: "username")
        d.set(names, forKey: "names")
        d.set(panelInterval, forKey: "panelInterval")
        d.set(alertsEnabled, forKey: "alertsEnabled")
        d.set(alertPeople, forKey: "alertPeople")
        d.set(alertVehicles, forKey: "alertVehicles")
        d.set(alertAnimals, forKey: "alertAnimals")
        d.set(alertMotion, forKey: "alertMotion")
        d.set(alertSound, forKey: "alertSound")
        Keychain.save(password, account: "nvr")
        restartEverything()
        if !camerasDetected && isConfigured {
            Task { _ = await self.detectCameras() }
        }
    }

    private func restartEverything() {
        for s in streams.values { s.stop() }
        streams.removeAll()
        frameAt.removeAll()
        aiSupported.removeAll()
        activeKinds.removeAll()
        restartPanelPolling()
        restartLivePolling()
        restartMonitor()
    }

    // MARK: - Camera detection

    /// Asks the NVR (or a single camera) how many channels it has, which are online and what they're called.
    func detectCameras() async -> String {
        guard isConfigured else { return "Set up the NVR connection first." }
        detecting = true
        defer { detecting = false }

        var found: [(channel: Int, name: String?, online: Bool)] = []

        // NVRs list every channel with its name and whether a camera is connected.
        if let reply = await apiPost("GetChannelstatus", param: [:]),
           (reply["code"] as? Int) == 0,
           let value = reply["value"] as? [String: Any],
           let list = value["status"] as? [[String: Any]], !list.isEmpty {
            for item in list {
                guard let ch = item["channel"] as? Int else { continue }
                let online = (item["online"] as? Int ?? 1) == 1
                let name = (item["name"] as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
                found.append((ch, name, online))
            }
        }

        // A single camera, or older firmware: ask how many channels there are.
        if found.isEmpty {
            var count = 0
            if let reply = await apiPost("GetDevInfo", param: [:]),
               (reply["code"] as? Int) == 0,
               let value = reply["value"] as? [String: Any],
               let info = value["DevInfo"] as? [String: Any] {
                count = info["channelNum"] as? Int ?? 1
            }
            guard count > 0 else {
                return "Couldn't read the camera list from the NVR. Check the connection and try again."
            }
            for ch in 0..<count { found.append((ch, nil, true)) }
        }

        // Fill in any missing names from each camera's on-screen name.
        for i in found.indices where found[i].name == nil && found[i].online {
            if let reply = await apiPost("GetOsd", param: ["channel": found[i].channel]),
               let value = reply["value"] as? [String: Any],
               let osd = value["Osd"] as? [String: Any],
               let channelInfo = osd["osdChannel"] as? [String: Any],
               let name = channelInfo["name"] as? String,
               !name.trimmingCharacters(in: .whitespaces).isEmpty {
                found[i].name = name
            }
        }

        let maxChannel = found.map { $0.channel }.max() ?? 0
        var newNames: [String] = []
        for ch in 0...maxChannel {
            let entry = found.first { $0.channel == ch }
            newNames.append(entry?.name ?? (names.indices.contains(ch) ? names[ch] : "Camera \(ch + 1)"))
        }
        let online = found.filter { $0.online }.map { $0.channel }.sorted()

        names = newNames
        activeChannels = online
        UserDefaults.standard.set(names, forKey: "names")
        camerasDetected = true
        UserDefaults.standard.set(true, forKey: "camerasDetected")
        if !online.contains(selected), let first = online.first { selected = first }
        if !online.contains(miniChannel), let first = online.first { miniChannel = first }
        if !online.contains(focusChannel), let first = online.first { focusChannel = first }
        restartEverything()

        let offline = found.count - online.count
        let plural = online.count == 1 ? "camera" : "cameras"
        return offline > 0
            ? "Found \(online.count) \(plural) (\(offline) empty or offline channel\(offline == 1 ? "" : "s") hidden)."
            : "Found \(online.count) \(plural)."
    }

    // MARK: - Events

    func eventsToday(channel: Int) -> [DetectionEvent] {
        let start = Calendar.current.startOfDay(for: Date())
        return events.filter { $0.channel == channel && $0.date >= start }
    }

    /// "Person · 2m" for the most recent event on a camera in the last 30 minutes.
    func recentBadge(channel: Int) -> EventBadge? {
        guard let e = events.first(where: { $0.channel == channel }) else { return nil }
        let age = Date().timeIntervalSince(e.date)
        guard age < 30 * 60 else { return nil }
        let minutes = Int(age / 60)
        return EventBadge(text: "\(e.kind.label) · \(minutes < 1 ? "now" : "\(minutes)m")", color: e.kind.color)
    }

    func image(for event: DetectionEvent) -> NSImage? {
        if let cached = eventImageCache[event.id] { return cached }
        guard let img = NSImage(contentsOf: EventLog.imageURL(for: event.id)) else { return nil }
        eventImageCache[event.id] = img
        return img
    }

    private func shouldAlert(_ kind: DetectionEvent.Kind) -> Bool {
        guard alertsEnabled, !isSnoozed else { return false }
        switch kind {
        case .person: return alertPeople
        case .vehicle: return alertVehicles
        case .animal: return alertAnimals
        case .motion: return alertMotion
        }
    }

    // MARK: - Addresses

    private static let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
    private func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? s }

    private var hostParts: (host: String, port: Int?)? {
        let parts = host.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard let h = parts.first, !h.isEmpty else { return nil }
        let port = parts.count > 1 ? Int(parts[1]) : nil
        return (String(h), port)
    }

    private func url(cmd: String, channel: Int) -> URL? {
        guard let hp = hostParts else { return nil }
        var c = URLComponents()
        c.scheme = "http"
        c.host = hp.host
        c.port = hp.port
        c.path = "/cgi-bin/api.cgi"
        c.percentEncodedQueryItems = [
            URLQueryItem(name: "cmd", value: enc(cmd)),
            URLQueryItem(name: "channel", value: String(channel)),
            URLQueryItem(name: "rs", value: String(Int.random(in: 100000...999999))),
            URLQueryItem(name: "user", value: enc(username)),
            URLQueryItem(name: "password", value: enc(password))
        ]
        return c.url
    }

    private static let pathStyles = ["Preview_%02d_%@", "h265Preview_%02d_%@", "h264Preview_%02d_%@"]

    private func rtspURL(channel: Int, main: Bool) -> String? {
        guard let hp = hostParts else { return nil }
        let style = Self.pathStyles[(pathVariant[channel] ?? 0) % Self.pathStyles.count]
        let path = String(format: style, channel + 1, main ? "main" : "sub")
        return "rtsp://\(enc(username)):\(enc(password))@\(hp.host):554/\(path)"
    }

    private func isFresh(_ key: StreamKey) -> Bool {
        guard streams[key] != nil, let t = frameAt[key] else { return false }
        return Date().timeIntervalSince(t) < 2
    }

    func isLive(_ channel: Int) -> Bool {
        isFresh(StreamKey(channel: channel, main: true)) || isFresh(StreamKey(channel: channel, main: false))
    }

    // MARK: - Snapshots

    func fetchSnapshot(channel: Int) async {
        guard let u = url(cmd: "Snap", channel: channel) else { return }
        do {
            let (data, _) = try await session.data(from: u)
            if let image = NSImage(data: data) {
                if !isLive(channel) { images[channel] = image }
                lastUpdate = Date()
                lastError = nil
            } else {
                lastError = "NVR refused the login"
            }
        } catch {
            if !(error is CancellationError) {
                lastError = "Can't reach the NVR"
            }
        }
    }

    func testConnection() async -> String {
        guard isConfigured else { return "Fill in the address, username and password first." }
        guard let u = url(cmd: "Snap", channel: 0) else { return "That address doesn't look right." }
        do {
            let (data, _) = try await session.data(from: u)
            if NSImage(data: data) != nil { return "Connected" }
            return "The NVR answered but refused the login. Check the username and password."
        } catch {
            return "Couldn't reach \(host). Check the address and that you're on your home network."
        }
    }

    // MARK: - Camera overlays (the date/time and name burned into the picture)

    private func apiPost(_ cmd: String, param: [String: Any]) async -> [String: Any]? {
        guard let hp = hostParts else { return nil }
        var c = URLComponents()
        c.scheme = "http"
        c.host = hp.host
        c.port = hp.port
        c.path = "/cgi-bin/api.cgi"
        c.percentEncodedQueryItems = [
            URLQueryItem(name: "cmd", value: enc(cmd)),
            URLQueryItem(name: "user", value: enc(username)),
            URLQueryItem(name: "password", value: enc(password))
        ]
        guard let u = c.url else { return nil }
        var request = URLRequest(url: u)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [[String: Any]] = [["cmd": cmd, "action": cmd.hasPrefix("Get") ? 1 : 0, "param": param]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let result = try? await session.data(for: request),
              let arr = try? JSONSerialization.jsonObject(with: result.0) as? [[String: Any]] else { return nil }
        return arr.first
    }

    /// Turns the cameras' own date/time and name overlays on or off. Needs an NVR login that may change settings.
    func applyOverlays() async -> String {
        guard isConfigured else { return "Set up the NVR connection first." }
        var changed = 0
        var failed = 0
        for cam in cameras {
            guard let got = await apiPost("GetOsd", param: ["channel": cam.channel]),
                  (got["code"] as? Int) == 0,
                  let value = got["value"] as? [String: Any],
                  var osd = value["Osd"] as? [String: Any] else {
                failed += 1
                continue
            }
            if var t = osd["osdTime"] as? [String: Any] {
                t["enable"] = osdTime ? 1 : 0
                osd["osdTime"] = t
            }
            if var n = osd["osdChannel"] as? [String: Any] {
                n["enable"] = osdName ? 1 : 0
                osd["osdChannel"] = n
            }
            osd["channel"] = cam.channel
            if let set = await apiPost("SetOsd", param: ["Osd": osd]), (set["code"] as? Int) == 0 {
                changed += 1
            } else {
                failed += 1
            }
        }
        if failed == 0 { return "Updated all \(changed) cameras." }
        if changed == 0 {
            return "The NVR didn't allow this change. Your login may be view-only: use an admin login, or change it in the Reolink app under Display › OSD."
        }
        return "Updated \(changed) cameras; \(failed) couldn't be changed."
    }

    // MARK: - Detection monitor (runs all the time)

    private func restartMonitor() {
        monitorTask?.cancel()
        guard isConfigured else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let cams = self.cameras
                await withTaskGroup(of: Void.self) { group in
                    for cam in cams {
                        group.addTask { await self.pollDetections(channel: cam.channel) }
                    }
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func pollDetections(channel: Int) async {
        var current: Set<DetectionEvent.Kind>?
        if aiSupported[channel] != false, let u = url(cmd: "GetAiState", channel: channel) {
            guard let result = try? await session.data(from: u) else { return }
            if let parsed = Self.parseAiState(result.0) {
                aiSupported[channel] = true
                current = parsed
            } else {
                aiSupported[channel] = false
            }
        }
        if current == nil {
            guard let u = url(cmd: "GetMdState", channel: channel),
                  let result = try? await session.data(from: u),
                  let moving = Self.parseMdState(result.0) else { return }
            current = moving ? [.motion] : []
        }
        guard let now = current else { return }
        let before = activeKinds[channel] ?? []
        activeKinds[channel] = now
        motion[channel] = !now.isEmpty
        // Only count it as new if that kind of detection had been quiet for 90 seconds,
        // so a parked car or swaying tree flickering on and off doesn't flood the feed.
        let stamp = Date()
        var fresh: [DetectionEvent.Kind] = []
        for kind in now.subtracting(before) {
            let key = "\(channel)-\(kind.rawValue)"
            if let seen = lastActiveAt[key], stamp.timeIntervalSince(seen) < 90 { continue }
            fresh.append(kind)
        }
        for kind in now { lastActiveAt["\(channel)-\(kind.rawValue)"] = stamp }
        for kind in fresh {
            await recordEvent(channel: channel, kind: kind)
        }
    }

    nonisolated static func parseAiState(_ data: Data) -> Set<DetectionEvent.Kind>? {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = arr.first,
              (first["code"] as? Int) == 0,
              let value = first["value"] as? [String: Any] else { return nil }
        var found = false
        var kinds = Set<DetectionEvent.Kind>()
        let keys: [(String, DetectionEvent.Kind)] = [("people", .person), ("vehicle", .vehicle), ("dog_cat", .animal)]
        for (key, kind) in keys {
            if let obj = value[key] as? [String: Any], let state = obj["alarm_state"] as? Int {
                found = true
                if state == 1 { kinds.insert(kind) }
            }
        }
        return found ? kinds : nil
    }

    nonisolated static func parseMdState(_ data: Data) -> Bool? {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let value = arr.first?["value"] as? [String: Any],
              let state = value["state"] as? Int else { return nil }
        return state == 1
    }

    private func recordEvent(channel: Int, kind: DetectionEvent.Kind) async {
        let key = "\(channel)-\(kind.rawValue)"
        if let last = lastEventAt[key], Date().timeIntervalSince(last) < 45 { return }
        lastEventAt[key] = Date()

        let event = DetectionEvent(id: UUID(), channel: channel, kind: kind, date: Date())
        var image: NSImage?
        if let u = url(cmd: "Snap", channel: channel),
           let result = try? await session.data(from: u),
           let img = NSImage(data: result.0) {
            image = img
            eventImageCache[event.id] = img
            EventLog.saveImage(result.0, for: event.id)
        }
        events.insert(event, at: 0)
        if events.count > 500 { events.removeLast(events.count - 500) }
        EventLog.save(events)
        unseen += 1

        if shouldAlert(kind) {
            WindowManager.shared.showAlert(event: event, image: image)
        }
    }

    // MARK: - Visibility

    func setPanelVisible(_ visible: Bool) {
        panelOpen = visible
        restartPanelPolling()
    }

    func setViewerVisible(_ visible: Bool) {
        viewerOpen = visible
        restartLivePolling()
    }

    func setMiniVisible(_ visible: Bool) {
        miniOpen = visible
        restartLivePolling()
    }

    private func restartPanelPolling() {
        panelTask?.cancel()
        guard panelOpen, isConfigured else { return }
        panelTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let cams = self.cameras
                await withTaskGroup(of: Void.self) { group in
                    for cam in cams {
                        group.addTask { await self.fetchSnapshot(channel: cam.channel) }
                    }
                }
                try? await Task.sleep(nanoseconds: UInt64(self.panelInterval * 1_000_000_000))
            }
        }
    }

    /// Channels currently on screen in the viewer and/or mini player.
    private var visibleChannels: [Int] {
        var list: [Int] = []
        if viewerOpen {
            list += showGrid ? cameras.map(\.channel) : [selected]
        }
        if miniOpen && !list.contains(miniChannel) { list.append(miniChannel) }
        return list
    }

    private func restartLivePolling() {
        liveTask?.cancel()
        updateStreams()
        guard viewerOpen || miniOpen, isConfigured else { return }
        liveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.checkForStalledStreams()
                // Fill in with snapshots wherever live video isn't (yet) arriving.
                let needSnapshots = self.visibleChannels.filter { !self.isLive($0) }
                if !needSnapshots.isEmpty {
                    await withTaskGroup(of: Void.self) { group in
                        for ch in needSnapshots {
                            group.addTask { await self.fetchSnapshot(channel: ch) }
                        }
                    }
                }
                try? await Task.sleep(nanoseconds: needSnapshots.isEmpty ? 1_000_000_000 : 300_000_000)
            }
        }
    }

    private func checkForStalledStreams() {
        let now = Date()
        for stream in streams.values {
            let since = stream.lastFrame ?? stream.startedAt
            if now.timeIntervalSince(since) > 10 {
                stream.stop()   // its exit handler restarts it
            }
        }
    }

    // MARK: - Live video

    /// While the viewer is open every camera's light sub stream keeps running so switching is instant;
    /// the camera you're looking at also gets its full-quality main stream. The mini player uses a sub stream.
    private func updateStreams() {
        // width 0 = the camera's own resolution
        var wanted: [StreamKey: (width: Int, fps: Int)] = [:]
        if isConfigured && liveVideoAvailable {
            if viewerOpen {
                for cam in cameras { wanted[StreamKey(channel: cam.channel, main: false)] = (0, 15) }
                if showGrid {
                    if gridQuality != .low {
                        for cam in gridCameras {
                            wanted[StreamKey(channel: cam.channel, main: true)] = (gridQuality == .best ? 0 : 1280, 15)
                        }
                    }
                } else if previewEvent == nil && singleQuality != .low {
                    wanted[StreamKey(channel: selected, main: true)] = singleQuality == .best ? (0, 15) : (1920, 20)
                }
            }
            if miniOpen {
                let key = StreamKey(channel: miniChannel, main: false)
                if wanted[key] == nil { wanted[key] = (0, 15) }
            }
        }
        for (key, stream) in Array(streams) {
            if let want = wanted[key], want.width == stream.width { continue }
            stream.stop()
            streams[key] = nil
            frameAt[key] = nil
        }
        for (key, want) in wanted where streams[key] == nil {
            guard let url = rtspURL(channel: key.channel, main: key.main) else { continue }
            let k = key
            let streamID = UUID()
            let stream = LiveStream(
                id: streamID,
                url: url, isMain: key.main,
                width: want.width,
                fps: want.fps,
                onFrame: { [weak self] image in
                    self?.receive(image, from: k)
                },
                onExit: { [weak self] gotFrames in
                    self?.streamEnded(key: k, id: streamID, gotFrames: gotFrames)
                })
            streams[key] = stream
            stream.start()
        }
    }

    private func receive(_ image: NSImage, from key: StreamKey) {
        frameAt[key] = Date()
        if !key.main && isFresh(StreamKey(channel: key.channel, main: true)) { return }
        images[key.channel] = image
        lastUpdate = Date()
        lastError = nil
    }

    private func streamEnded(key: StreamKey, id: UUID, gotFrames: Bool) {
        guard streams[key]?.id == id else { return }
        streams[key] = nil
        frameAt[key] = nil
        if !gotFrames && !key.main { pathVariant[key.channel, default: 0] += 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            Task { @MainActor in self?.updateStreams() }
        }
    }
}
