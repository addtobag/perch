import SwiftUI
import AppKit
import Combine

/// A panel that can take clicks without needing a title bar.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Owns the camera window, the floating mini player and the alert card.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    weak var store: CameraStore? {
        didSet { observe() }
    }

    private var viewer: NSWindow?
    private var mini: NSPanel?
    private var alert: NSPanel?
    private var alertHide: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    private func observe() {
        cancellables.removeAll()
        store?.$pinned
            .sink { [weak self] value in self?.applyPin(value) }
            .store(in: &cancellables)
    }

    // MARK: Camera window

    var hasViewer: Bool { viewer != nil }

    func showViewer(channel: Int? = nil, grid: Bool? = nil) {
        guard let store else { return }
        // Behave like a normal app (Dock, ⌘-Tab) while the camera window is open.
        NSApp.setActivationPolicy(.regular)
        if let channel { store.selected = channel }
        if let grid { store.showGrid = grid }
        if viewer == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 720),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Perch"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.isMovableByWindowBackground = true
            w.backgroundColor = .black
            w.minSize = NSSize(width: 420, height: 260)
            w.contentView = NSHostingView(rootView: AnyView(ViewerView().environmentObject(store)))
            w.delegate = self
            if !w.setFrameUsingName("PerchViewerWindow") { w.center() }
            w.setFrameAutosaveName("PerchViewerWindow")
            viewer = w
        }
        applyPin(store.pinned)
        viewer?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        store.setViewerVisible(true)
    }

    func toggleViewerFullScreen() {
        store?.pinned = false
        viewer?.toggleFullScreen(nil)
    }

    func closeViewer() { viewer?.close() }

    private func applyPin(_ pinned: Bool) {
        guard let w = viewer else { return }
        w.level = pinned ? .floating : .normal
        if pinned {
            w.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
        } else {
            w.collectionBehavior.remove([.canJoinAllSpaces, .fullScreenAuxiliary])
        }
    }

    // MARK: Mini player

    func showMini(channel: Int) {
        guard let store else { return }
        store.miniChannel = channel
        if mini == nil {
            let p = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 248),
                                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
            p.title = "Mini player"
            p.titlebarAppearsTransparent = true
            p.titleVisibility = .hidden
            p.standardWindowButton(.closeButton)?.isHidden = true
            p.standardWindowButton(.miniaturizeButton)?.isHidden = true
            p.standardWindowButton(.zoomButton)?.isHidden = true
            p.isFloatingPanel = true
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.hidesOnDeactivate = false
            p.isMovableByWindowBackground = true
            p.isReleasedWhenClosed = false
            p.backgroundColor = .black
            p.contentAspectRatio = NSSize(width: 16, height: 9)
            p.minSize = NSSize(width: 280, height: 158)
            p.contentView = NSHostingView(rootView: AnyView(MiniPlayerView().environmentObject(store)))
            p.delegate = self
            if !p.setFrameUsingName("PerchMiniPlayer"), let screen = NSScreen.main?.visibleFrame {
                p.setFrameOrigin(NSPoint(x: screen.maxX - 440 - 24, y: screen.minY + 24))
            }
            p.setFrameAutosaveName("PerchMiniPlayer")
            mini = p
        }
        mini?.orderFrontRegardless()
        store.setMiniVisible(true)
    }

    func closeMini() { mini?.close() }

    // MARK: Alert card

    func showAlert(event: DetectionEvent, image: NSImage?) {
        guard let store else { return }
        alertHide?.cancel()
        let hosting = NSHostingView(rootView: AnyView(AlertView(event: event, image: image).environmentObject(store)))
        var size = hosting.fittingSize
        if size.width < 10 || size.height < 10 { size = NSSize(width: 380, height: 330) }
        hosting.frame = NSRect(origin: .zero, size: size)

        let p: NSPanel
        if let existing = alert {
            p = existing
        } else {
            p = FloatingPanel(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.level = .statusBar
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            alert = p
        }
        p.contentView = hosting
        p.setContentSize(size)
        if let screen = NSScreen.main?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 12, y: screen.maxY - size.height - 12))
        }
        p.orderFrontRegardless()
        if store.alertSound {
            let sound = event.kind == .doorbell ? (NSSound(named: "Doorbell") ?? NSSound(named: "Glass")) : NSSound(named: "Glass")
            sound?.play()
        }

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.dismissAlert() }
        }
        alertHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (event.kind == .doorbell ? 30 : 15), execute: work)
    }

    func dismissAlert() {
        alertHide?.cancel()
        alert?.orderOut(nil)
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        if w === viewer {
            store?.setViewerVisible(false)
            // Back to living quietly in the menu bar.
            NSApp.setActivationPolicy(.accessory)
        }
        if w === mini { store?.setMiniVisible(false) }
    }
}
