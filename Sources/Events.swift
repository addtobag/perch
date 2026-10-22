import SwiftUI
import Foundation

/// Something the NVR detected: a person, vehicle, animal or plain motion on a camera.
struct DetectionEvent: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case person, vehicle, animal, motion

        var label: String {
            switch self {
            case .person: return "Person"
            case .vehicle: return "Vehicle"
            case .animal: return "Animal"
            case .motion: return "Motion"
            }
        }

        var symbol: String {
            switch self {
            case .person: return "figure.walk"
            case .vehicle: return "car.fill"
            case .animal: return "pawprint.fill"
            case .motion: return "waveform.path"
            }
        }

        var color: Color {
            switch self {
            case .person: return Color(red: 1.0, green: 0.72, blue: 0.30)
            case .vehicle: return Color(red: 0.47, green: 0.74, blue: 1.0)
            case .animal: return Color(red: 0.52, green: 0.86, blue: 0.56)
            case .motion: return Color(white: 0.78)
            }
        }

        func title(at place: String) -> String {
            switch self {
            case .person: return "Person at \(place)"
            case .vehicle: return "Vehicle at \(place)"
            case .animal: return "Animal at \(place)"
            case .motion: return "Motion at \(place)"
            }
        }

        func headline(at place: String) -> String {
            switch self {
            case .person: return "Someone's at the \(place)"
            case .vehicle: return "A vehicle at the \(place)"
            case .animal: return "An animal at the \(place)"
            case .motion: return "Movement at the \(place)"
            }
        }
    }

    let id: UUID
    let channel: Int
    let kind: Kind
    let date: Date
}

/// A short label shown on a camera tile, e.g. "Person · 2m".
struct EventBadge {
    let text: String
    let color: Color
}

/// Keeps the last week of events (and a snapshot of each) on disk.
enum EventLog {
    static var folder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let base = support.appendingPathComponent("Perch/events", isDirectory: true)
        let old = support.appendingPathComponent("ReolinkViewer/events", isDirectory: true)
        if !FileManager.default.fileExists(atPath: base.path), FileManager.default.fileExists(atPath: old.path) {
            try? FileManager.default.createDirectory(at: base.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.moveItem(at: old, to: base)
        }
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static var indexURL: URL { folder.appendingPathComponent("events.json") }

    static func imageURL(for id: UUID) -> URL {
        folder.appendingPathComponent("\(id.uuidString).jpg")
    }

    static func load() -> [DetectionEvent] {
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? JSONDecoder().decode([DetectionEvent].self, from: data) else { return [] }
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        for old in list where old.date < cutoff {
            try? FileManager.default.removeItem(at: imageURL(for: old.id))
        }
        return list.filter { $0.date >= cutoff }
    }

    static func save(_ events: [DetectionEvent]) {
        if let data = try? JSONEncoder().encode(events) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    static func saveImage(_ data: Data, for id: UUID) {
        try? data.write(to: imageURL(for: id))
    }
}
