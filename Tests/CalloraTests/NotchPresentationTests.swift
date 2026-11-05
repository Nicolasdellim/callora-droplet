import AppKit
import CoreGraphics
import ScreenCaptureKit
import SwiftUI
import DroppyKit
import DroppyKitHarness
import Testing
@testable import Callora

@MainActor private func harness() throws -> (CalloraDroplet, HarnessSession) {
    _ = NSApplication.shared
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let manifest = try JSONDecoder().decode(DropletManifest.self, from: Data(contentsOf: root.appendingPathComponent("droplet.json")))
    let droplet = CalloraDroplet()
    let session = HarnessSession(droplet: droplet, manifest: manifest, manifestProblem: nil)
    session.activate()
    return (droplet, session)
}
private let activeCall = DetectionEvidence(bundleID: "test.provider", processID: -1, provider: "Local test call", windowID: "call", labels: ["Leave call", "Microphone", "Camera"])

@MainActor @Test func detectedCallPresentsInsideHostNotFloatingWindow() throws {
    let (droplet, harness) = try harness()
    defer { droplet.deactivate() }
    droplet.receive([activeCall], ended: [])
    #expect(harness.host.notchSurface.expandedState.current?.surfaceID.rawValue == "callora.call")
    #expect(droplet.floating.panel == nil)
    #expect(!droplet.isDetached)
    #expect(!harness.recorder.effects.contains { $0.wasRefused })
}

@MainActor @Test func dockReturnsToActualHostSurfaceAndDetectionDoesNotDetach() throws {
    let (droplet, harness) = try harness()
    defer { droplet.deactivate() }
    droplet.receive([activeCall], ended: [])
    droplet.detach()
    #expect(droplet.floating.panel != nil)
    #expect(harness.host.notchSurface.expandedState.current == nil)
    droplet.receive([activeCall], ended: [])
    #expect(droplet.isDetached)
    droplet.dock()
    #expect(harness.host.notchSurface.expandedState.current?.surfaceID.rawValue == "callora.call")
    #expect(!droplet.isDetached)
}

@MainActor @Test func frenchIncomingThenAcceptedCallStaysInNotch() throws {
    let (droplet, harness) = try harness()
    defer { droplet.deactivate() }
    let incoming = DetectionEvidence(bundleID: "test.provider", processID: -1, provider: "Local test call", windowID: "call", labels: ["Répondre", "Refuser"])
    #expect(incoming.detectedPhase == .incoming)
    droplet.receive([incoming], ended: [])
    #expect(droplet.selected?.phase == .incoming)
    #expect(droplet.selected?.startedAt == nil)
    #expect(harness.host.notchSurface.expandedState.current?.surfaceID.rawValue == "callora.call")
    let accepted = DetectionEvidence(bundleID: "test.provider", processID: -1, provider: "Local test call", windowID: "call", labels: ["Raccrocher", "Désactiver le microphone", "Désactiver la caméra"])
    #expect(accepted.detectedPhase == .active)
    droplet.receive([accepted], ended: [])
    #expect(droplet.selected?.phase == .active)
    #expect(droplet.floating.panel == nil)
    droplet.receive([], ended: ["-1:call"])
    #expect(harness.host.notchSurface.expandedState.current == nil)
}

@Test func notchDefaultsPreserveExistingFloatingWindowPreferences() throws {
    let oldJSON = Data(#"{"detectionEnabled":false,"opacity":0.65,"panelFrame":[10,20,400,280]}"#.utf8)
    let settings = try JSONDecoder().decode(CalloraSettings.self, from: oldJSON)
    #expect(settings.automaticallyPresentCalls)
    #expect(!settings.detectionEnabled)
    #expect(settings.opacity == 0.65)
    #expect(settings.panelFrame == [10, 20, 400, 280])
}

@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["CALLORA_CAPTURE_TEST"] == "1" && CGPreflightScreenCaptureAccess(), "Opt-in real window capture; requires an existing Screen Recording grant."))
func selectedVideoCapturesInNotchWithoutAnyShelfWidgetOrPanel() async throws {
    let (droplet, host) = try harness()
    defer { droplet.deactivate() }
    let window = NSWindow(contentRect: NSRect(x: 180, y: 180, width: 640, height: 360), styleMask: [.titled], backing: .buffered, defer: false)
    window.title = "Generated local Callora notch capture test"
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: Text("Local test source, no live call").frame(width: 640, height: 360))
    window.orderFrontRegardless()
    defer { window.close() }
    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
    let source = try #require(content.windows.first { $0.windowID == CGWindowID(window.windowNumber) })
    droplet.selectSource(source)
    #expect(host.host.notchSurface.expandedState.current?.surfaceID.rawValue == "callora.call")
    #expect(droplet.floating.panel == nil)
    for _ in 0..<40 {
        if droplet.capture.frame != nil { break }
        try await Task.sleep(for: .milliseconds(100))
    }
    #expect(droplet.capture.frame != nil)
    #expect(droplet.capture.isCapturing)
    droplet.hidePreview()
    #expect(host.host.notchSurface.expandedState.current == nil)
    for _ in 0..<30 {
        if !droplet.capture.isCapturing { break }
        try await Task.sleep(for: .milliseconds(100))
    }
    #expect(!droplet.capture.isCapturing)
    #expect(window.isVisible)
}
