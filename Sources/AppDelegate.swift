import AppKit
import CoreServices

/// Handles opening Perch from the Dock, Finder or Launchpad.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let store = WindowManager.shared.store,
              store.isConfigured,
              store.openViewerOnLaunch,
              !launchedAsLoginItem else { return }
        WindowManager.shared.showViewer(grid: true)
    }

    /// Clicking Perch in the Dock (or opening it again) while it's running.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        WindowManager.shared.showViewer(grid: WindowManager.shared.hasViewer ? nil : true)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Started automatically at login, so stay quietly in the menu bar.
    private var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication) else { return false }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }
}
