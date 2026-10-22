import SwiftUI
import AppKit

/// The panel that drops down from the menu bar icon: cameras at a glance plus recent activity.
struct PanelView: View {
    @EnvironmentObject var store: CameraStore
    @Environment(\.openWindow) private var openWindow
    @State private var filter = "All"

    private var columns: [GridItem] {
        let count = store.cameras.count > 4 ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 6), count: count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if store.isConfigured {
                tiles
                activity
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "video.badge.plus")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Add your NVR to get started").font(.system(size: 13, weight: .medium))
                    Button("Open settings") { openSettings() }
                        .buttonStyle(PillButtonStyle(prominent: true))
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            }
            footer
        }
        .padding(14)
        .frame(width: 500)
        .preferredColorScheme(.dark)
        .onAppear {
            store.setPanelVisible(true)
            store.unseen = 0
        }
        .onDisappear { store.setPanelVisible(false) }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Home").font(.system(size: 16, weight: .semibold))
                statusLine
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                if store.isSnoozed {
                    Button("Turn alerts back on") { store.unsnooze() }
                } else {
                    Button("Snooze alerts for 1 hour") { store.snooze(hours: 1) }
                    Button("Snooze alerts for 4 hours") { store.snooze(hours: 4) }
                }
            } label: {
                Image(systemName: store.isSnoozed ? "bell.slash.fill" : "bell")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(store.isSnoozed ? DetectionEvent.Kind.person.color : Color.white)
                    .frame(width: 32, height: 32)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .help(store.isSnoozed ? "Alerts are snoozed" : "Snooze alerts")

            Button { openSettings() } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if !store.isConfigured {
            Text("Not set up yet")
        } else if let error = store.lastError {
            Text(error).foregroundStyle(DetectionEvent.Kind.person.color)
        } else if store.isSnoozed, let until = store.snoozedUntil {
            Text("Alerts snoozed until \(until.formatted(date: .omitted, time: .shortened))")
        } else if let last = store.events.first {
            Text("\(store.cameras.count) cameras · last activity ") + Text(last.date, style: .relative) + Text(" ago")
        } else {
            Text("\(store.cameras.count) cameras · all quiet")
        }
    }

    // MARK: Tiles

    private var tiles: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(store.gridCameras) { cam in
                Button {
                    WindowManager.shared.showViewer(channel: cam.channel, grid: false)
                } label: {
                    CameraTile(camera: cam,
                               image: store.images[cam.channel],
                               badge: store.recentBadge(channel: cam.channel),
                               cornerRadius: 8,
                               aspect: 16.0 / 9.0,
                               fill: true,
                               compactLabel: true,
                               active: store.motion[cam.channel] ?? false,
                               rotation: store.rotation(for: cam.channel))
                }
                .buttonStyle(.plain)
                .help("Open \(cam.name)")
            }
        }
    }

    // MARK: Activity

    private var filtered: [DetectionEvent] {
        switch filter {
        case "People": return store.events.filter { $0.kind == .person }
        case "Vehicles": return store.events.filter { $0.kind == .vehicle }
        case "Doorbell": return store.events.filter { $0.kind == .doorbell }
        default: return store.events
        }
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Activity").font(.system(size: 13, weight: .semibold))
                Spacer()
                Picker("Show", selection: $filter) {
                    Text("All").tag("All")
                    Text("People").tag("People")
                    Text("Vehicles").tag("Vehicles")
                    if !store.doorbellChannels.isEmpty || store.events.contains(where: { $0.kind == .doorbell }) {
                        Text("Doorbell").tag("Doorbell")
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: store.doorbellChannels.isEmpty ? 200 : 270)
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 4)

            let list = Array(filtered.prefix(4))
            if list.isEmpty {
                Text(filter == "Doorbell" ? "No one has rung the doorbell yet." : "Nothing yet. People and vehicles your cameras spot will appear here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 2)
            } else {
                ForEach(list) { ev in
                    row(ev)
                }
            }
        }
    }

    private func row(_ ev: DetectionEvent) -> some View {
        Button {
            WindowManager.shared.showViewer(channel: ev.channel, grid: false)
            store.previewEvent = ev
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Color(white: 0.12)
                    if let img = store.image(for: ev) {
                        Image(nsImage: img).resizable().scaledToFill()
                    }
                }
                .frame(width: 64, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Circle().fill(ev.kind.color).frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(ev.kind.title(at: store.name(for: ev.channel)))
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text("\(store.name(for: ev.channel)) · \(ev.date.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                (Text(ev.date, style: .relative) + Text(" ago"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Open viewer") { WindowManager.shared.showViewer(grid: true) }
                .buttonStyle(PillButtonStyle(prominent: true))
                .disabled(!store.isConfigured)
            Button {
                WindowManager.shared.showMini(channel: store.selected)
            } label: {
                Label("Mini player", systemImage: "pip.enter")
            }
            .buttonStyle(PillButtonStyle(prominent: false))
            .disabled(!store.isConfigured)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
        }
    }

    private func openSettings() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }
}
