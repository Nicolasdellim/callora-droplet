import DroppyKit
import SwiftUI

struct CalloraSettingsView: View {
    @ObservedObject var droplet: CalloraDroplet
    private func binding<Value>(_ keyPath: WritableKeyPath<CalloraSettings, Value>) -> Binding<Value> {
        Binding(get: { droplet.settings[keyPath: keyPath] }, set: { value in droplet.changeSettings { $0[keyPath: keyPath] = value } })
    }
    var body: some View {
        DropletSettingsPane {
            DropletSettingsSection { settingsSectionHeader("General") } content: {
                DropletSettingsCard {
                    DropletToggleRow(title: "Enable Callora", isOn: binding(\.enabled))
                    DropletToggleRow(title: "Experimental call detection", subtitle: "Uses accessible call controls; English interfaces only.", isOn: binding(\.detectionEnabled))
                    DropletToggleRow(title: "Keep activity beside other activities", isOn: binding(\.persistentActivity))
                    DropletToggleRow(title: "Show duration", isOn: binding(\.showDuration))
                }
            }
            DropletSettingsSection { settingsSectionHeader("Video source") } content: {
                DropletSettingsCard {
                    DropletControlRow(title: "Window capture", infoTip: "Only your selected window is shared with Callora.") {
                        Button(droplet.isLoadingWindows ? "Refreshing…" : "Refresh sources", action: droplet.refreshSources)
                            .disabled(!droplet.canCapture || droplet.isLoadingWindows).buttonStyle(.bordered)
                    }
                    ForEach(droplet.availableWindows, id: \.windowID) { window in
                        DropletControlRow(title: window.owningApplication?.applicationName ?? "Application", infoTip: window.title ?? "Window") {
                            Button("Use window") { droplet.selectSource(window) }.buttonStyle(.bordered)
                        }
                    }
                    if let message = droplet.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                    DropletControlRow(title: "Frame rate") {
                        Picker("Frame rate", selection: binding(\.frameRate)) {
                            ForEach([10, 15, 30], id: \.self) { Text("\($0) fps").tag($0) }
                        }.labelsHidden()
                    }
                    DropletControlRow(title: "Crop region", infoTip: "Values are fractions of the source window.") {
                        Button("Reset") { droplet.changeSettings { $0.crop = NormalizedCrop() } }.buttonStyle(.bordered)
                    }
                    cropSlider("Left", keyPath: \.x)
                    cropSlider("Top", keyPath: \.y)
                    cropSlider("Width", keyPath: \.width)
                    cropSlider("Height", keyPath: \.height)
                }
            }
            DropletSettingsSection { settingsSectionHeader("Floating window") } content: {
                DropletSettingsCard {
                    DropletToggleRow(title: "Always on top", isOn: binding(\.alwaysOnTop))
                    DropletToggleRow(title: "Remember position and size", isOn: binding(\.rememberPosition))
                    DropletToggleRow(title: "Snap to edges", isOn: binding(\.snapToEdges))
                    DropletSliderRow(title: "Opacity", value: "\(Int(droplet.settings.opacity * 100))%", binding: binding(\.opacity), range: 0.4...1)
                    DropletControlRow(title: "Layout") {
                        Picker("Layout", selection: binding(\.layout)) {
                            ForEach(PanelLayout.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.labelsHidden()
                    }
                    DropletControlRow(title: "Preview", infoTip: "Hiding this preview never ends your call.") {
                        Button(droplet.isDetached ? "Dock to notch" : "Detach preview") {
                            droplet.isDetached ? droplet.dock() : droplet.detach()
                        }.disabled(droplet.selected == nil).buttonStyle(.bordered)
                    }
                }
            }
            DropletSettingsSection { settingsSectionHeader("Integrations") } content: {
                DropletSettingsCard {
                    ForEach(ProviderRegistry.providers) { provider in
                        DropletControlRow(title: provider.name, infoTip: provider.automatic ? "Experimental detection; manual window video." : "Manual window selection; call controls unavailable.") {
                            Image(systemName: provider.automatic ? "accessibility" : "rectangle.dashed")
                        }
                    }
                    if let selected = droplet.selected {
                        DropletControlRow(title: "Selected session", infoTip: selected.manual ? "Manually associated; not verified by the provider." : "Inferred from controls; not live validated.") {
                            if selected.manual { Button("Forget session", action: droplet.forgetSession).buttonStyle(.bordered) }
                        }
                    }
                }
            }
            DropletSettingsSection { settingsSectionHeader("Privacy and shortcuts") } content: {
                DropletSettingsCard {
                    permissionRow("Screen Recording", granted: droplet.screenCaptureGranted, permission: .screenCapture)
                    permissionRow("Accessibility", granted: droplet.accessibilityGranted, permission: .accessibility)
                    DropletControlRow(title: "Capture status", infoTip: "No recording, microphone capture, analytics or uploads.") {
                        Text(droplet.capture.isCapturing ? "Sharing selected window" : "Off").font(.caption)
                    }
                    DropletControlRow(title: "Keyboard shortcuts", infoTip: "No defaults; Droppy manages bindings and conflicts.") {
                        Button("Configure", action: droplet.openShortcuts).buttonStyle(.bordered)
                    }
                    DropletControlRow(title: "Local preferences") {
                        Button("Reset preferences") { droplet.changeSettings { $0 = CalloraSettings() } }.buttonStyle(.bordered)
                    }
                }
            }
        }
        .onAppear { droplet.refreshPermissions() }
    }
    private func permissionRow(_ title: String, granted: Bool, permission: DropletPermission) -> some View {
        DropletControlRow(title: title, infoTip: granted ? "Allowed for the host application." : "Required only for this feature.") {
            Button(granted ? "Check" : "Allow") { Task { await droplet.requestPermission(permission) } }.buttonStyle(.bordered)
        }
    }
    private func cropSlider(_ title: String, keyPath: WritableKeyPath<NormalizedCrop, Double>) -> some View {
        let value = droplet.settings.crop[keyPath: keyPath]
        return DropletSliderRow(title: title, value: "\(Int(value * 100))%", binding: Binding(get: {
            droplet.settings.crop[keyPath: keyPath]
        }, set: { value in
            droplet.changeSettings {
                var c = $0.crop; c[keyPath: keyPath] = value
                $0.crop = NormalizedCrop(x: c.x, y: c.y, width: c.width, height: c.height)
            }
        }), range: keyPath == \.x || keyPath == \.y ? 0...0.95 : 0.05...1)
    }
}
