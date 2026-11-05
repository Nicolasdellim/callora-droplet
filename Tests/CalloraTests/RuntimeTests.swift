import AppKit
import CoreGraphics
import ScreenCaptureKit
import CoreMedia
import SwiftUI
import Testing
@testable import Callora

@MainActor @Test func nativePanelCloseOnlyHidesPreview() {
    _ = NSApplication.shared
    let controller = FloatingWindowController()
    var closeRequests = 0
    controller.onHide = { closeRequests += 1; controller.hide() }
    controller.show(content: Text("Local preview test"), from: nil, settings: CalloraSettings())
    #expect(controller.panel != nil)
    #expect(controller.panel?.styleMask.contains(.nonactivatingPanel) == true)
    #expect(controller.panel?.styleMask.contains(.resizable) == true)
    #expect(controller.panel?.collectionBehavior.contains(.fullScreenAuxiliary) == true)
    controller.panel?.performClose(nil)
    #expect(closeRequests == 1)
    #expect(controller.panel == nil)
}

@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["CALLORA_CAPTURE_TEST"] == "1" && CGPreflightScreenCaptureAccess(), "Needs explicit opt-in and an existing Screen Recording grant; never prompts in tests."))
func realWindowCaptureAndTeardown() async throws {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 180, y: 200, width: 640, height: 360), styleMask: [.titled], backing: .buffered, defer: false)
    window.title = "Callora local capture test"
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: VStack(spacing: 20) {
        Image(systemName: "rectangle.on.rectangle").font(.system(size: 48))
        Text("Callora capture test").font(.title)
        Text("Generated local test window — no call or remote participant")
    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.gray.opacity(0.2)))
    window.orderFrontRegardless()
    defer { window.close() }
    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
    let source = try #require(content.windows.first { $0.windowID == CGWindowID(window.windowNumber) })
    let droplet = CalloraDroplet()
    let capture = droplet.capture
    await capture.start(window: source, settings: CalloraSettings())
    for _ in 0..<40 {
        if capture.frame != nil { break }
        try await Task.sleep(for: .milliseconds(100))
    }
    #expect(capture.isCapturing)
    #expect(capture.frame != nil)
    let firstFormat = try #require(capture.frame.flatMap { CMSampleBufferGetFormatDescription($0.sample) })
    let firstSize = CMVideoFormatDescriptionGetDimensions(firstFormat)
    window.setContentSize(NSSize(width: 800, height: 360))
    try await Task.sleep(for: .seconds(5))
    let resizedFormat = try #require(capture.frame.flatMap { CMSampleBufferGetFormatDescription($0.sample) })
    let resizedSize = CMVideoFormatDescriptionGetDimensions(resizedFormat)
    #expect(firstSize.height != resizedSize.height)
    let controller = FloatingWindowController()
    controller.show(content: FloatingCallView(droplet: droplet), from: nil, settings: CalloraSettings())
    #expect(controller.panel?.isVisible == true)
    controller.panel?.setContentSize(NSSize(width: 560, height: 315))
    #expect(controller.panel!.frame.width >= 560)
    if let output = ProcessInfo.processInfo.environment["CALLORA_TEST_SCREENSHOT"], let panel = controller.panel {
        try await Task.sleep(for: .milliseconds(500))
        let windows = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        let panelSource = try #require(windows.windows.first { $0.windowID == CGWindowID(panel.windowNumber) })
        let configuration = SCStreamConfiguration()
        configuration.width = 1120; configuration.height = 700; configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: panelSource), configuration: configuration)
        let bitmap = NSBitmapImageRep(cgImage: image)
        try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output))
    }
    controller.hide()
    await capture.stop()
    #expect(!capture.isCapturing)
    #expect(capture.frame == nil)
    #expect(capture.sourceName == nil)
    // Ending a preview did not terminate or close the original source window.
    #expect(window.isVisible)
}
