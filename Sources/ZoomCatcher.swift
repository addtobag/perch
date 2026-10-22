import SwiftUI
import AppKit

/// Transparent layer over the live picture: mouse wheel / pinch zoom, drag to pan
/// (or move the window when not zoomed), double-click, and mouse movement.
struct ZoomCatcher: NSViewRepresentable {
    var isZoomed: Bool
    var onZoom: (CGFloat, CGPoint) -> Void      // factor, point (top-left origin)
    var onDrag: (CGSize) -> Void
    var onDoubleClick: () -> Void
    var onMove: () -> Void

    final class CatcherView: NSView {
        var owner: ZoomCatcher?
        private var tracking: NSTrackingArea?

        override var isFlipped: Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(rect: bounds,
                                      options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil)
            addTrackingArea(area)
            tracking = area
        }

        override func mouseMoved(with event: NSEvent) {
            owner?.onMove()
        }

        override func scrollWheel(with event: NSEvent) {
            var dy = event.scrollingDeltaY
            if event.isDirectionInvertedFromDevice { dy = -dy }
            let step: CGFloat = event.hasPreciseScrollingDeltas ? 0.01 : 0.12
            owner?.onZoom(exp(dy * step), convert(event.locationInWindow, from: nil))
            owner?.onMove()
        }

        override func magnify(with event: NSEvent) {
            owner?.onZoom(1 + event.magnification, convert(event.locationInWindow, from: nil))
        }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                owner?.onDoubleClick()
            } else if !(owner?.isZoomed ?? false) {
                window?.performDrag(with: event)
            }
        }

        override func mouseDragged(with event: NSEvent) {
            owner?.onDrag(CGSize(width: event.deltaX, height: event.deltaY))
        }
    }

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.owner = self
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.owner = self
    }
}
