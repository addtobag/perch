import SwiftUI
import AppKit
import CoreImage

/// The soft blurred picture behind a camera shown in "fit" mode.
/// Blurring the full-size video live on every frame is very expensive for the Mac's window
/// compositor, so instead a tiny, already-blurred copy is made at most every couple of seconds
/// and simply stretched to fill the space.
@MainActor
enum Backdrop {
    private static var cache: [String: (image: NSImage, madeAt: Date)] = [:]
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func image(for source: NSImage, key: String) -> NSImage? {
        let now = Date()
        if let hit = cache[key], now.timeIntervalSince(hit.madeAt) < 2 { return hit.image }
        guard let made = make(from: source) else { return cache[key]?.image }
        cache[key] = (made, now)
        return made
    }

    private static func make(from source: NSImage) -> NSImage? {
        guard let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cg.width > 0, cg.height > 0 else { return nil }
        let w = 64.0, h = max(1, (w * Double(cg.height) / Double(cg.width)).rounded())
        let small = CIImage(cgImage: cg)
            .transformed(by: CGAffineTransform(scaleX: w / Double(cg.width), y: h / Double(cg.height)))
        let blurred = small.clampedToExtent()
            .applyingGaussianBlur(sigma: 2.5)
            .cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = context.createCGImage(blurred, from: blurred.extent) else { return nil }
        return NSImage(cgImage: out, size: NSSize(width: w, height: h))
    }
}

/// Draws a frame rotated by 0/90/180/270 degrees, filling or fitting the space it's given.
struct RotatedImage: View {
    let image: NSImage
    let rotation: Int
    let fill: Bool

    var body: some View {
        GeometryReader { geo in
            let quarterTurn = rotation % 180 != 0
            let w = quarterTurn ? geo.size.height : geo.size.width
            let h = quarterTurn ? geo.size.width : geo.size.height
            Group {
                if fill {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Image(nsImage: image).resizable().scaledToFit()
                }
            }
            .frame(width: w, height: h)
            .clipped()
            .rotationEffect(.degrees(Double(rotation)))
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// One camera picture with an optional name chip and event badge.
/// With `aspect` set it keeps that shape; without it, it fills the frame it's given.
/// In fit mode with `blurBackground`, the empty space shows a soft blurred copy of the picture.
struct CameraTile: View {
    let camera: Camera
    let image: NSImage?
    var badge: EventBadge? = nil
    var cornerRadius: CGFloat = 10
    var aspect: CGFloat? = nil
    var fill = true
    var blurBackground = false
    var showLabel = true
    var compactLabel = false
    var active = false
    var rotation = 0
    var zoom: CGFloat = 1
    var pan: CGSize = .zero
    /// Identifies the picture for the blurred backdrop cache (defaults to the camera's channel).
    var backdropKey: String? = nil

    var body: some View {
        if let aspect {
            content.aspectRatio(aspect, contentMode: .fit)
        } else {
            content
        }
    }

    private var content: some View {
        Color(white: 0.04)
            .overlay {
                if let image {
                    ZStack {
                        if blurBackground && !fill,
                           let backdrop = Backdrop.image(for: image, key: backdropKey ?? "ch\(camera.channel)") {
                            RotatedImage(image: backdrop, rotation: rotation, fill: true)
                                .opacity(0.5)
                        }
                        RotatedImage(image: image, rotation: rotation, fill: fill)
                            .scaleEffect(zoom)
                            .offset(pan)
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if showLabel {
                    HStack(spacing: 6) {
                        Circle().fill(active ? DetectionEvent.Kind.person.color : liveRed)
                            .frame(width: 6, height: 6)
                        Text(camera.name)
                        Text(camera.key).opacity(0.5)
                    }
                    .font(.system(size: compactLabel ? 11 : 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, compactLabel ? 8 : 10)
                    .frame(height: compactLabel ? 22 : 26)
                    .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(compactLabel ? 8 : 10)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let badge {
                    HStack(spacing: 5) {
                        Circle().fill(badge.color).frame(width: 6, height: 6)
                        Text(badge.text)
                    }
                    .font(.system(size: compactLabel ? 11 : 12, weight: .semibold))
                    .foregroundStyle(badge.color)
                    .padding(.horizontal, compactLabel ? 7 : 10)
                    .frame(height: compactLabel ? 22 : 26)
                    .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(compactLabel ? 8 : 10)
                }
            }
            .contentShape(Rectangle())
    }
}
