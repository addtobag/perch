import SwiftUI
import AppKit

@main
struct PerchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: CameraStore

    init() {
        // Perch is always dark, including the menu bar panel.
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        let s = CameraStore()
        _store = StateObject(wrappedValue: s)
        WindowManager.shared.store = s
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environmentObject(store)
        } label: {
            MenuBarLabel(unseen: store.unseen)
        }
        .menuBarExtraStyle(.window)

        Window("Perch Settings", id: "settings") {
            SettingsView()
                .environmentObject(store)
        }
        .windowResizability(.contentSize)
    }
}

/// The menu bar icon, with a count of new detections since the panel was last opened.
struct MenuBarLabel: View {
    let unseen: Int

    static let icon: NSImage? = {
        guard let image = NSImage(named: "MenuBarIcon") else { return nil }
        image.isTemplate = true
        return image
    }()

    var body: some View {
        if unseen > 0 {
            HStack(spacing: 3) {
                glyph
                Text("\(unseen)")
            }
        } else {
            glyph
        }
    }

    @ViewBuilder
    private var glyph: some View {
        if let icon = Self.icon {
            Image(nsImage: icon)
        } else {
            Image(systemName: "video.fill")
        }
    }
}
