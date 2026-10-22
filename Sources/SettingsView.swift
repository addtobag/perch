import SwiftUI
import AppKit
import ServiceManagement

/// Setup: NVR connection, cameras, the all-cameras view, overlays and alerts.
struct SettingsView: View {
    @EnvironmentObject var store: CameraStore
    @State private var testResult: String?
    @State private var testing = false
    @State private var overlayResult: String?
    @State private var applyingOverlays = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var detectResult: String?

    var body: some View {
        Form {
            Section("Connection") {
                TextField("NVR address", text: $store.host, prompt: Text("192.168.1.xxx"))
                TextField("Username", text: $store.username)
                SecureField("Password", text: $store.password)
                HStack {
                    Text("Saved in your Mac's Keychain. A view-only NVR user is safest.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(testing ? "Testing…" : "Test connection") {
                        testing = true
                        Task {
                            testResult = await store.testConnection()
                            testing = false
                        }
                    }
                    .disabled(testing)
                }
                if let testResult {
                    Text(testResult).font(.caption)
                }
                if !store.liveVideoAvailable {
                    Text("For smooth live video, install ffmpeg:  brew install ffmpeg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Cameras") {
                HStack {
                    Text("Perch reads the camera list and names from your NVR.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(store.detecting ? "Detecting…" : "Detect cameras") {
                        Task { detectResult = await store.detectCameras() }
                    }
                    .disabled(store.detecting || !store.isConfigured)
                }
                if let detectResult {
                    Text(detectResult).font(.caption)
                }
                ForEach(0..<store.names.count, id: \.self) { i in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { store.cameras.contains { $0.channel == i } },
                            set: { store.setCameraActive(i, $0) }
                        ))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .help("Use this channel")
                        TextField("Channel \(i + 1)", text: $store.names[i])
                        Picker("", selection: Binding(
                            get: { store.fitOverrides[i].map { $0 ? 1 : 2 } ?? 0 },
                            set: { store.setFill(i, $0 == 0 ? nil : ($0 == 1)) }
                        )) {
                            Text("Default").tag(0)
                            Text("Fill").tag(1)
                            Text("Fit").tag(2)
                        }
                        .labelsHidden()
                        .frame(width: 100)
                        .help("Crop this camera to fill its space, or always show the whole picture")
                    }
                }
            }

            Section("All cameras view") {
                Picker("Layout", selection: $store.gridLayout) {
                    ForEach(GridLayout.allCases) { layout in
                        Text(layout.label).tag(layout)
                    }
                }
                if store.gridLayout == .focus {
                    Picker("Large camera", selection: $store.focusChannel) {
                        ForEach(store.cameras) { cam in
                            Text(cam.name).tag(cam.channel)
                        }
                    }
                }
                Picker("Spacing", selection: $store.gridSpacing) {
                    Text("None").tag(0.0)
                    Text("Thin").tag(2.0)
                    Text("Roomy").tag(10.0)
                }
                .pickerStyle(.segmented)
                Toggle("Show camera names", isOn: $store.gridShowNames)
                Toggle("Show latest detection on each camera", isOn: $store.gridShowBadges)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Order and visibility")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    let order = store.orderedChannels
                    ForEach(order, id: \.self) { ch in
                        HStack {
                            Toggle(isOn: Binding(
                                get: { !store.gridHidden.contains(ch) },
                                set: { store.setShownInGrid(ch, $0) }
                            )) {
                                Text(store.name(for: ch))
                            }
                            .toggleStyle(.checkbox)
                            Spacer()
                            Button { store.moveInGrid(ch, by: -1) } label: {
                                Image(systemName: "chevron.up")
                            }
                            .buttonStyle(.borderless)
                            .disabled(order.first == ch)
                            .help("Move earlier")
                            Button { store.moveInGrid(ch, by: 1) } label: {
                                Image(systemName: "chevron.down")
                            }
                            .buttonStyle(.borderless)
                            .disabled(order.last == ch)
                            .help("Move later")
                        }
                    }
                }
            }

            Section("Video quality") {
                Picker("One camera", selection: $store.singleQuality) {
                    ForEach(StreamQuality.allCases) { q in
                        Text(q.label).tag(q)
                    }
                }
                Picker("All cameras", selection: $store.gridQuality) {
                    ForEach(StreamQuality.allCases) { q in
                        Text(q.label).tag(q)
                    }
                }
                Text("Low uses each camera's light sub stream. High and Maximum use the full stream, which looks sharper on big screens but uses more network and battery.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Camera overlays") {
                Toggle("Show date and time on the picture", isOn: $store.osdTime)
                Toggle("Show camera name on the picture", isOn: $store.osdName)
                HStack {
                    Text("Changes the cameras themselves, so recordings change too. Needs an NVR login that can change settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(applyingOverlays ? "Applying…" : "Apply to cameras") {
                        applyingOverlays = true
                        Task {
                            overlayResult = await store.applyOverlays()
                            applyingOverlays = false
                        }
                    }
                    .disabled(applyingOverlays || !store.isConfigured)
                }
                if let overlayResult {
                    Text(overlayResult).font(.caption)
                }
            }

            Section("Alerts") {
                Toggle("Show an alert when something is detected", isOn: $store.alertsEnabled)
                Toggle("People", isOn: $store.alertPeople).disabled(!store.alertsEnabled)
                Toggle("Vehicles", isOn: $store.alertVehicles).disabled(!store.alertsEnabled)
                Toggle("Animals", isOn: $store.alertAnimals).disabled(!store.alertsEnabled)
                Toggle("Any motion (cameras without person detection)", isOn: $store.alertMotion).disabled(!store.alertsEnabled)
                Toggle("Play a sound", isOn: $store.alertSound).disabled(!store.alertsEnabled)
            }

            Section("General") {
                Picker("Menu bar panel refresh", selection: $store.panelInterval) {
                    Text("1s").tag(1.0)
                    Text("2s").tag(2.0)
                    Text("5s").tag(5.0)
                }
                .pickerStyle(.segmented)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            testResult = "Couldn't change launch at login: \(error.localizedDescription)"
                        }
                    }
            }

            HStack {
                Spacer()
                Button("Cancel") { NSApp.keyWindow?.close() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    store.save()
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 720)
    }
}
