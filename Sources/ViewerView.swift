import SwiftUI
import AppKit

/// The camera window: edge-to-edge video, controls on floating glass that fade when the mouse is still.
struct ViewerView: View {
    @EnvironmentObject var store: CameraStore
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var controlsVisible = true
    @State private var hoveringControls = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                content(size: geo.size)
                offlineBanner
                controls(size: geo.size)
                    .opacity(controlsVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.25), value: controlsVisible)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .frame(minWidth: 420, minHeight: 260)
        .preferredColorScheme(.dark)
        .background(shortcuts)
        .onContinuousHover { _ in poke() }
        .onAppear { poke() }
        .onChange(of: store.selected) { _ in resetZoom() }
        .onChange(of: store.showGrid) { _ in resetZoom() }
    }

    private var currentName: String { store.name(for: store.selected) }

    /// Says so plainly when the cameras can't be reached, instead of showing old pictures as if they were live.
    private var offlineBanner: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let since = store.offlineSince, context.date.timeIntervalSince(since) > 5 {
                let last = (store.lastUpdate ?? since).formatted(date: .omitted, time: .shortened)
                HStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark")
                        .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.30))
                    Text("Can't reach your cameras. Showing pictures from \(last). Trying again…")
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .glass(10)
                .padding(.top, 62)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(size: CGSize) -> some View {
        if store.showGrid {
            grid(size: size)
        } else if let event = store.previewEvent {
            eventPreview(event, size: size)
        } else {
            liveFeed(size: size)
        }
    }

    private func liveFeed(size: CGSize) -> some View {
        CameraTile(camera: Camera(channel: store.selected, name: currentName),
                   image: store.images[store.selected],
                   cornerRadius: 0,
                   fill: store.fills(store.selected),
                   blurBackground: true,
                   showLabel: false,
                   rotation: store.rotation(for: store.selected),
                   zoom: zoom,
                   pan: pan)
            .frame(width: size.width, height: size.height)
            .overlay(
                ZoomCatcher(
                    isZoomed: zoom > 1.01,
                    onZoom: { factor, point in applyZoom(factor, at: point, in: size) },
                    onDrag: { delta in
                        pan = clamp(CGSize(width: pan.width + delta.width, height: pan.height + delta.height),
                                    size: size, zoom: zoom)
                    },
                    onDoubleClick: { withAnimation(.easeOut(duration: 0.2)) { resetZoom() } },
                    onMove: { poke() }
                )
            )
    }

    private func eventPreview(_ event: DetectionEvent, size: CGSize) -> some View {
        ZStack {
            if let img = store.image(for: event) {
                CameraTile(camera: Camera(channel: event.channel, name: store.name(for: event.channel)),
                           image: img,
                           cornerRadius: 0,
                           fill: false,
                           blurBackground: true,
                           showLabel: false,
                           rotation: store.rotation(for: event.channel))
            } else {
                Text("No snapshot was saved for this event")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - Grid

    private func bestColumns(for count: Int, in size: CGSize, spacing: CGFloat) -> Int {
        guard count > 0, size.width > 0, size.height > 0 else { return 1 }
        let aspect: CGFloat = 16.0 / 9.0
        var best = 1
        var bestArea: CGFloat = 0
        for cols in 1...count {
            let rows = Int((Double(count) / Double(cols)).rounded(.up))
            let cellW = (size.width - CGFloat(cols - 1) * spacing) / CGFloat(cols)
            let cellH = (size.height - CGFloat(rows - 1) * spacing) / CGFloat(rows)
            guard cellW > 0, cellH > 0 else { continue }
            let picW = min(cellW, cellH * aspect)
            let area = picW * (picW / aspect)
            if area > bestArea + 0.5 {
                bestArea = area
                best = cols
            }
        }
        return best
    }

    @ViewBuilder
    private func grid(size: CGSize) -> some View {
        let gap = CGFloat(store.gridSpacing)
        let pad: CGFloat = gap > 4 ? gap : 0
        let inner = CGSize(width: max(size.width - pad * 2, 0), height: max(size.height - pad * 2, 0))
        let radius: CGFloat = pad > 0 ? 10 : 0
        let cams = store.gridCameras
        Group {
            if cams.isEmpty {
                Text("No cameras are set to show here. Choose some in Settings › All cameras.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: inner.width, height: inner.height)
            } else if store.gridLayout == .focus && cams.count > 1 {
                focusGrid(cams: cams, size: inner, gap: gap, radius: radius)
            } else {
                uniformGrid(cams: cams, cols: columns(for: cams.count, in: inner, gap: gap),
                            size: inner, gap: gap, radius: radius)
            }
        }
        .padding(pad)
        .frame(width: size.width, height: size.height)
    }

    private func columns(for count: Int, in size: CGSize, gap: CGFloat) -> Int {
        switch store.gridLayout {
        case .grid: return max(Int(Double(count).squareRoot().rounded(.up)), 1)
        case .row: return max(count, 1)
        case .column: return 1
        case .auto, .focus: return bestColumns(for: count, in: size, spacing: gap)
        }
    }

    private func uniformGrid(cams: [Camera], cols: Int, size: CGSize, gap: CGFloat, radius: CGFloat) -> some View {
        let rows = max(Int((Double(cams.count) / Double(cols)).rounded(.up)), 1)
        let cellW = max((size.width - CGFloat(cols - 1) * gap) / CGFloat(cols), 0)
        let cellH = max((size.height - CGFloat(rows - 1) * gap) / CGFloat(rows), 0)
        return VStack(spacing: gap) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0..<cols, id: \.self) { col in
                        let index = row * cols + col
                        if index < cams.count {
                            tile(cams[index], width: cellW, height: cellH, radius: radius)
                        } else {
                            Color.clear.frame(width: cellW, height: cellH)
                        }
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// The chosen camera large on the left, the others stacked on the right.
    private func focusGrid(cams: [Camera], size: CGSize, gap: CGFloat, radius: CGFloat) -> some View {
        let main = cams.first(where: { $0.channel == store.focusChannel }) ?? cams[0]
        let others = cams.filter { $0.channel != main.channel }
        let sideW = max(size.width * 0.25, 0)
        let mainW = max(size.width - sideW - gap, 0)
        let sideH = max((size.height - CGFloat(max(others.count - 1, 0)) * gap) / CGFloat(max(others.count, 1)), 0)
        return HStack(spacing: gap) {
            tile(main, width: mainW, height: size.height, radius: radius)
            VStack(spacing: gap) {
                ForEach(others) { cam in
                    tile(cam, width: sideW, height: sideH, radius: radius)
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func tile(_ cam: Camera, width: CGFloat, height: CGFloat, radius: CGFloat) -> some View {
        Button { focus(cam.channel) } label: {
            CameraTile(camera: cam,
                       image: store.images[cam.channel],
                       badge: store.gridShowBadges ? store.recentBadge(channel: cam.channel) : nil,
                       cornerRadius: radius,
                       fill: store.fills(cam.channel),
                       blurBackground: true,
                       showLabel: store.gridShowNames,
                       active: store.motion[cam.channel] ?? false,
                       rotation: store.rotation(for: cam.channel))
                .frame(width: width, height: height)
        }
        .buttonStyle(.plain)
        .help("Open \(cam.name). Right-click for options.")
        .contextMenu {
            Button("Fill the frame") { store.setFill(cam.channel, true) }
            Button("Show the whole picture") { store.setFill(cam.channel, false) }
            if store.fitOverrides[cam.channel] != nil {
                Button("Use the default") { store.setFill(cam.channel, nil) }
            }
            Divider()
            Button("Rotate 90°") { store.rotate(cam.channel) }
            Button("Open in mini player") { WindowManager.shared.showMini(channel: cam.channel) }
        }
    }

    // MARK: - Controls

    private func controls(size: CGSize) -> some View {
        let compact = size.width < max(860, CGFloat(store.cameras.count) * 140 + 260)
        return VStack(spacing: 0) {
            ZStack(alignment: .top) {
                switcher(compact: compact)
                    .frame(maxWidth: .infinity, alignment: compact ? .trailing : .center)
                    .padding(.trailing, compact ? 150 : 0)
                rightButtons
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.top, 10)
            .padding(.horizontal, 12)
            .padding(.leading, compact ? 70 : 0)
            .onHover { hoveringControls = $0 }

            if let event = store.previewEvent, !store.showGrid {
                previewBar(event)
                    .padding(.top, 10)
            }

            Spacer(minLength: 0)

            if !store.showGrid {
                VStack(spacing: 10) {
                    if store.previewEvent == nil {
                        hud(size: size, compact: compact)
                    }
                    if !compact {
                        timeline
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .onHover { hoveringControls = $0 }
            }
        }
        .allowsHitTesting(controlsVisible)
    }

    private func switcher(compact: Bool) -> some View {
        HStack(spacing: 2) {
            pill(title: "All", key: nil, on: store.showGrid, active: false) {
                store.previewEvent = nil
                store.showGrid = true
            }
            ForEach(store.gridCameras) { cam in
                pill(title: compact ? cam.key : cam.name,
                     key: compact ? nil : cam.key,
                     on: !store.showGrid && store.selected == cam.channel,
                     active: store.motion[cam.channel] ?? false) {
                    focus(cam.channel)
                }
            }
        }
        .padding(5)
        .glass(17)
    }

    private func pill(title: String, key: String?, on: Bool, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if active {
                    Circle().fill(DetectionEvent.Kind.person.color).frame(width: 7, height: 7)
                }
                Text(title).font(.system(size: 15, weight: .semibold))
                if let key {
                    Text(key).font(.system(size: 12, weight: .medium)).opacity(0.5)
                }
            }
            .foregroundStyle(on ? Color(white: 0.07) : Color.white)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(on ? Color.white.opacity(0.92) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var rightButtons: some View {
        HStack(spacing: 2) {
            if store.showGrid {
                Menu {
                    Picker("Layout", selection: $store.gridLayout) {
                        ForEach(GridLayout.allCases) { layout in
                            Text(layout.label).tag(layout)
                        }
                    }
                    .pickerStyle(.inline)
                    if store.gridLayout == .focus {
                        Picker("Large camera", selection: $store.focusChannel) {
                            ForEach(store.gridCameras) { cam in
                                Text(cam.name).tag(cam.channel)
                            }
                        }
                    }
                    Picker("Spacing", selection: $store.gridSpacing) {
                        Text("None").tag(0.0)
                        Text("Thin").tag(2.0)
                        Text("Roomy").tag(10.0)
                    }
                    Divider()
                    Toggle("Show camera names", isOn: $store.gridShowNames)
                    Toggle("Show detections", isOn: $store.gridShowBadges)
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Layout")
                IconButton(symbol: store.fillTiles ? "rectangle.fill" : "rectangle",
                           help: store.fillTiles ? "Default: fill. Click to show whole pictures (F). Right-click a camera to set it on its own."
                                                 : "Default: whole picture. Click to crop to fill (F). Right-click a camera to set it on its own.") {
                    store.fillTiles.toggle()
                }
            }
            IconButton(symbol: "pip.enter", help: "Mini player (M)") {
                WindowManager.shared.showMini(channel: store.selected)
            }
            IconButton(symbol: store.pinned ? "pin.fill" : "pin", active: store.pinned, help: "Keep on top (P)") {
                store.pinned.toggle()
            }
        }
        .padding(4)
        .glass(14)
    }

    private func hud(size: CGSize, compact: Bool) -> some View {
        HStack(spacing: 2) {
            HStack(spacing: 7) {
                Circle()
                    .fill(store.isLive(store.selected) ? liveRed : Color.gray)
                    .frame(width: 8, height: 8)
                Text(store.isLive(store.selected) ? "LIVE" : (store.liveVideoAvailable ? "CONNECTING" : "SNAPSHOTS"))
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.6)
                if !compact {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(context.date.formatted(date: .omitted, time: .standard))
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 4)

            Menu {
                Picker("Quality", selection: $store.singleQuality) {
                    ForEach(StreamQuality.allCases) { q in
                        Text(q.label).tag(q)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Text(store.singleQuality.short)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Video quality")
            .padding(.trailing, 4)

            divider
            IconButton(symbol: "minus", help: "Zoom out") {
                withAnimation(.easeOut(duration: 0.15)) {
                    applyZoom(1 / 1.5, at: CGPoint(x: size.width / 2, y: size.height / 2), in: size)
                }
            }
            Text(String(format: "%.1f×", zoom))
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .frame(width: 38)
            IconButton(symbol: "plus", help: "Zoom in (scroll wheel)") {
                withAnimation(.easeOut(duration: 0.15)) {
                    applyZoom(1.5, at: CGPoint(x: size.width / 2, y: size.height / 2), in: size)
                }
            }
            divider
            IconButton(symbol: store.fills(store.selected) ? "rectangle.fill" : "rectangle",
                       help: store.fills(store.selected) ? "Show this camera's whole picture (F)" : "Crop this camera to fill (F)") {
                store.setFill(store.selected, !store.fills(store.selected))
            }
            IconButton(symbol: "rotate.left", help: "Rotate (R)") { store.rotate(store.selected) }
            IconButton(symbol: "camera", help: "Save snapshot (S)") { saveSnapshot() }
            IconButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Full screen") {
                WindowManager.shared.toggleViewerFullScreen()
            }
        }
        .padding(4)
        .glass(18)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.16))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 4)
    }

    private func previewBar(_ event: DetectionEvent) -> some View {
        HStack(spacing: 10) {
            Image(systemName: event.kind.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(event.kind.color)
            Text("\(event.kind.label) · \(event.date.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 13, weight: .semibold))
            Button("Back to live") { store.previewEvent = nil }
                .buttonStyle(PillButtonStyle(prominent: true))
        }
        .padding(.leading, 14)
        .padding(4)
        .glass(14)
    }

    /// Today's detections for this camera; click a mark to see its snapshot.
    private var timeline: some View {
        let todays = store.eventsToday(channel: store.selected)
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return HStack(spacing: 12) {
            Text("Today")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14)).frame(width: w, height: 2)
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        let f = CGFloat(min(max(context.date.timeIntervalSince(startOfDay) / 86400, 0), 1))
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.32)).frame(width: w * f, height: 2)
                            Capsule().fill(Color.white).frame(width: 2, height: 18).offset(x: w * f - 1)
                        }
                    }
                    ForEach(todays) { ev in
                        let f = CGFloat(min(max(ev.date.timeIntervalSince(startOfDay) / 86400, 0), 1))
                        Button { store.previewEvent = ev } label: {
                            Capsule()
                                .fill(ev.kind.color)
                                .frame(width: 4, height: 14)
                                .padding(.horizontal, 3)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("\(ev.kind.label) · \(ev.date.formatted(date: .omitted, time: .shortened))")
                        .offset(x: w * f - 5)
                    }
                }
                .frame(width: w, height: g.size.height)
            }
            .frame(height: 22)
            if todays.isEmpty {
                Text("No activity yet")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    if todays.contains(where: { $0.kind == .doorbell }) { legend(.doorbell) }
                    legend(.person)
                    legend(.vehicle)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .glass(12)
    }

    private func legend(_ kind: DetectionEvent.Kind) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(kind.color).frame(width: 8, height: 8)
            Text(kind.plural)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    // MARK: - Behaviour

    /// Show the controls, then fade them out after the mouse has been still for a moment.
    private func poke() {
        if !controlsVisible { controlsVisible = true }
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if !Task.isCancelled && !hoveringControls {
                controlsVisible = false
            }
        }
    }

    private func applyZoom(_ factor: CGFloat, at point: CGPoint, in size: CGSize) {
        let newZoom = min(max(zoom * factor, 1), 8)
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let d = CGSize(width: point.x - centre.x, height: point.y - centre.y)
        let k = newZoom / zoom
        let proposed = CGSize(width: d.width - k * (d.width - pan.width),
                              height: d.height - k * (d.height - pan.height))
        zoom = newZoom
        pan = clamp(proposed, size: size, zoom: newZoom)
    }

    private func clamp(_ o: CGSize, size: CGSize, zoom: CGFloat) -> CGSize {
        let maxX = (zoom - 1) * size.width / 2
        let maxY = (zoom - 1) * size.height / 2
        return CGSize(width: min(max(o.width, -maxX), maxX), height: min(max(o.height, -maxY), maxY))
    }

    private func resetZoom() {
        zoom = 1
        pan = .zero
    }

    private func focus(_ channel: Int) {
        store.previewEvent = nil
        store.selected = channel
        store.showGrid = false
    }

    /// Invisible buttons so the keyboard shortcuts work.
    private var shortcuts: some View {
        ZStack {
            ForEach(store.cameras.filter { $0.channel < 9 }) { cam in
                Button("") { focus(cam.channel) }
                    .keyboardShortcut(KeyEquivalent(Character(cam.key)), modifiers: [])
            }
            Button("") { store.previewEvent = nil; store.showGrid.toggle() }
                .keyboardShortcut("g", modifiers: [])
            Button("") {
                if store.showGrid {
                    store.fillTiles.toggle()
                } else {
                    store.setFill(store.selected, !store.fills(store.selected))
                }
            }
            .keyboardShortcut("f", modifiers: [])
            Button("") { store.pinned.toggle() }
                .keyboardShortcut("p", modifiers: [])
            Button("") { if !store.showGrid { store.rotate(store.selected) } }
                .keyboardShortcut("r", modifiers: [])
            Button("") { if !store.showGrid { saveSnapshot() } }
                .keyboardShortcut("s", modifiers: [])
            Button("") { WindowManager.shared.showMini(channel: store.selected) }
                .keyboardShortcut("m", modifiers: [])
            Button("") { withAnimation(.easeOut(duration: 0.2)) { resetZoom() } }
                .keyboardShortcut("0", modifiers: [])
            Button("") {
                if store.previewEvent != nil {
                    store.previewEvent = nil
                } else {
                    WindowManager.shared.closeViewer()
                }
            }
            .keyboardShortcut(.cancelAction)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    private func saveSnapshot() {
        guard let image = store.images[store.selected],
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else { return }
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
        let folder = pictures.appendingPathComponent("Perch", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let file = folder.appendingPathComponent("\(currentName) \(formatter.string(from: Date())).jpg")
        do {
            try jpeg.write(to: file)
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } catch {
            NSSound.beep()
        }
    }
}
