import SwiftUI
import AppKit

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
                        if blurBackground && !fill {
                            RotatedImage(image: image, rotation: rotation, fill: true)
                                .blur(radius: 40)
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
