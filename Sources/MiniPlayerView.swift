import SwiftUI
import AppKit

/// Small floating player that stays above other apps. Controls appear on hover.
struct MiniPlayerView: View {
    @EnvironmentObject var store: CameraStore
    @State private var hovering = false

    var body: some View {
        let ch = store.miniChannel
        ZStack {
            Color.black
            CameraTile(camera: Camera(channel: ch, name: store.name(for: ch)),
                       image: store.images[ch],
                       cornerRadius: 0,
                       fill: true,
                       showLabel: false,
                       rotation: store.rotation(for: ch))
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 7) {
                Circle().fill(store.isLive(ch) ? liveRed : Color.gray).frame(width: 7, height: 7)
                Text(store.name(for: ch))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .glass(9)
            .padding(10)
        }
        .overlay(alignment: .topTrailing) {
            if hovering {
                HStack(spacing: 2) {
                    IconButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Open in camera window") {
                        WindowManager.shared.showViewer(channel: ch, grid: false)
                    }
                    IconButton(symbol: "xmark", help: "Close mini player") {
                        WindowManager.shared.closeMini()
                    }
                }
                .padding(3)
                .glass(11)
                .padding(8)
            }
        }
        .overlay(alignment: .bottom) {
            if hovering {
                HStack(spacing: 3) {
                    ForEach(store.cameras) { cam in
                        Button { store.miniChannel = cam.channel } label: {
                            Text(cam.key)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(cam.channel == ch ? Color(white: 0.07) : Color.white)
                                .frame(width: 26, height: 24)
                                .background(cam.channel == ch ? Color.white.opacity(0.92) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(cam.name)
                    }
                }
                .padding(3)
                .glass(11)
                .padding(.bottom, 10)
            }
        }
        .onHover { inside in
            withAnimation(.easeInOut(duration: 0.15)) { hovering = inside }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .frame(minWidth: 280, minHeight: 158)
    }
}
