import SwiftUI
import AppKit

/// The card that slides in at the top right when someone is detected.
struct AlertView: View {
    let event: DetectionEvent
    let image: NSImage?
    @EnvironmentObject var store: CameraStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: event.kind.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(event.kind.color)
                    .frame(width: 36, height: 36)
                    .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Perch")
                        Spacer()
                        Text(event.date.formatted(date: .omitted, time: .shortened))
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.68))
                    Text(event.kind.headline(at: store.name(for: event.channel)))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(event.kind.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(white: 0.78))
                }
            }
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 356, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .rotationEffect(.degrees(0))
            }
            HStack(spacing: 8) {
                Button {
                    WindowManager.shared.dismissAlert()
                    WindowManager.shared.showMini(channel: event.channel)
                } label: {
                    Text("Watch live").frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(prominent: true))
                Button {
                    WindowManager.shared.dismissAlert()
                } label: {
                    Text("Dismiss").frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(prominent: false))
            }
        }
        .padding(12)
        .frame(width: 380)
        .background(Color(white: 0.11).opacity(0.97), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(event.kind == .doorbell ? event.kind.color.opacity(0.7) : Color.white.opacity(0.12),
                          lineWidth: event.kind == .doorbell ? 1.5 : 1))
        .environment(\.colorScheme, .dark)
    }
}
